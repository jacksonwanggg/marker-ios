import Foundation

protocol MarkerBackend: Sendable {
    func unitRoles() async throws -> [UnitRole]
    func unit(_ id: Int) async throws -> UnitDetail
    func students(unitID: Int) async throws -> [ProjectSummary]
    func inbox(unitID: Int, myStudentsOnly: Bool) async throws -> [TaskSummary]
    func explorer(unitID: Int, taskDefID: Int) async throws -> [TaskSummary]
    func project(_ id: Int) async throws -> ProjectDetail
    func prerequisites(unitID: Int) async throws -> [Prerequisite]

    // Formatif counts these three reads as marking activity
    func submissionDetails(_ key: TaskKey) async throws -> SubmissionDetails
    func submissionPDF(_ key: TaskKey) async throws -> Data
    func submissionFiles(_ key: TaskKey) async throws -> FileBundle?

    func regeneratePDF(_ key: TaskKey) async throws
    func taskSheet(unitID: Int, taskDefID: Int) async throws -> Data
    func taskResources(unitID: Int, taskDefID: Int) async throws -> FileBundle?

    // also marks the thread as read
    func comments(_ key: TaskKey) async throws -> [Comment]
    func postComment(_ key: TaskKey, text: String, replyTo: Int?) async throws -> Comment
    func postAttachment(_ key: TaskKey, filename: String, mimeType: String, data: Data) async throws -> Comment
    func deleteComment(_ key: TaskKey, id: Int) async throws
    func commentAttachment(_ key: TaskKey, id: Int) async throws -> DownloadedFile
    func assessExtension(_ key: TaskKey, commentID: Int, granted: Bool) async throws

    func setStatus(_ key: TaskKey, trigger: TaskStatus, grade: Int?, qualityPts: Int) async throws
    func setPinned(taskID: Int, pinned: Bool) async throws

    func staffNotes(projectID: Int) async throws -> [StaffNote]
    func addStaffNote(projectID: Int, text: String) async throws -> StaffNote
    func deleteStaffNote(projectID: Int, id: Int) async throws

    func csv(unitID: Int, report: CSVReport) async throws -> DownloadedFile
    func signOut() async
}

struct SignedOutBackend: MarkerBackend {
    func unitRoles() async throws -> [UnitRole] { throw APIError.notSignedIn }
    func unit(_ id: Int) async throws -> UnitDetail { throw APIError.notSignedIn }
    func students(unitID: Int) async throws -> [ProjectSummary] { throw APIError.notSignedIn }
    func inbox(unitID: Int, myStudentsOnly: Bool) async throws -> [TaskSummary] { throw APIError.notSignedIn }
    func explorer(unitID: Int, taskDefID: Int) async throws -> [TaskSummary] { throw APIError.notSignedIn }
    func project(_ id: Int) async throws -> ProjectDetail { throw APIError.notSignedIn }
    func prerequisites(unitID: Int) async throws -> [Prerequisite] { throw APIError.notSignedIn }
    func submissionDetails(_ key: TaskKey) async throws -> SubmissionDetails { throw APIError.notSignedIn }
    func submissionPDF(_ key: TaskKey) async throws -> Data { throw APIError.notSignedIn }
    func submissionFiles(_ key: TaskKey) async throws -> FileBundle? { throw APIError.notSignedIn }
    func regeneratePDF(_ key: TaskKey) async throws { throw APIError.notSignedIn }
    func taskSheet(unitID: Int, taskDefID: Int) async throws -> Data { throw APIError.notSignedIn }
    func taskResources(unitID: Int, taskDefID: Int) async throws -> FileBundle? { throw APIError.notSignedIn }
    func comments(_ key: TaskKey) async throws -> [Comment] { throw APIError.notSignedIn }
    func postComment(_ key: TaskKey, text: String, replyTo: Int?) async throws -> Comment { throw APIError.notSignedIn }
    func postAttachment(_ key: TaskKey, filename: String, mimeType: String, data: Data) async throws -> Comment { throw APIError.notSignedIn }
    func deleteComment(_ key: TaskKey, id: Int) async throws { throw APIError.notSignedIn }
    func commentAttachment(_ key: TaskKey, id: Int) async throws -> DownloadedFile { throw APIError.notSignedIn }
    func assessExtension(_ key: TaskKey, commentID: Int, granted: Bool) async throws { throw APIError.notSignedIn }
    func setStatus(_ key: TaskKey, trigger: TaskStatus, grade: Int?, qualityPts: Int) async throws { throw APIError.notSignedIn }
    func setPinned(taskID: Int, pinned: Bool) async throws { throw APIError.notSignedIn }
    func staffNotes(projectID: Int) async throws -> [StaffNote] { throw APIError.notSignedIn }
    func addStaffNote(projectID: Int, text: String) async throws -> StaffNote { throw APIError.notSignedIn }
    func deleteStaffNote(projectID: Int, id: Int) async throws { throw APIError.notSignedIn }
    func csv(unitID: Int, report: CSVReport) async throws -> DownloadedFile { throw APIError.notSignedIn }
    func signOut() async {}
}

struct LiveBackend: MarkerBackend {
    let client: FormatifClient

    private func base(_ k: TaskKey) -> String { "projects/\(k.projectID)/task_def_id/\(k.taskDefID)" }
    private let inline = [URLQueryItem(name: "as_attachment", value: "false")]

    func unitRoles() async throws -> [UnitRole] { try await client.list(UnitRole.self, "unit_roles/") }
    func unit(_ id: Int) async throws -> UnitDetail { try await client.get(UnitDetail.self, "units/\(id)") }

    func students(unitID: Int) async throws -> [ProjectSummary] {
        try await client.list(ProjectSummary.self, "students", query: [
            URLQueryItem(name: "withdrawn", value: "false"), URLQueryItem(name: "unit_id", value: String(unitID)),
        ])
    }

    func inbox(unitID: Int, myStudentsOnly: Bool) async throws -> [TaskSummary] {
        try await client.list(TaskSummary.self, "units/\(unitID)/tasks/inbox",
                             query: [URLQueryItem(name: "my_students_only", value: myStudentsOnly ? "true" : "false")])
    }

    func explorer(unitID: Int, taskDefID: Int) async throws -> [TaskSummary] {
        try await client.list(TaskSummary.self, "units/\(unitID)/task_definitions/\(taskDefID)/tasks")
    }

    func project(_ id: Int) async throws -> ProjectDetail { try await client.get(ProjectDetail.self, "projects/\(id)") }

    func prerequisites(unitID: Int) async throws -> [Prerequisite] {
        try await client.list(Prerequisite.self, "units/\(unitID)/task_prerequisites")
    }

    func submissionDetails(_ key: TaskKey) async throws -> SubmissionDetails {
        try await client.get(SubmissionDetails.self, "\(base(key))/submission_details")
    }

    func submissionPDF(_ key: TaskKey) async throws -> Data {
        try await client.download("\(base(key))/submission", query: inline).data
    }

    func submissionFiles(_ key: TaskKey) async throws -> FileBundle? {
        let file = try await client.download("\(base(key))/submission_files", query: inline)
        // with no upload Formatif sends a FileNotFound.pdf placeholder
        guard Zip.isZip(file.data) else { return nil }
        return FileBundle(name: file.filename, entries: try Zip.entries(file.data))
    }

    func regeneratePDF(_ key: TaskKey) async throws {
        _ = try await client.send("PUT", "\(base(key))/submission", body: .json(Data("{}".utf8)))
    }

    func taskSheet(unitID: Int, taskDefID: Int) async throws -> Data {
        try await client.download("units/\(unitID)/task_definitions/\(taskDefID)/task_pdf.json").data
    }

    func taskResources(unitID: Int, taskDefID: Int) async throws -> FileBundle? {
        let file = try await client.download("units/\(unitID)/task_definitions/\(taskDefID)/task_resources.json")
        guard Zip.isZip(file.data) else { return nil }
        return FileBundle(name: file.filename, entries: try Zip.entries(file.data))
    }

    func comments(_ key: TaskKey) async throws -> [Comment] {
        try await client.list(Comment.self, "\(base(key))/comments")
    }

    func postComment(_ key: TaskKey, text: String, replyTo: Int?) async throws -> Comment {
        var form = Multipart()
        form.add("comment", text)
        if let replyTo { form.add("reply_to_id", String(replyTo)) }
        let (data, _) = try await client.send("POST", "\(base(key))/comments/", body: .multipart(form))
        return try JSON.decoder().decode(Comment.self, from: data)
    }

    func postAttachment(_ key: TaskKey, filename: String, mimeType: String, data: Data) async throws -> Comment {
        var form = Multipart()
        form.addFile("attachment", filename: filename, mimeType: mimeType, data: data)
        let (body, _) = try await client.send("POST", "\(base(key))/comments/", body: .multipart(form))
        return try JSON.decoder().decode(Comment.self, from: body)
    }

    func deleteComment(_ key: TaskKey, id: Int) async throws {
        _ = try await client.send("DELETE", "\(base(key))/comments/\(id)")
    }

    func commentAttachment(_ key: TaskKey, id: Int) async throws -> DownloadedFile {
        try await client.download("\(base(key))/comments/\(id)", query: inline)
    }

    func assessExtension(_ key: TaskKey, commentID: Int, granted: Bool) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["granted": granted])
        _ = try await client.send("PUT", "\(base(key))/assess_extension/\(commentID)", body: .json(body))
    }

    func setStatus(_ key: TaskKey, trigger: TaskStatus, grade: Int?, qualityPts: Int) async throws {
        let payload: [String: Any] = [
            "trigger": trigger.rawValue,
            "grade": grade.map { $0 as Any } ?? NSNull(),
            "quality_pts": qualityPts,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await client.send("PUT", base(key), body: .json(body))
    }

    func setPinned(taskID: Int, pinned: Bool) async throws {
        _ = try await client.send(pinned ? "POST" : "DELETE", "tasks/\(taskID)/pin")
    }

    func staffNotes(projectID: Int) async throws -> [StaffNote] {
        try await client.list(StaffNote.self, "projects/\(projectID)/staff_notes")
    }

    func addStaffNote(projectID: Int, text: String) async throws -> StaffNote {
        var form = Multipart()
        form.add("note", text)
        let (data, _) = try await client.send("POST", "projects/\(projectID)/staff_notes", body: .multipart(form))
        return try JSON.decoder().decode(StaffNote.self, from: data)
    }

    func deleteStaffNote(projectID: Int, id: Int) async throws {
        _ = try await client.send("DELETE", "projects/\(projectID)/staff_notes/\(id)")
    }

    func csv(unitID: Int, report: CSVReport) async throws -> DownloadedFile {
        try await client.download(report.path(unitID: unitID))
    }

    func signOut() async { await client.signOut() }
}
