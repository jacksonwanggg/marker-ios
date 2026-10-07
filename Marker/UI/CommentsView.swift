import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct CommentsTab: View {
    @Environment(AppModel.self) private var model
    let detail: TaskDetailModel
    @State private var selected: Int?
    @State private var preview: URL?
    @State private var confirmDelete: Comment?

    var body: some View {
        Group {
            switch detail.comments {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let msg):
                EmptyState(title: "Couldn't load comments.", detail: msg, action: "Try again") {
                    Task { await detail.loadComments(force: true) }
                }
            case .done(let list):
                if list.isEmpty {
                    EmptyState(title: "No comments yet.", detail: "Anything you send goes straight to the student.")
                } else {
                    thread(list)
                }
            }
        }
        .task { await detail.loadComments() }
        .quickLookPreview($preview)
        .confirmationDialog("Delete this comment?",
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible, presenting: confirmDelete) { c in
            Button("Delete", role: .destructive) { Task { await detail.delete(c) } }
        } message: { _ in
            Text("It's removed from Formatif for you and the student.")
        }
    }

    private func thread(_ list: [Comment]) -> some View {
        let byID = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(list) { c in
                        row(c, replyTo: c.replyToId.flatMap { byID[$0] }).id(c.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: list.count) { _, _ in
                if let last = list.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    @ViewBuilder
    private func row(_ c: Comment, replyTo: Comment?) -> some View {
        let mine = c.author?.id == model.myUserID && model.myUserID != nil
        switch c.kind {
        case "status":
            Text(statusLine(c, mine: mine))
                .font(.caption).monospacedDigit().foregroundStyle(Palette.fg2)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.vertical, 8)
        case "extension":
            ExtensionCard(comment: c, mine: mine) { granted in
                Task { await detail.decideExtension(c, granted: granted) }
            }
        default:
            bubble(c, mine: mine, replyTo: replyTo)
        }
    }

    private func statusLine(_ c: Comment, mine: Bool) -> String {
        let s = TaskStatus(key: c.status ?? c.taskStatus)
        let who = mine ? "You" : (c.author?.first ?? "Someone")
        let what = !mine && s == .readyForFeedback
            ? "\(who) submitted · Ready for feedback"
            : "\(who) set the status to \(s.label)"
        return "\(what) · \(Fmt.thread(c.created))"
    }

    private func bubble(_ c: Comment, mine: Bool, replyTo: Comment?) -> some View {
        let isSelected = selected == c.id
        let pending = c.id < 0
        let caption = meta(c, mine: mine, pending: pending)
        let shape = UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: mine ? 18 : 4,
                                           bottomTrailingRadius: mine ? 4 : 18, topTrailingRadius: 18)
        return VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 6) {
                if let replyTo {
                    Text(replyTo.comment ?? "Attachment")
                        .font(.footnote)
                        .lineLimit(1)
                        .padding(.leading, 8)
                        .overlay(alignment: .leading) { Rectangle().frame(width: 2) }
                        .opacity(0.8)
                }
                if c.isAttachment {
                    HStack(spacing: 8) {
                        Image(systemName: c.kind == "image" ? "photo" : c.kind == "audio" ? "waveform" : "paperclip")
                        Text(c.comment?.isEmpty == false && c.kind != "text" ? c.comment! : attachmentLabel(c))
                            .font(.footnote.monospaced())
                    }
                } else {
                    Text(c.comment ?? "")
                }
            }
            .font(.system(size: 16))
            .foregroundStyle(mine ? Palette.accOn : Palette.fg)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(mine ? Palette.acc : Palette.fill, in: shape)
            .overlay {
                if isSelected { shape.strokeBorder(Palette.fg, lineWidth: 2).padding(-3) }
            }
            .opacity(pending ? 0.6 : 1)
            .frame(maxWidth: 300, alignment: mine ? .trailing : .leading)
            .onTapGesture { if !pending { selected = isSelected ? nil : c.id } }
            .contextMenu {
                if let text = c.comment, !c.isAttachment {
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                }
                if !mine { Button("Reply", systemImage: "arrowshape.turn.up.left") { detail.replyTo = c } }
                if c.isAttachment, !pending { Button("Open", systemImage: "eye") { open(c) } }
                if mine, !pending { Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = c } }
            }

            Text(caption)
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.fg2)
                .padding(.horizontal, 6)

            if isSelected {
                HStack(spacing: 8) {
                    if !mine { actionButton("Reply") { detail.replyTo = c; selected = nil } }
                    if c.isAttachment { actionButton("Open") { open(c) } }
                    if mine { actionButton("Delete", destructive: true) { confirmDelete = c; selected = nil } }
                }
                .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mine ? "You" : c.author?.first ?? "Student"): \(c.comment ?? attachmentLabel(c)). \(caption)")
        .accessibilityAction(named: "Show actions") { selected = c.id }
    }

    private func open(_ c: Comment) {
        Task { preview = await detail.attachment(c) }
    }

    private func attachmentLabel(_ c: Comment) -> String {
        switch c.kind { case "image": "Image"; case "audio": "Audio"; case "pdf": "PDF"; default: "Attachment" }
    }

    private func meta(_ c: Comment, mine: Bool, pending: Bool) -> String {
        if pending { return "Sending…" }
        guard mine else { return Fmt.thread(c.created) }
        if let read = Fmt.parse(c.recipientReadTime) { return "Read \(Fmt.thread(read))" }
        return "Delivered · \(Fmt.thread(c.created))"
    }

    private func actionButton(_ title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(destructive ? Palette.err : Palette.fg)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .overlay(Capsule().strokeBorder(Palette.hair))
            .buttonStyle(.plain)
    }
}

struct ExtensionCard: View {
    let comment: Comment
    let mine: Bool
    let decide: (Bool) -> Void
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let weeks = comment.weeksRequested ?? 1
            Text("Extension request · \(weeks) week\(weeks == 1 ? "" : "s")".uppercased())
                .font(.caption.weight(.bold)).kerning(0.4).foregroundStyle(Palette.fg2)
            if let text = comment.comment, !text.isEmpty { Text(text).font(.subheadline) }
            Text("\(comment.author?.first ?? "Student") · \(Fmt.thread(comment.created))")
                .font(.footnote).monospacedDigit().foregroundStyle(Palette.fg2)
            if comment.assessed ?? false {
                Text(verdict)
                    .font(.footnote.weight(.semibold))
                    .padding(.top, 6)
            } else if !mine {
                HStack(spacing: 8) {
                    Button {
                        busy = true
                        decide(true)
                    } label: {
                        Text("Grant").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        busy = true
                        decide(false)
                    } label: {
                        Text("Deny").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(busy)
                .padding(.top, 8)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.hair))
        .padding(.vertical, 4)
    }

    private var verdict: String {
        let result = (comment.granted ?? false) ? "Granted" : "Denied"
        guard let date = Fmt.parse(comment.dateAssessed) else { return result }
        return "\(result) · \(Fmt.thread(date))"
    }
}

struct Composer: View {
    @Environment(AppModel.self) private var model
    @Bindable var detail: TaskDetailModel
    // the text put back after a failed send, so only an edit clears the error
    @State private var restored: String?
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var photo: PhotosPickerItem?
    @FocusState private var focused: Bool

    private var canSend: Bool { !detail.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !detail.sending }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let r = detail.replyTo {
                HStack {
                    Text("Replying to “\(r.comment ?? "attachment")”").lineLimit(1)
                    Spacer()
                    Button("Cancel") { detail.replyTo = nil }.fontWeight(.semibold)
                }
                .font(.footnote)
                .foregroundStyle(Palette.fg2)
                .padding(.horizontal, 4)
            }
            if let err = detail.sendError {
                Text(err).font(.footnote).foregroundStyle(Palette.err).padding(.horizontal, 4)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button("Photo Library", systemImage: "photo") { showPhotos = true }
                    Button("Files", systemImage: "folder") { showFiles = true }
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.fg2)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(Palette.hair))
                }
                .accessibilityLabel("Attach a file")

                TextField("Comment", text: $detail.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textInputAutocapitalization(model.prefs.capitaliseComments ? .sentences : .never)
                    .focused($focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(minHeight: 36)
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.hair))
                    .onChange(of: detail.draft) { _, new in
                        if new != restored, detail.sendError != nil {
                            detail.sendError = nil
                            restored = nil
                        }
                    }

                Button(action: send) {
                    Group {
                        if detail.sending {
                            ProgressView().tint(Palette.accOn)
                        } else {
                            Image(systemName: "arrow.up").font(.body.weight(.bold))
                        }
                    }
                    .foregroundStyle(canSend ? Palette.accOn : Palette.fg3)
                    .frame(width: 36, height: 36)
                    .background(canSend ? Palette.acc : Palette.fill, in: Circle())
                }
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task {
                guard let raw = try? await item.loadTransferable(type: Data.self) else { return }
                let jpeg = UIImage(data: raw)?.jpegData(compressionQuality: 0.85) ?? raw
                await detail.sendAttachment(filename: "photo.jpg", mimeType: "image/jpeg", data: jpeg)
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image, .plainText, .data]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let name = url.lastPathComponent
            Task { await detail.sendAttachment(filename: name, mimeType: mime, data: data) }
        }
    }

    private func send() {
        let text = detail.draft
        restored = nil
        Task {
            if !(await detail.sendDraft()) { restored = text }
        }
    }
}
