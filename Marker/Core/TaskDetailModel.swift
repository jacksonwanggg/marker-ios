import Foundation
import Observation
import PDFKit

enum Load<T> {
    case idle, loading, done(T), failed(String)

    var value: T? { if case .done(let v) = self { return v } else { return nil } }
    var isIdle: Bool { if case .idle = self { return true } else { return false } }
}

enum SubmissionState {
    case none
    case noUploads
    case noPDF // submitted but no PDF, regenerating usually fixes it
    case processing
    case pdf(PDFDocument, name: String)
}

@MainActor @Observable
final class TaskDetailModel {
    let key: TaskKey
    let unitID: Int
    private let model: AppModel
    private var backend: any MarkerBackend { model.backend }

    var submission: Load<SubmissionState> = .idle
    var files: Load<FileBundle?> = .idle
    var sheet: Load<PDFDocument?> = .idle
    var resources: Load<FileBundle?> = .idle
    var comments: Load<[Comment]> = .idle
    var sending = false
    var draft = "" // lives here so a half-typed comment survives tab switches
    var sendError: String?
    var replyTo: Comment?
    private var nextLocalID = -1

    init(key: TaskKey, unitID: Int, model: AppModel) {
        self.key = key
        self.unitID = unitID
        self.model = model
    }

    func loadSubmission(force: Bool = false) async {
        guard force || submission.isIdle else { return }
        if model.taskDef(key.taskDefID)?.hasUploads == false {
            submission = .done(.noUploads)
            return
        }
        submission = .loading
        let b = backend, k = key
        do {
            let d = try await b.submissionDetails(k)
            // a fresh upload reports has_pdf false while Formatif is still building it
            if d.processingPdf == true {
                submission = .done(.processing)
                return
            }
            guard d.hasPdf == true else {
                submission = .done(d.submissionDate == nil ? .none : .noPDF)
                return
            }
            let data = try await b.submissionPDF(k)
            guard let doc = PDFDocument(data: data) else { submission = .failed("The PDF couldn't be opened."); return }
            let name = "\(model.zid(k.projectID))-\(model.taskDef(k.taskDefID)?.abbreviation ?? "task").pdf"
            submission = .done(.pdf(doc, name: name))
        } catch {
            submission = .failed(model.message(error))
            model.handle(error, quiet: true)
        }
    }

    func regeneratePDF() async {
        let b = backend, k = key
        do {
            try await b.regeneratePDF(k)
            model.show("PDF regeneration requested")
            await loadSubmission(force: true)
        } catch {
            model.show(model.message(error), error: true)
        }
    }

    func loadFiles() async {
        guard files.isIdle else { return }
        if model.taskDef(key.taskDefID)?.hasUploads == false {
            files = .done(nil)
            return
        }
        files = .loading
        let b = backend, k = key
        do { files = .done(try await b.submissionFiles(k)) } catch { files = .failed(model.message(error)) }
    }

    func loadSheet(hasSheet: Bool) async {
        guard sheet.isIdle else { return }
        guard hasSheet else { sheet = .done(nil); return }
        sheet = .loading
        let b = backend, u = unitID, td = key.taskDefID
        do {
            let data = try await b.taskSheet(unitID: u, taskDefID: td)
            sheet = .done(Zip.isPDF(data) ? PDFDocument(data: data) : nil)
        } catch {
            sheet = .failed(model.message(error))
        }
    }

    func loadResources() async {
        guard resources.isIdle else { return }
        resources = .loading
        let b = backend, u = unitID, td = key.taskDefID
        do {
            resources = .done(try await b.taskResources(unitID: u, taskDefID: td))
        } catch {
            resources = .failed(model.message(error))
        }
    }

    func loadComments(force: Bool = false) async {
        guard force || comments.isIdle else { return }
        if comments.value == nil { comments = .loading }
        let b = backend, k = key
        do {
            comments = .done(try await b.comments(k))
            model.markRead(k)
        } catch {
            if comments.value == nil { comments = .failed(model.message(error)) }
            model.handle(error, quiet: true)
        }
    }

    private func send(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sending else { return false }
        sending = true
        sendError = nil
        defer { sending = false }
        let reply = replyTo
        let local = localComment(text: trimmed, replyTo: reply?.id)
        append(local)
        replyTo = nil
        let b = backend, k = key
        do {
            let saved = try await b.postComment(k, text: trimmed, replyTo: reply?.id)
            replace(local.id, with: saved)
            model.haptic += 1
            return true
        } catch {
            remove(local.id)
            replyTo = reply
            sendError = model.message(error)
            return false
        }
    }

    func sendDraft() async -> Bool {
        let t = draft
        draft = ""
        if await send(t) { return true }
        draft = t
        return false
    }

    func sendAttachment(filename: String, mimeType: String, data: Data) async {
        guard !sending else { return }
        sending = true
        sendError = nil
        defer { sending = false }
        let b = backend, k = key
        do {
            let saved = try await b.postAttachment(k, filename: filename, mimeType: mimeType, data: data)
            append(saved)
            model.haptic += 1
        } catch {
            sendError = model.message(error)
        }
    }

    func delete(_ c: Comment) async {
        let b = backend, k = key
        do {
            try await b.deleteComment(k, id: c.id)
            remove(c.id)
            model.show("Comment deleted")
        } catch {
            model.show(model.message(error), error: true)
        }
    }

    func attachment(_ c: Comment) async -> URL? {
        let b = backend, k = key
        do {
            let file = try await b.commentAttachment(k, id: c.id)
            var name = file.filename
            if (name as NSString).pathExtension.isEmpty {
                let isPDF = file.mimeType == "application/pdf" || c.kind == "pdf"
                let ext = isPDF ? "pdf" : c.kind == "audio" ? "m4a" : "jpg"
                name = "attachment-\(c.id).\(ext)"
            }
            return TempFiles.write(file.data, name: name)
        } catch {
            model.show(model.message(error), error: true)
            return nil
        }
    }

    func decideExtension(_ c: Comment, granted: Bool) async {
        let b = backend, k = key
        do {
            try await b.assessExtension(k, commentID: c.id, granted: granted)
            model.extensionDecided(k)
            model.show(granted ? "Extension granted" : "Extension denied")
            await loadComments(force: true)
        } catch {
            model.show(model.message(error), error: true)
        }
    }

    // Formatif posts a comment for every status change
    func statusChanged() async {
        if comments.value != nil { await loadComments(force: true) }
    }

    private func localComment(text: String, replyTo: Int?) -> Comment {
        nextLocalID -= 1
        let me = model.myUserID.map { UserRef(id: $0, firstName: model.credentials?.firstName, lastName: model.credentials?.lastName) }
        return Comment(id: nextLocalID, comment: text, hasAttachment: false, type: "text", isNew: false, replyToId: replyTo,
                       author: me, recipient: nil, createdAt: Date.now.formatted(Date.ISO8601FormatStyle()))
    }

    private func append(_ c: Comment) { comments = .done((comments.value ?? []) + [c]) }
    private func remove(_ id: Int) { comments = .done((comments.value ?? []).filter { $0.id != id }) }
    private func replace(_ id: Int, with c: Comment) {
        comments = .done((comments.value ?? []).map { $0.id == id ? c : $0 })
    }
}
