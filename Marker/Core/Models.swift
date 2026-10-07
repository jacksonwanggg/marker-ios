import Foundation

struct TaskKey: Hashable, Codable, Sendable {
    let projectID: Int
    let taskDefID: Int
}

struct UserRef: Codable, Hashable, Sendable {
    let id: Int
    var firstName: String?
    var lastName: String?
    var email: String?
    var username: String?
    var nickname: String?

    var fullName: String {
        let parts = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? (username ?? "Unknown") : parts.joined(separator: " ")
    }
    var first: String { firstName ?? username ?? "Someone" }
}

struct UnitSummary: Codable, Hashable, Sendable {
    let id: Int
    var code: String
    var name: String?
    var myRole: String?
    var startDate: String?
    var endDate: String?
    var active: Bool?
}

struct UnitRole: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    var role: String?
    var unit: UnitSummary
    var user: UserRef?

    var isStaff: Bool { (role ?? unit.myRole ?? "").lowercased() != "student" }
}

struct TaskDefinition: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    var abbreviation: String
    var name: String
    var description: String?
    var targetGrade: Int?
    var dueDate: String?
    var targetDate: String?
    var startDate: String?
    var hasTaskSheet: Bool?
    var hasTaskResources: Bool?
    var isGraded: Bool?
    var maxQualityPts: Int?
    var discussionPromptsCount: Int?
    var uploadRequirements: [UploadRequirement]?

    /// False for (E), (D) and (M) tasks, which have nothing to upload. nil if unknown.
    var hasUploads: Bool? { uploadRequirements.map { !$0.isEmpty } }

    var isMoodle: Bool { name.hasPrefix("(M)") || abbreviation.hasPrefix("(M)") }
    var line: String { "\(abbreviation) · \(name)" }
    var gradeLetter: String { Grade.letter(targetGrade) }
}

struct UploadRequirement: Codable, Hashable, Sendable {
    var key: String?
    var name: String?
    var type: String?
}

struct Tutorial: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    var abbreviation: String
    var meetingDay: String?
    var meetingTime: String?
    var meetingLocation: String?
    var tutorId: Int?
    var numStudents: Int?
}

struct StaffMember: Codable, Hashable, Sendable {
    let id: Int
    var role: String?
    var user: UserRef
}

struct UnitDetail: Codable, Sendable {
    let id: Int
    var code: String
    var name: String?
    var myRole: String?
    var startDate: String?
    var taskDefinitions: [TaskDefinition]
    var tutorials: [Tutorial]
    var staff: [StaffMember]?

    enum CodingKeys: String, CodingKey {
        case id, code, name, myRole, startDate, taskDefinitions, tutorials, staff
    }
}

extension UnitDetail {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        code = c.opt(String.self, .code) ?? "Unit \(id)"
        name = c.opt(String.self, .name)
        myRole = c.opt(String.self, .myRole)
        startDate = c.opt(String.self, .startDate)
        taskDefinitions = c.opt(LossyList<TaskDefinition>.self, .taskDefinitions)?.items ?? []
        tutorials = c.opt(LossyList<Tutorial>.self, .tutorials)?.items ?? []
        staff = c.opt(LossyList<StaffMember>.self, .staff)?.items
    }
}

struct Student: Codable, Hashable, Sendable {
    let id: Int
    var studentId: String?
    var username: String?
    var email: String?
    var firstName: String?
    var lastName: String?
    var nickname: String?

    var name: String {
        let parts = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? (username ?? "Student") : parts.joined(separator: " ")
    }
    var zid: String { studentId ?? username ?? "" }
}

struct TutorialEnrolment: Codable, Hashable, Sendable {
    /// Can be null for students who aren't in a class yet.
    var tutorialId: Int?
    var streamAbbr: String?
}

/// A student's enrolment. Formatif calls it a project.
struct ProjectSummary: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    var student: Student
    var targetGrade: Int?
    var tutorialEnrolments: [TutorialEnrolment]?
    var staffNoteCount: Int?

    var tutorialIDs: [Int] { (tutorialEnrolments ?? []).compactMap(\.tutorialId) }
}

struct TaskSummary: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let projectId: Int
    let taskDefinitionId: Int
    var tutorialId: Int?
    var statusKey: String
    var completionDate: String?
    var submissionDate: String?
    var timesAssessed: Int?
    var grade: Int?
    var qualityPts: Int?
    var numNewComments: Int
    var similarityFlag: Bool
    var pinned: Bool
    var hasExtensions: Bool

    enum CodingKeys: String, CodingKey {
        case id, projectId, taskDefinitionId, tutorialId
        case statusKey = "status"
        case completionDate, submissionDate, timesAssessed, grade, qualityPts
        case numNewComments, similarityFlag, pinned, hasExtensions
    }

    var key: TaskKey { TaskKey(projectID: projectId, taskDefID: taskDefinitionId) }
    var status: TaskStatus { TaskStatus(key: statusKey) }
    var submitted: Date? { Fmt.parse(submissionDate) }
}

extension TaskSummary {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        projectId = try c.decode(Int.self, forKey: .projectId)
        taskDefinitionId = try c.decode(Int.self, forKey: .taskDefinitionId)
        tutorialId = c.opt(Int.self, .tutorialId)
        statusKey = c.opt(String.self, .statusKey) ?? "not_started"
        completionDate = c.opt(String.self, .completionDate)
        submissionDate = c.opt(String.self, .submissionDate)
        timesAssessed = c.opt(Int.self, .timesAssessed)
        grade = c.opt(Int.self, .grade)
        qualityPts = c.opt(Int.self, .qualityPts)
        numNewComments = c.opt(Int.self, .numNewComments) ?? 0
        similarityFlag = c.flexBool(.similarityFlag)
        pinned = c.flexBool(.pinned)
        hasExtensions = c.flexBool(.hasExtensions)
    }

    init(projectID: Int, task t: ProjectTask) {
        self.init(id: t.id, projectId: projectID, taskDefinitionId: t.taskDefinitionId, tutorialId: nil,
                  statusKey: t.status ?? "not_started", completionDate: t.completionDate,
                  submissionDate: t.submissionDate, timesAssessed: t.timesAssessed, grade: nil,
                  qualityPts: t.qualityPts, numNewComments: t.numNewComments ?? 0,
                  similarityFlag: t.similarityFlag ?? false, pinned: false, hasExtensions: (t.extensions ?? 0) > 0)
    }
}

struct ProjectTask: Codable, Hashable, Sendable {
    let id: Int
    let taskDefinitionId: Int
    var status: String?
    var dueDate: String?
    var submissionDate: String?
    var completionDate: String?
    var extensions: Int?
    var timesAssessed: Int?
    var qualityPts: Int?
    var similarityFlag: Bool?
    var numNewComments: Int?
}

struct ProjectDetail: Codable, Sendable {
    let id: Int
    var unitId: Int?
    var targetGrade: Int?
    var tasks: [ProjectTask]
    var tutorialEnrolments: [TutorialEnrolment]?

    enum CodingKeys: String, CodingKey { case id, unitId, targetGrade, tasks, tutorialEnrolments }
}

extension ProjectDetail {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        unitId = c.opt(Int.self, .unitId)
        targetGrade = c.opt(Int.self, .targetGrade)
        tasks = c.opt(LossyList<ProjectTask>.self, .tasks)?.items ?? []
        tutorialEnrolments = c.opt(LossyList<TutorialEnrolment>.self, .tutorialEnrolments)?.items
    }
}

struct SubmissionDetails: Codable, Sendable, Hashable {
    var hasPdf: Bool?
    var submissionDate: String?
    var processingPdf: Bool?
    var taskStatus: String?
}

struct Comment: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    var comment: String?
    var hasAttachment: Bool?
    var type: String?
    var isNew: Bool?
    var replyToId: Int?
    var author: UserRef?
    var recipient: UserRef?
    var createdAt: String?
    var recipientReadTime: String?
    var status: String?
    var assessed: Bool?
    var granted: Bool?
    var dateAssessed: String?
    var weeksRequested: Int?
    var extensionResponse: String?
    var taskStatus: String?
    var dueDate: String?

    enum CodingKeys: String, CodingKey {
        case id, comment, hasAttachment, type, isNew, replyToId, author, recipient, createdAt
        case recipientReadTime, status, assessed, granted, dateAssessed, weeksRequested
        case extensionResponse, taskStatus, dueDate
    }

    var kind: String { type ?? "text" }
    var created: Date? { Fmt.parse(createdAt) }
    var isAttachment: Bool { (hasAttachment ?? false) || ["image", "pdf", "audio"].contains(kind) }
}

extension Comment {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        comment = c.opt(String.self, .comment)
        hasAttachment = c.opt(Bool.self, .hasAttachment)
        type = c.opt(String.self, .type)
        isNew = c.opt(Bool.self, .isNew)
        replyToId = c.opt(Int.self, .replyToId)
        author = c.opt(UserRef.self, .author)
        recipient = c.opt(UserRef.self, .recipient)
        createdAt = c.opt(String.self, .createdAt)
        recipientReadTime = c.opt(String.self, .recipientReadTime)
        status = c.opt(String.self, .status)
        assessed = c.opt(Bool.self, .assessed)
        granted = c.opt(Bool.self, .granted)
        dateAssessed = c.opt(String.self, .dateAssessed)
        weeksRequested = c.opt(Int.self, .weeksRequested)
        extensionResponse = c.opt(String.self, .extensionResponse)
        taskStatus = c.opt(String.self, .taskStatus)
        dueDate = c.opt(String.self, .dueDate)
    }
}

struct StaffNote: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    var note: String?
    var createdAt: String?
    var updatedAt: String?
    var replyToId: Int?
    var userId: Int?
}

struct Prerequisite: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    var taskDefinitionId: Int
    var prerequisiteId: Int
    var taskStatus: String?
}

struct AuthResponse: Codable, Sendable {
    var user: UserRef?
    var authToken: String
}

struct AuthMethod: Codable, Sendable {
    var method: String?
    var redirectTo: String?
}

struct DownloadedFile: Sendable {
    let data: Data
    let filename: String
    let mimeType: String?
}

enum CSVReport: String, CaseIterable, Identifiable, Sendable {
    case taskCompletion = "task_completion"
    case awaitingFeedback = "tasks_awaiting_feedback"
    case assessmentCounts = "task_assessment_counts"
    case tutorAssessments = "tutor_assessments"
    case tutorTimes = "tutor_times_summary"
    case myMarkingSessions = "my_marking_sessions"
    case staffNotes = "staff_notes"
    case students = "students"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .taskCompletion: "Task completion"
        case .awaitingFeedback: "Awaiting feedback"
        case .assessmentCounts: "Assessment counts"
        case .tutorAssessments: "Tutor assessments"
        case .tutorTimes: "Tutor times"
        case .myMarkingSessions: "My marking sessions"
        case .staffNotes: "Staff notes"
        case .students: "Students"
        }
    }

    func path(unitID: Int) -> String {
        self == .students ? "csv/units/\(unitID)" : "csv/units/\(unitID)/\(rawValue)"
    }
}

enum Grade {
    static func letter(_ g: Int?) -> String {
        switch g { case 0: "P"; case 1: "C"; case 2: "D"; case 3: "HD"; default: "None" }
    }
}

/// Decodes an array but skips items that fail, so one bad record can't blank a screen.
struct LossyList<T: Decodable & Sendable>: Decodable, Sendable {
    var items: [T]
    var skipped = 0

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var out: [T] = []
        var bad = 0
        while !c.isAtEnd {
            if let v = try? c.decode(T.self) {
                out.append(v)
            } else {
                _ = try? c.decode(Skip.self)
                bad += 1
            }
        }
        items = out
        skipped = bad
    }

    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

extension KeyedDecodingContainer {
    /// A missing key, null or wrong type all give nil.
    func opt<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// Formatif sends some flags as 0/1 and others as true/false.
    func flexBool(_ key: Key) -> Bool {
        if let b = opt(Bool.self, key) { return b }
        if let i = opt(Int.self, key) { return i != 0 }
        return false
    }
}

enum JSON {
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }
}
