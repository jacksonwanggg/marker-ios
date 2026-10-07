import Foundation
import Testing
@testable import Marker

/// Saved responses from a live unit. They hold real student data, so they stay outside the repo.
enum LiveData {
    static let dir = ProcessInfo.processInfo.environment["MARKER_LIVE_DIR"].map { URL(fileURLWithPath: $0) }
    static let captures = ProcessInfo.processInfo.environment["MARKER_CAPTURES_DIR"].map { URL(fileURLWithPath: $0) }

    static func data(_ name: String) throws -> Data { try Data(contentsOf: dir!.appendingPathComponent(name)) }
    static func decode<T: Decodable>(_ t: T.Type, _ name: String) throws -> T { try JSON.decoder().decode(T.self, from: data(name)) }
    /// Same lenient list decoding as LiveBackend.
    static func list<T: Decodable & Sendable>(_ t: T.Type, _ name: String) throws -> [T] { try decode(LossyList<T>.self, name).items }
    static func files(prefix: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir!.path)) ?? []).filter { $0.hasPrefix(prefix) }.sorted()
    }
}

struct FileBackend: MarkerBackend {
    var isDemo: Bool { false }
    private func no<T>() throws -> T { throw APIError.badResponse("not in the saved responses") }
    func unitRoles() async throws -> [UnitRole] { try LiveData.list(UnitRole.self, "unit_roles.json") }
    func unit(_ id: Int) async throws -> UnitDetail { try LiveData.decode(UnitDetail.self, "unit.json") }
    func students(unitID: Int) async throws -> [ProjectSummary] { try LiveData.list(ProjectSummary.self, "students.json") }
    func inbox(unitID: Int, myStudentsOnly: Bool) async throws -> [TaskSummary] {
        try LiveData.list(TaskSummary.self, myStudentsOnly ? "inbox_mine.json" : "inbox_all.json")
    }
    func explorer(unitID: Int, taskDefID: Int) async throws -> [TaskSummary] { try LiveData.list(TaskSummary.self, "explorer_\(taskDefID).json") }
    func project(_ id: Int) async throws -> ProjectDetail { try LiveData.decode(ProjectDetail.self, "project_\(id).json") }
    func prerequisites(unitID: Int) async throws -> [Prerequisite] { try LiveData.list(Prerequisite.self, "prereqs.json") }
    func submissionDetails(_ key: TaskKey) async throws -> SubmissionDetails { try LiveData.decode(SubmissionDetails.self, "submission_details.json") }
    func submissionPDF(_ key: TaskKey) async throws -> Data { try no() }
    func submissionFiles(_ key: TaskKey) async throws -> FileBundle? { try no() }
    func regeneratePDF(_ key: TaskKey) async throws { throw APIError.notSignedIn }
    func taskSheet(unitID: Int, taskDefID: Int) async throws -> Data { try no() }
    func taskResources(unitID: Int, taskDefID: Int) async throws -> FileBundle? { try no() }
    func comments(_ key: TaskKey) async throws -> [Marker.Comment] { try no() }
    func postComment(_ key: TaskKey, text: String, replyTo: Int?) async throws -> Marker.Comment { try no() }
    func postAttachment(_ key: TaskKey, filename: String, mimeType: String, data: Data) async throws -> Marker.Comment { try no() }
    func deleteComment(_ key: TaskKey, id: Int) async throws { throw APIError.notSignedIn }
    func commentAttachment(_ key: TaskKey, id: Int) async throws -> DownloadedFile { try no() }
    func assessExtension(_ key: TaskKey, commentID: Int, granted: Bool) async throws { throw APIError.notSignedIn }
    func setStatus(_ key: TaskKey, trigger: TaskStatus, grade: Int?, qualityPts: Int) async throws { throw APIError.notSignedIn }
    func setPinned(taskID: Int, pinned: Bool) async throws { throw APIError.notSignedIn }
    func staffNotes(projectID: Int) async throws -> [StaffNote] { try LiveData.list(StaffNote.self, "notes_\(projectID).json") }
    func addStaffNote(projectID: Int, text: String) async throws -> StaffNote { try no() }
    func deleteStaffNote(projectID: Int, id: Int) async throws { throw APIError.notSignedIn }
    func csv(unitID: Int, report: CSVReport) async throws -> DownloadedFile { try no() }
    func signOut() async {}
}

@MainActor
@Suite(.enabled(if: LiveData.dir != nil), .serialized)
struct LiveDataTests {
    @Test func picksTheCurrentUnitAndMyTutorial() async throws {
        let model = AppModel()
        await model.startForTesting(FileBackend(), credentials: nil)
        #expect(model.unitRoles.count >= 1)
        let active = model.unitRoles.filter { $0.unit.active ?? false }
        let newest = try #require(active.max { ($0.unit.startDate ?? "") < ($1.unit.startDate ?? "") })
        #expect(model.unitID == newest.unit.id, "defaults to the newest active unit")
        #expect(model.myUserID != nil)
        let myTutorial = try #require(model.myTutorialIDs.min())
        #expect(model.tutorial(myTutorial)?.abbreviation.isEmpty == false)
        #expect(model.unit?.taskDefinitions.count ?? 0 > 0)
        #expect(model.students.count > 100)
        let labels = Set(model.unitRoles.map { model.unitLabel($0.unit) })
        #expect(labels.count == model.unitRoles.count, "every unit role has a distinct label: \(labels.sorted())")
    }

    @Test func inboxRowsResolveNamesAndTasks() async throws {
        let model = AppModel()
        await model.startForTesting(FileBackend(), credentials: nil)
        let mine = try LiveData.list(TaskSummary.self, "inbox_mine.json")
        #expect(model.inbox.count == mine.count)
        for t in model.inbox {
            #expect(model.projects[t.projectId] != nil, "inbox project \(t.projectId) maps to a student")
            #expect(model.taskDef(t.taskDefinitionId) != nil, "inbox task def \(t.taskDefinitionId) is in the unit")
        }

        model.scope = .all
        await model.refreshInbox()
        let all = try LiveData.list(TaskSummary.self, "inbox_all.json")
        #expect(model.inbox.count == all.count)
        let unmapped = model.inbox.filter { model.projects[$0.projectId] == nil }.count
        let unknownTD = model.inbox.filter { model.taskDef($0.taskDefinitionId) == nil }.count
        print("LIVE all-students inbox: \(all.count) rows, \(unmapped) without a student match, \(unknownTD) with an unknown task")
        #expect(Double(unmapped) <= Double(all.count) * 0.05)
        #expect(unknownTD == 0)

        // default filters, then narrow to my tutorial
        let visible = model.inboxRows
        #expect(visible.allSatisfy { $0.status != .complete })
        #expect(visible.allSatisfy { !(model.taskDef($0.taskDefinitionId)?.isMoodle ?? false) })
        let myTutorial = try #require(model.myTutorialIDs.min())
        model.scope = .tutorial(myTutorial)
        #expect(model.inboxRows.allSatisfy { $0.tutorialId == myTutorial })
        model.search = "4.5"
        #expect(model.inboxRows.allSatisfy { model.taskLine($0.taskDefinitionId).contains("4.5") })
        print("LIVE default-filter rows: all=\(visible.count) · my tutorial with 4.5=\(model.inboxRows.count)")

        // waiting tiers and bumps compute on real dates
        let tiers = Dictionary(grouping: all, by: { WaitTier.of(status: $0.status, submitted: $0.submitted) }).mapValues(\.count)
        print("LIVE wait tiers across the unit: \(tiers.sorted { $0.key < $1.key }.map { "\($0.key.rawValue)d=\($0.value)" })")
        _ = Notifier.bumpRequests(inbox: all, lookup: model.lookup, prefs: Prefs())
        #expect(Notifier.diff(old: Notifier.snapshot(all), new: all, lookup: model.lookup).isEmpty)
        #expect(all.allSatisfy { !model.lookup.title($0).hasPrefix("A student") || model.projects[$0.projectId] == nil })
    }

    @Test func explorerProjectsNotesAndPrereqsDecode() throws {
        for f in LiveData.files(prefix: "explorer_") {
            let rows = try LiveData.list(TaskSummary.self, f)
            #expect(rows.allSatisfy { $0.tutorialId != nil }, "\(f): explorer rows carry a tutorial")
        }
        for f in LiveData.files(prefix: "project_") {
            let p = try LiveData.decode(ProjectDetail.self, f)
            #expect(!p.tasks.isEmpty)
            let rows = p.tasks.map { TaskSummary(projectID: p.id, task: $0) }
            #expect(rows.allSatisfy { $0.projectId == p.id })
        }
        for f in LiveData.files(prefix: "notes_") { _ = try LiveData.list(StaffNote.self, f) }
        let prereqs = try LiveData.list(Prerequisite.self, "prereqs.json")
        #expect(!prereqs.isEmpty)
    }

    @Test func processingPDFIsNotShownAsMissing() async throws {
        let details = try LiveData.decode(SubmissionDetails.self, "submission_details.json")
        let model = AppModel()
        await model.startForTesting(FileBackend(), credentials: nil)
        let unitID = try #require(model.unitID)
        let d = TaskDetailModel(key: TaskKey(projectID: 1, taskDefID: 1), unitID: unitID, model: model)
        await d.loadSubmission()
        switch d.submission {
        case .done(.processing): #expect(details.processingPdf == true)
        case .done(.noPDF): #expect(details.hasPdf == false && details.processingPdf != true)
        case .failed: #expect(details.hasPdf == true, "a real PDF would need the network")
        default: Issue.record("unexpected state for \(details)")
        }
    }

    @Test(.enabled(if: LiveData.captures != nil))
    func capturedCommentThreadsDecode() throws {
        var count = 0, kinds = Set<String>()
        for name in ["probe1.json", "probe2.json", "probe3.json"] {
            let url = LiveData.captures!.appendingPathComponent(name)
            guard let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { continue }
            for (path, value) in obj where path.hasSuffix("/comments") {
                guard let v = value as? [String: Any], let body = v["body"] as? String else { continue }
                let list = try JSON.decoder().decode([Marker.Comment].self, from: Data(body.utf8))
                count += list.count
                list.forEach { kinds.insert($0.kind) }
                #expect(list.allSatisfy { $0.created != nil }, "every comment has a parseable time")
                #expect(list.filter { $0.kind == "status" }.allSatisfy { $0.status != nil })
            }
        }
        print("LIVE captured comments decoded: \(count), kinds \(kinds.sorted())")
        #expect(count > 0)
    }
}
