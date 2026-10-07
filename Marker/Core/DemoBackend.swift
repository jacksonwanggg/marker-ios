import Foundation
import UIKit

/// Demo mode. Every student and submission is made up, and changes only live in memory.
actor DemoBackend: MarkerBackend {
    nonisolated var isDemo: Bool { true }

    static let me = UserRef(id: 1, firstName: "Alex", lastName: "Tutor", email: nil, username: "z5123456", nickname: nil)

    private struct DemoStudent { let sid: Int; let first: String; let last: String; let zid: String; let tut: Int; let target: Int }
    private static let tutorials: [Tutorial] = [
        Tutorial(id: 11, abbreviation: "T13A", meetingDay: "Tuesday", meetingTime: "13:00", meetingLocation: "Quad G040", tutorId: 1, numStudents: 6),
        Tutorial(id: 12, abbreviation: "H14B", meetingDay: "Thursday", meetingTime: "14:00", meetingLocation: "Ainsworth 101", tutorId: 1, numStudents: 4),
        Tutorial(id: 13, abbreviation: "W11A", meetingDay: "Wednesday", meetingTime: "11:00", meetingLocation: "Law 203", tutorId: 2, numStudents: 1),
        Tutorial(id: 14, abbreviation: "F09B", meetingDay: "Friday", meetingTime: "09:00", meetingLocation: "Online", tutorId: 3, numStudents: 1),
    ]
    private static let roster: [DemoStudent] = [
        .init(sid: 1, first: "Priya", last: "Raman", zid: "z5401234", tut: 11, target: 3),
        .init(sid: 2, first: "Tom", last: "Okafor", zid: "z5388811", tut: 11, target: 2),
        .init(sid: 3, first: "Mei-Ling", last: "Zhao", zid: "z5412907", tut: 12, target: 3),
        .init(sid: 4, first: "Daniel", last: "Kowalski", zid: "z5377650", tut: 11, target: 1),
        .init(sid: 5, first: "Aisha", last: "Rahman", zid: "z5429118", tut: 12, target: 2),
        .init(sid: 6, first: "Lucas", last: "Ferreira", zid: "z5390022", tut: 11, target: 0),
        .init(sid: 7, first: "Hannah", last: "Byrne", zid: "z5418833", tut: 12, target: 1),
        .init(sid: 8, first: "Jin-woo", last: "Park", zid: "z5402266", tut: 11, target: 2),
        .init(sid: 9, first: "Sofia", last: "Marchetti", zid: "z5431105", tut: 12, target: 3),
        .init(sid: 10, first: "Ethan", last: "Walsh", zid: "z5386640", tut: 11, target: 0),
        .init(sid: 11, first: "Nadia", last: "Hussain", zid: "z5424471", tut: 13, target: 2),
        .init(sid: 12, first: "Oliver", last: "Tan", zid: "z5399087", tut: 14, target: 1),
    ]
    private static let taskDefs: [TaskDefinition] = {
        let start = Date.now.addingTimeInterval(-28 * 86_400)
        func td(_ id: Int, _ abbr: String, _ name: String, _ grade: Int, dueIn days: Double, _ desc: String) -> TaskDefinition {
            TaskDefinition(id: id, abbreviation: abbr, name: name, description: desc,
                           targetGrade: grade, dueDate: day(Date.now.addingTimeInterval(days * 86_400)),
                           targetDate: nil, startDate: day(start), hasTaskSheet: true, hasTaskResources: id == 5,
                           isGraded: false, maxQualityPts: 0, discussionPromptsCount: 0)
        }
        return [
            td(1, "1.1", "(W) Asymptotic notation", 0, dueIn: -22,
               "Rank the eight functions on the task sheet by growth rate and prove each step with limits or the definitions."),
            td(2, "2.1", "(W) Divide and conquer", 0, dueIn: -15,
               "Count inversions in an array in O(n log n). Explain the merge step and write down the recurrence."),
            td(3, "2.2", "(W) Master theorem", 1, dueIn: -15,
               "Solve the four recurrences with the master theorem. Say which case applies and check its conditions."),
            td(4, "3.1", "(W) Greedy exchange argument", 1, dueIn: -8,
               "Give a greedy algorithm for the room booking problem and prove it's optimal with an exchange argument."),
            td(5, "3.2", "(W) Dynamic programming", 2, dueIn: -1,
               "Give the subproblem definition, the recurrence with base cases, a correctness argument and the running time. Keep it to two pages."),
            td(6, "4.1", "(W) Shortest paths", 2, dueIn: 6,
               "Find the cheapest route when some roads have tolls. Model it as a graph and say which shortest path algorithm you'd run."),
            td(7, "4.2", "(W) Maximum flow", 3, dueIn: 13,
               "Reduce the tutor allocation problem to max flow. Draw the network and argue why a max flow gives a valid allocation."),
            td(8, "Q3", "(M) Week 3 Moodle quiz", 0, dueIn: -11,
               "Done on Moodle. Nothing to upload here."),
        ]
    }()

    private var tasks: [TaskSummary]
    private var threads: [TaskKey: [Comment]]
    private var notes: [Int: [StaffNote]]
    private var attachments: [Int: DownloadedFile] = [:]
    private var nextID = 900_000

    init() {
        let now = Date.now
        func ago(_ hours: Double) -> String { Self.iso(now.addingTimeInterval(-hours * 3600)) }
        func t(_ sid: Int, _ td: Int, _ status: TaskStatus, _ hours: Double, newc: Int = 0, pinned: Bool = false,
               ext: Bool = false, sim: Bool = false, attempt: Int = 1) -> TaskSummary {
            let stu = Self.roster[sid - 1]
            return TaskSummary(id: Self.taskID(sid, td), projectId: Self.projectID(sid), taskDefinitionId: td,
                               tutorialId: stu.tut, statusKey: status.rawValue, completionDate: nil,
                               submissionDate: ago(hours), timesAssessed: attempt - 1, grade: nil, qualityPts: -1,
                               numNewComments: newc, similarityFlag: sim, pinned: pinned, hasExtensions: ext)
        }
        tasks = [
            t(1, 5, .readyForFeedback, 2, pinned: true),
            t(9, 6, .readyForFeedback, 1),
            t(2, 4, .readyForFeedback, 3, newc: 1),
            t(3, 5, .readyForFeedback, 5, sim: true),
            t(8, 4, .readyForFeedback, 6),
            t(4, 5, .workingOnIt, 8, newc: 1),
            t(4, 3, .readyForFeedback, 26, attempt: 2),
            t(5, 4, .needHelp, 27, newc: 2),
            t(2, 8, .readyForFeedback, 30),
            t(6, 2, .readyForFeedback, 51, ext: true),
            t(7, 5, .discuss, 54, newc: 1),
            t(10, 3, .readyForFeedback, 77, newc: 1, attempt: 2),
            t(8, 2, .readyForFeedback, 103),
            t(3, 3, .readyForFeedback, 205),
            t(1, 3, .complete, 98, newc: 1),
            t(5, 2, .complete, 120, newc: 2),
            t(11, 5, .readyForFeedback, 4),
            t(12, 4, .readyForFeedback, 24),
        ]
        threads = Self.seedThreads(now: now)
        notes = [Self.projectID(1): [StaffNote(id: 1, note: "Asked about a reference letter in week 5. Follow up once term's over.",
                                               createdAt: ago(48), updatedAt: nil, replyToId: nil, userId: 1)]]
    }

    // MARK: ids and helpers

    private static func taskID(_ sid: Int, _ td: Int) -> Int { 10_000 + sid * 100 + td }
    private static func projectID(_ sid: Int) -> Int { 500 + sid }
    private static func sid(ofProject p: Int) -> Int { p - 500 }
    private static func iso(_ d: Date) -> String { d.formatted(Date.ISO8601FormatStyle()) }
    private static func day(_ d: Date) -> String { d.formatted(Date.ISO8601FormatStyle().year().month().day()) }
    private static func user(_ sid: Int) -> UserRef {
        let s = roster[sid - 1]
        return UserRef(id: 100 + sid, firstName: s.first, lastName: s.last, email: nil, username: s.zid, nickname: nil)
    }

    private static func seedThreads(now: Date) -> [TaskKey: [Comment]] {
        func at(_ hours: Double) -> String { iso(now.addingTimeInterval(-hours * 3600)) }
        func key(_ sid: Int, _ td: Int) -> TaskKey { TaskKey(projectID: projectID(sid), taskDefID: td) }
        var id = 1
        func c(_ sid: Int, _ type: String, _ text: String?, _ hours: Double, mine: Bool = false, status: TaskStatus? = nil,
               read: Double? = nil, replyTo: Int? = nil, attach: Bool = false, weeks: Int? = nil) -> Comment {
            id += 1
            let student = user(sid)
            return Comment(id: id, comment: text, hasAttachment: attach, type: type, isNew: false, replyToId: replyTo,
                           author: mine ? me : student, recipient: mine ? student : me, createdAt: at(hours),
                           recipientReadTime: read.map { at($0) }, status: status?.rawValue,
                           assessed: weeks == nil ? nil : false, granted: nil, dateAssessed: nil, weeksRequested: weeks)
        }
        var out: [TaskKey: [Comment]] = [:]
        let reply = c(1, "text", "Having both is fine. OPT(0) = 0 is enough on its own, but the extra one doesn't hurt.", 1.6, mine: true, read: 1.5)
        out[key(1, 5)] = [
            c(1, "status", nil, 2, status: .readyForFeedback),
            c(1, "text", "Hi, does the recurrence need a base case for n = 1 as well as n = 0? I put both in just in case.", 1.95),
            reply,
            c(1, "text", "Great, thanks!", 1.4, replyTo: reply.id),
        ]
        out[key(5, 4)] = [
            c(5, "status", nil, 27, status: .needHelp),
            c(5, "text", "I'm stuck on the exchange step. I swap the first interval in OPT for the greedy one but can't show the new schedule still has no overlaps. Any hints?", 26.9),
            c(5, "text", "also can I assume the intervals are already sorted by finish time?", 26.5),
        ]
        out[key(6, 2)] = [
            c(6, "status", nil, 51, status: .readyForFeedback),
            c(6, "extension", "I was sick for most of week 3. I've put the medical certificate through Special Consideration.", 50.9, weeks: 1),
        ]
        out[key(10, 3)] = [
            c(10, "status", nil, 110, status: .readyForFeedback),
            c(10, "text", "The regularity condition is for case 3, not case 2. Have a look at section 2 of the task sheet.", 100, mine: true, read: 80),
            c(10, "status", nil, 99.9, mine: true, status: .fixAndResubmit),
            c(10, "text", "Ah I had 2 and 3 mixed up. Fixed and resubmitted.", 77.2),
            c(10, "pdf", nil, 77.1, attach: true),
            c(10, "status", nil, 77, status: .readyForFeedback),
        ]
        out[key(2, 4)] = [
            c(2, "status", nil, 3.2, status: .readyForFeedback),
            c(2, "text", "Does the exchange argument need to handle ties in finish time too?", 3),
        ]
        out[key(4, 5)] = [c(4, "text", "Is it ok to use memoisation instead of filling the table bottom up?", 8)]
        return out
    }

    private func derived(_ sid: Int, _ td: Int) -> TaskSummary {
        let h = (sid * 7 + td * 3) % 5
        let status: TaskStatus = switch td {
        case ...3: (sid + td) % 6 == 0 ? .fixAndResubmit : .complete
        case 4, 5: [.complete, .readyForFeedback, .workingOnIt, .notStarted, .discuss][h]
        case 8: sid % 2 == 1 ? .complete : .notStarted
        default: sid % 3 == 0 ? .workingOnIt : .notStarted
        }
        let submitted = status.isSubmitted ? Self.iso(Date.now.addingTimeInterval(-Double(96 + td * 5) * 3600)) : nil
        return TaskSummary(id: Self.taskID(sid, td), projectId: Self.projectID(sid), taskDefinitionId: td,
                           tutorialId: Self.roster[sid - 1].tut, statusKey: status.rawValue, completionDate: nil,
                           submissionDate: submitted, timesAssessed: 0, grade: nil, qualityPts: -1, numNewComments: 0,
                           similarityFlag: false, pinned: false, hasExtensions: false)
    }

    private func task(_ key: TaskKey) -> TaskSummary {
        tasks.first { $0.key == key } ?? derived(Self.sid(ofProject: key.projectID), key.taskDefID)
    }

    private func update(_ key: TaskKey, _ change: (inout TaskSummary) -> Void) {
        if let i = tasks.firstIndex(where: { $0.key == key }) {
            change(&tasks[i])
        } else {
            var t = task(key)
            change(&t)
            tasks.append(t)
        }
    }

    private func thread(_ key: TaskKey) -> [Comment] {
        if let t = threads[key] { return t }
        let t = task(key)
        guard t.status.isSubmitted else { return [] }
        let sid = Self.sid(ofProject: key.projectID)
        return [Comment(id: 800_000 + t.id, comment: nil, hasAttachment: false, type: "status", isNew: false, replyToId: nil,
                        author: Self.user(sid), recipient: Self.me, createdAt: t.submissionDate, recipientReadTime: nil,
                        status: TaskStatus.readyForFeedback.rawValue)]
    }

    private func newID() -> Int { nextID += 1; return nextID }
    private func pause() async { try? await Task.sleep(for: .milliseconds(250)) }

    // MARK: MarkerBackend

    func unitRoles() async throws -> [UnitRole] {
        [
            UnitRole(id: 1, role: "Tutor", unit: UnitSummary(id: 1, code: "COMP3121/9101", name: "Algorithm Design and Analysis", myRole: "Tutor", startDate: "2026-09-14", endDate: "2026-12-12", active: true), user: Self.me),
            UnitRole(id: 2, role: "Tutor", unit: UnitSummary(id: 2, code: "COMP9020", name: "Foundations of Computer Science", myRole: "Tutor", startDate: "2026-09-14", endDate: "2026-12-12", active: true), user: Self.me),
        ]
    }

    func unit(_ id: Int) async throws -> UnitDetail {
        if id == 2 {
            return UnitDetail(id: 2, code: "COMP9020", name: "Foundations of Computer Science", myRole: "Tutor", startDate: "2026-09-14",
                              taskDefinitions: [TaskDefinition(id: 21, abbreviation: "1.1", name: "(W) Sets and relations")],
                              tutorials: [], staff: [])
        }
        return UnitDetail(id: 1, code: "COMP3121/9101", name: "Algorithm Design and Analysis", myRole: "Tutor", startDate: "2026-09-14",
                          taskDefinitions: Self.taskDefs, tutorials: Self.tutorials,
                          staff: [StaffMember(id: 1, role: "Tutor", user: Self.me)])
    }

    func students(unitID: Int) async throws -> [ProjectSummary] {
        guard unitID == 1 else { return [] }
        return Self.roster.map { s in
            ProjectSummary(id: Self.projectID(s.sid),
                           student: Student(id: 100 + s.sid, studentId: s.zid, username: s.zid, email: nil, firstName: s.first, lastName: s.last, nickname: nil),
                           targetGrade: s.target, tutorialEnrolments: [TutorialEnrolment(tutorialId: s.tut, streamAbbr: "Lab")],
                           staffNoteCount: notes[Self.projectID(s.sid)]?.count ?? 0)
        }
    }

    func inbox(unitID: Int, myStudentsOnly: Bool) async throws -> [TaskSummary] {
        await pause()
        guard unitID == 1 else { return [] }
        let mine: Set<Int> = [11, 12]
        let open = tasks.filter { $0.status != .complete || $0.numNewComments > 0 }
        return myStudentsOnly ? open.filter { mine.contains($0.tutorialId ?? 0) } : open
    }

    func explorer(unitID: Int, taskDefID: Int) async throws -> [TaskSummary] {
        await pause()
        guard unitID == 1 else { return [] }
        return Self.roster.map { task(TaskKey(projectID: Self.projectID($0.sid), taskDefID: taskDefID)) }
    }

    func project(_ id: Int) async throws -> ProjectDetail {
        let student = Self.roster[max(0, Self.sid(ofProject: id) - 1)]
        let list = Self.taskDefs.map { td -> ProjectTask in
            let t = task(TaskKey(projectID: id, taskDefID: td.id))
            return ProjectTask(id: t.id, taskDefinitionId: td.id, status: t.statusKey, dueDate: td.dueDate,
                               submissionDate: t.submissionDate, completionDate: nil, extensions: t.hasExtensions ? 1 : 0,
                               timesAssessed: t.timesAssessed, qualityPts: -1, similarityFlag: t.similarityFlag,
                               numNewComments: t.numNewComments)
        }
        return ProjectDetail(id: id, unitId: 1, targetGrade: student.target, tasks: list,
                             tutorialEnrolments: [TutorialEnrolment(tutorialId: student.tut, streamAbbr: "Lab")])
    }

    func prerequisites(unitID: Int) async throws -> [Prerequisite] {
        [Prerequisite(id: 1, taskDefinitionId: 5, prerequisiteId: 4, taskStatus: "complete")]
    }

    func submissionDetails(_ key: TaskKey) async throws -> SubmissionDetails {
        let t = task(key)
        return SubmissionDetails(hasPdf: t.status.isSubmitted, submissionDate: t.submissionDate, processingPdf: false, taskStatus: t.statusKey)
    }

    func submissionPDF(_ key: TaskKey) async throws -> Data {
        await pause()
        let s = Self.roster[Self.sid(ofProject: key.projectID) - 1]
        let td = Self.taskDefs.first { $0.id == key.taskDefID }
        let header = "COMP3121/9101 · Task \(td?.abbreviation ?? "") · \(s.zid)"
        let title = td?.name ?? "Submission"
        return await MainActor.run { DemoContent.submissionPDF(header: header, title: title) }
    }

    func submissionFiles(_ key: TaskKey) async throws -> FileBundle? {
        await pause()
        guard task(key).status.isSubmitted else { return nil }
        let zid = Self.roster[Self.sid(ofProject: key.projectID) - 1].zid
        let png = await MainActor.run { DemoContent.figurePNG() }
        return FileBundle(name: "\(zid)-task\(key.taskDefID).zip", entries: [
            ZipEntry(path: "main.tex", data: Data(DemoContent.mainTex(zid: zid).utf8)),
            ZipEntry(path: "dp.tex", data: Data(DemoContent.dpTex.utf8)),
            ZipEntry(path: "figure-recurrence.png", data: png),
            ZipEntry(path: "Makefile", data: Data(DemoContent.makefile.utf8)),
        ])
    }

    func regeneratePDF(_ key: TaskKey) async throws { await pause() }

    func taskSheet(unitID: Int, taskDefID: Int) async throws -> Data {
        let td = Self.taskDefs.first { $0.id == taskDefID }
        let title = td?.name ?? "Task sheet"
        let header = "COMP3121/9101 · 26T3 · Task \(td?.abbreviation ?? "")"
        return await MainActor.run { DemoContent.sheetPDF(header: header, title: title) }
    }

    func taskResources(unitID: Int, taskDefID: Int) async throws -> FileBundle? {
        FileBundle(name: "resources.zip", entries: [
            ZipEntry(path: "starter.tex", data: Data(DemoContent.mainTex(zid: "zXXXXXXX").utf8)),
            ZipEntry(path: "intervals.txt", data: Data("0 3 5\n1 4 1\n3 5 8\n4 7 4\n6 9 3\n".utf8)),
        ])
    }

    func comments(_ key: TaskKey) async throws -> [Comment] {
        await pause()
        update(key) { $0.numNewComments = 0 }
        return thread(key)
    }

    func postComment(_ key: TaskKey, text: String, replyTo: Int?) async throws -> Comment {
        await pause()
        var list = thread(key)
        if let last = list.last(where: { $0.author?.id == Self.me.id && $0.kind == "text" }), last.comment == text {
            throw APIError.duplicate("This comment duplicates the last one.")
        }
        let sid = Self.sid(ofProject: key.projectID)
        let c = Comment(id: newID(), comment: text, hasAttachment: false, type: "text", isNew: false, replyToId: replyTo,
                        author: Self.me, recipient: Self.user(sid), createdAt: Self.iso(.now))
        list.append(c)
        threads[key] = list
        return c
    }

    func postAttachment(_ key: TaskKey, filename: String, mimeType: String, data: Data) async throws -> Comment {
        await pause()
        var list = thread(key)
        let kind = mimeType.hasPrefix("image") ? "image" : mimeType == "application/pdf" ? "pdf" : "text"
        let sid = Self.sid(ofProject: key.projectID)
        let c = Comment(id: newID(), comment: filename, hasAttachment: true, type: kind, isNew: false, replyToId: nil,
                        author: Self.me, recipient: Self.user(sid), createdAt: Self.iso(.now))
        attachments[c.id] = DownloadedFile(data: data, filename: filename, mimeType: mimeType)
        list.append(c)
        threads[key] = list
        return c
    }

    func deleteComment(_ key: TaskKey, id: Int) async throws {
        await pause()
        threads[key] = thread(key).filter { $0.id != id }
    }

    func commentAttachment(_ key: TaskKey, id: Int) async throws -> DownloadedFile {
        if let f = attachments[id] { return f }
        let pdf = await MainActor.run { DemoContent.submissionPDF(header: "Attachment", title: "master-theorem-v2.pdf") }
        return DownloadedFile(data: pdf, filename: "master-theorem-v2.pdf", mimeType: "application/pdf")
    }

    func assessExtension(_ key: TaskKey, commentID: Int, granted: Bool) async throws {
        await pause()
        var list = thread(key)
        if let i = list.firstIndex(where: { $0.id == commentID }) {
            list[i].assessed = true
            list[i].granted = granted
            list[i].dateAssessed = Self.iso(.now)
        }
        threads[key] = list
        update(key) { $0.hasExtensions = false }
    }

    func setStatus(_ key: TaskKey, trigger: TaskStatus, grade: Int?, qualityPts: Int) async throws {
        await pause()
        update(key) { $0.statusKey = trigger.rawValue }
        var list = thread(key)
        let sid = Self.sid(ofProject: key.projectID)
        list.append(Comment(id: newID(), comment: nil, hasAttachment: false, type: "status", isNew: false, replyToId: nil,
                            author: Self.me, recipient: Self.user(sid), createdAt: Self.iso(.now), status: trigger.rawValue))
        threads[key] = list
    }

    func setPinned(taskID: Int, pinned: Bool) async throws {
        await pause()
        if let i = tasks.firstIndex(where: { $0.id == taskID }) { tasks[i].pinned = pinned }
    }

    func staffNotes(projectID: Int) async throws -> [StaffNote] { notes[projectID] ?? [] }

    func addStaffNote(projectID: Int, text: String) async throws -> StaffNote {
        await pause()
        let n = StaffNote(id: newID(), note: text, createdAt: Self.iso(.now), updatedAt: nil, replyToId: nil, userId: Self.me.id)
        notes[projectID, default: []].insert(n, at: 0)
        return n
    }

    func deleteStaffNote(projectID: Int, id: Int) async throws {
        await pause()
        notes[projectID]?.removeAll { $0.id == id }
    }

    func csv(unitID: Int, report: CSVReport) async throws -> DownloadedFile {
        var rows = ["student,zid,task,status"]
        for t in tasks {
            let s = Self.roster[Self.sid(ofProject: t.projectId) - 1]
            let td = Self.taskDefs.first { $0.id == t.taskDefinitionId }?.abbreviation ?? ""
            rows.append("\(s.first) \(s.last),\(s.zid),\(td),\(t.statusKey)")
        }
        return DownloadedFile(data: Data(rows.joined(separator: "\n").utf8), filename: "demo-\(report.rawValue).csv", mimeType: "text/csv")
    }

    func signOut() async {}
}

@MainActor
enum DemoContent {
    static func submissionPDF(header: String, title: String) -> Data {
        pdf(header: header, title: title, paragraphs: [
            "Problem. Given n intervals [s_i, f_i) with weights w_i > 0, choose a set of pairwise disjoint intervals of maximum total weight.",
            "1. Subproblems. Sort by finish time. Let p(i) be the largest j < i with f_j ≤ s_i. Define OPT(i) as the maximum weight achievable using only intervals 1..i.",
            "2. Recurrence. OPT(i) = max{ OPT(i−1), w_i + OPT(p(i)) }, with OPT(0) = 0.",
            "3. Correctness. Either interval i is in some optimal solution or it is not. If it is not, OPT(i) = OPT(i−1). If it is, no interval in p(i)+1..i−1 can be chosen, so the remainder is an optimal solution for 1..p(i); otherwise we could exchange it for a heavier one, a contradiction.",
            "4. Running time. Sorting costs O(n log n). Each p(i) is found by binary search over finish times, O(n log n) in total. Filling the table is O(n). Overall O(n log n).",
        ], secondPage: [
            "5. Reconstruction. Walk back from i = n: if w_i + OPT(p(i)) ≥ OPT(i−1), take interval i and jump to p(i); otherwise move to i−1. This visits each index at most once, so it adds O(n).",
        ])
    }

    static func sheetPDF(header: String, title: String) -> Data {
        pdf(header: header, title: title, paragraphs: [
            "Weighted interval scheduling. Give the subproblem definition, the recurrence with base cases, a correctness argument, and the running time of your algorithm.",
            "Then explain in two sentences why the greedy choice from Task 3.1 fails once intervals carry weights.",
            "Due: first attempt before your tutorial; final submission one week later. Submit a single PDF compiled from LaTeX.",
        ], secondPage: nil)
    }

    private static func pdf(header: String, title: String, paragraphs: [String], secondPage: [String]?) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let body = UIFont(name: "TimesNewRomanPSMT", size: 13) ?? .systemFont(ofSize: 13)
        let bold = UIFont(name: "TimesNewRomanPS-BoldMT", size: 20) ?? .boldSystemFont(ofSize: 20)
        let small = UIFont.systemFont(ofSize: 10)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            func draw(_ s: String, _ font: UIFont, _ color: UIColor, _ y: inout CGFloat) {
                let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
                let rect = attr.boundingRect(with: CGSize(width: 483, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
                attr.draw(with: CGRect(x: 56, y: y, width: 483, height: rect.height), options: [.usesLineFragmentOrigin], context: nil)
                y += rect.height + 12
            }
            ctx.beginPage()
            var y: CGFloat = 52
            draw(header, small, .darkGray, &y)
            draw(title, bold, .black, &y)
            for p in paragraphs { draw(p, body, .black, &y) }
            if let secondPage {
                ctx.beginPage()
                y = 52
                draw(header, small, .darkGray, &y)
                for p in secondPage { draw(p, body, .black, &y) }
            }
        }
    }

    static func figurePNG() -> Data {
        let size = CGSize(width: 480, height: 280)
        return UIGraphicsImageRenderer(size: size).pngData { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let bars: [(CGFloat, CGFloat, CGFloat)] = [(20, 120, 40), (80, 260, 90), (160, 300, 140), (240, 420, 190), (320, 460, 240)]
            UIColor(hex: 0x3939ff).setFill()
            for (x0, x1, y) in bars { ctx.fill(CGRect(x: x0, y: y, width: x1 - x0, height: 18)) }
        }
    }

    nonisolated static func mainTex(zid: String) -> String {
        """
        \\documentclass[11pt]{article}
        \\usepackage{amsmath,amssymb}
        \\usepackage{algorithm2e}
        % weighted interval scheduling
        \\title{Task 3.2: Dynamic programming}
        \\author{\(zid)}
        \\begin{document}
        \\maketitle

        \\section*{Subproblems}
        Sort intervals by finish time $f_1 \\le \\dots \\le f_n$.
        Let $p(i)$ be the largest $j < i$ with $f_j \\le s_i$.

        \\section*{Recurrence}
        \\[ \\mathrm{OPT}(i) = \\max\\{\\mathrm{OPT}(i-1),\\; w_i + \\mathrm{OPT}(p(i))\\} \\]
        with $\\mathrm{OPT}(0) = 0$.

        \\section*{Running time}
        Sorting and computing $p(i)$ take $O(n \\log n)$;
        the table is $O(n)$.

        \\input{dp}
        \\end{document}
        """
    }

    nonisolated static let dpTex = """
        \\section*{Correctness}
        % exchange argument
        If interval $i$ is in an optimal solution, the rest is optimal for $1..p(i)$.
        Otherwise $\\mathrm{OPT}(i) = \\mathrm{OPT}(i-1)$.
        """

    nonisolated static let makefile = """
        all: main.pdf

        main.pdf: main.tex dp.tex
        \tlatexmk -pdf main.tex

        clean:
        \tlatexmk -C
        """
}
