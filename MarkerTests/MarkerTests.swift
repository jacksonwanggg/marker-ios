import Foundation
import Testing
import UserNotifications
@testable import Marker

@Suite struct DecodeTests {
    @Test func decodesInboxRow() throws {
        let json = """
        [{"id":1,"project_id":2,"task_definition_id":3,"tutorial_id":4,"status":"ready_for_feedback",
          "completion_date":null,"submission_date":"2026-09-14T07:24:04.146Z","times_assessed":1,"grade":null,
          "quality_pts":-1,"num_new_comments":2,"similarity_flag":false,"pinned":1,"has_extensions":0}]
        """
        let rows = try JSON.decoder().decode([TaskSummary].self, from: Data(json.utf8))
        #expect(rows.count == 1)
        #expect(rows[0].pinned)
        #expect(!rows[0].hasExtensions)
        #expect(rows[0].status == .readyForFeedback)
        #expect(rows[0].numNewComments == 2)
        #expect(rows[0].submitted != nil)
        #expect(rows[0].key == TaskKey(projectID: 2, taskDefID: 3))
    }

    @Test func missingCommentCountIsZero() throws {
        let json = """
        [{"project_id":9,"id":8,"task_definition_id":7,"tutorial_id":6,"tutorial_stream_id":33,"status":"complete",
          "submission_date":"2026-09-17T06:22:53.270Z","times_assessed":2,"similarity_flag":false,"grade":null,
          "quality_pts":-1,"has_extensions":true}]
        """
        let rows = try JSON.decoder().decode([TaskSummary].self, from: Data(json.utf8))
        #expect(rows[0].numNewComments == 0)
        #expect(rows[0].hasExtensions)
        #expect(!rows[0].pinned)
    }

    @Test func decodesCommentKinds() throws {
        let json = """
        [{"id":1,"comment":"","has_attachment":false,"type":"status","is_new":false,"reply_to_id":null,
          "author":{"id":10,"first_name":"Sam","last_name":"Lee","email":"x"},"recipient":{"id":20,"first_name":"Ana","last_name":"B","email":"y"},
          "created_at":"2026-09-16T13:27:50.704Z","recipient_read_time":null,"status":"ready_for_feedback"},
         {"id":2,"comment":"looks good","has_attachment":false,"type":"text","is_new":true,"reply_to_id":1,
          "author":{"id":20,"first_name":"Ana","last_name":"B"},"recipient":{"id":10,"first_name":"Sam","last_name":"Lee"},
          "created_at":"2026-09-16T14:00:00.000Z","recipient_read_time":"2026-09-17T06:05:02.483Z"},
         {"id":3,"comment":"sick","type":"extension","author":{"id":10},"created_at":"2026-09-18T01:00:00Z",
          "assessed":false,"granted":false,"weeks_requested":1,"due_date":"2026-10-09"}]
        """
        let list = try JSON.decoder().decode([Marker.Comment].self, from: Data(json.utf8))
        #expect(list.map(\.kind) == ["status", "text", "extension"])
        #expect(list[1].replyToId == 1)
        #expect(Fmt.parse(list[1].recipientReadTime) != nil)
        #expect(list[2].weeksRequested == 1)
        #expect(list[2].assessed == false)
    }

    @Test func skipsBadRecords() throws {
        // a null tutorial_id only drops that enrolment
        let json = """
        [{"id":1,"student":{"id":2,"first_name":"A"},"tutorial_enrolments":[{"tutorial_id":null},{"tutorial_id":5}]},
         {"id":"oops","student":null},
         {"id":3,"student":{"id":4,"first_name":"B"},"tutorial_enrolments":[]}]
        """
        let list = try JSON.decoder().decode(LossyList<ProjectSummary>.self, from: Data(json.utf8))
        #expect(list.items.map(\.id) == [1, 3])
        #expect(list.skipped == 1)
        #expect(list.items[0].tutorialIDs == [5])

        let unit = """
        {"id":9,"code":"C","task_definitions":[{"id":1,"abbreviation":"1.1","name":"(W) A"},{"id":null}],"tutorials":[{"abbreviation":"x"}]}
        """
        let u = try JSON.decoder().decode(UnitDetail.self, from: Data(unit.utf8))
        #expect(u.taskDefinitions.map(\.id) == [1])
        #expect(u.tutorials.isEmpty)
    }

    @Test func qaGuardBlocksSideEffects() {
        #expect(FormatifClient.qaBlockReason("POST", "projects/1/task_def_id/2/comments/") != nil)
        #expect(FormatifClient.qaBlockReason("PUT", "projects/1/task_def_id/2") != nil)
        #expect(FormatifClient.qaBlockReason("DELETE", "auth") != nil)
        #expect(FormatifClient.qaBlockReason("GET", "projects/1/task_def_id/2/comments") != nil)
        #expect(FormatifClient.qaBlockReason("GET", "projects/1/task_def_id/2/comments/9") != nil)
        #expect(FormatifClient.qaBlockReason("GET", "projects/1/task_def_id/2/submission") != nil)
        #expect(FormatifClient.qaBlockReason("GET", "projects/1/task_def_id/2/submission_files") != nil)
        #expect(FormatifClient.qaBlockReason("GET", "projects/1/task_def_id/2/submission_details") != nil)
        #expect(FormatifClient.qaBlockReason("GET", "units/1/tasks/inbox") == nil)
        #expect(FormatifClient.qaBlockReason("GET", "units/1/task_definitions/7/task_pdf.json") == nil)
        #expect(FormatifClient.qaBlockReason("GET", "projects/1/staff_notes") == nil)
    }

    @Test func decodesUnitAndStudents() throws {
        let unit = """
        {"code":"COMP0000","id":1,"name":"Test","my_role":"Tutor","start_date":"2026-09-14",
         "tutorials":[{"id":5,"meeting_day":"Monday","meeting_time":"10am-12pm","meeting_location":"G01","abbreviation":"M10A",
                       "campus_id":1,"capacity":36,"tutorial_stream_abbr":"Lab","num_students":11,"tutor_id":99}],
         "task_definitions":[{"id":7,"abbreviation":"1.2","name":"(W) Grid","target_grade":0,"due_date":"2026-10-02",
                              "has_task_sheet":true,"is_graded":false,"max_quality_pts":0},
                             {"id":8,"abbreviation":"0.1","name":"(M) Getting Started","target_grade":0}],
         "staff":[{"id":1,"role":"Tutor","user":{"id":99,"first_name":"T","last_name":"U"}}]}
        """
        let u = try JSON.decoder().decode(UnitDetail.self, from: Data(unit.utf8))
        #expect(u.tutorials[0].tutorId == 99)
        #expect(u.taskDefinitions[1].isMoodle)
        #expect(!u.taskDefinitions[0].isMoodle)

        let students = """
        [{"id":3,"enrolled":true,"student":{"id":4,"student_id":"z1234567","username":"z1234567","first_name":"Ana","last_name":"B"},
          "target_grade":3,"tutorial_enrolments":[{"stream_abbr":"Lab","tutorial_id":5}],"staff_note_count":0}]
        """
        let s = try JSON.decoder().decode([ProjectSummary].self, from: Data(students.utf8))
        #expect(s[0].student.zid == "z1234567")
        #expect(s[0].tutorialIDs == [5])
        #expect(Grade.letter(s[0].targetGrade) == "HD")
    }
}

private func task(_ status: TaskStatus, id: Int = 1, taskDef: Int = 3, comments: Int = 0, ext: Bool = false,
                  submitted: String? = "2026-10-01T00:00:00Z", assessed: Int = 0) -> TaskSummary {
    TaskSummary(id: id, projectId: 2, taskDefinitionId: taskDef, tutorialId: 4, statusKey: status.rawValue, completionDate: nil,
                submissionDate: submitted, timesAssessed: assessed, grade: nil, qualityPts: -1, numNewComments: comments,
                similarityFlag: false, pinned: false, hasExtensions: ext)
}

@Suite struct NotificationTests {
    let lookup = Lookup(unitCode: "COMP0000", students: [2: "Ana B"], taskDefs: [3: "1.2 · (W) Grid"])

    @Test func summaryBody() {
        let r = Notifier.summaryRequest(inbox: [task(.readyForFeedback), task(.discuss, comments: 1)], lookup: lookup, prefs: Prefs())
        #expect(r?.content.body == "COMP0000: 1 waiting for feedback and 1 thread with unread comments.")
    }

    @Test func firstRunIsSilent() {
        #expect(Notifier.diff(old: nil, new: [task(.readyForFeedback)], lookup: lookup).isEmpty)
    }

    @Test func diffEvents() {
        let a = Notifier.snapshot([task(.workingOnIt)])
        let events = Notifier.diff(old: a, new: [task(.readyForFeedback, comments: 2, ext: true)], lookup: lookup)
        #expect(events.map(\.kind) == [.newWork, .comment, .extensionRequest])
        #expect(events[1].body == "2 new comments.")
        #expect(events[0].title == "Ana B · 1.2 · (W) Grid")
        #expect(events.allSatisfy { $0.key == TaskKey(projectID: 2, taskDefID: 3) })
    }

    @Test func resubmissionAlerts() {
        let a = Notifier.snapshot([task(.readyForFeedback)])
        #expect(Notifier.diff(old: a, new: [task(.readyForFeedback)], lookup: lookup).isEmpty)
        let resub = Notifier.diff(old: a, new: [task(.readyForFeedback, submitted: "2026-10-03T00:00:00Z", assessed: 1)], lookup: lookup)
        #expect(resub.map(\.kind) == [.resubmission])
        // reading a thread resets num_new_comments, which isn't an alert
        let read = Notifier.diff(old: Notifier.snapshot([task(.complete, comments: 3)]), new: [task(.complete)], lookup: lookup)
        #expect(read.isEmpty)
    }

    @Test func badgeCount() {
        let other = task(.discuss, id: 2, taskDef: 5, comments: 1, submitted: nil)
        #expect(Notifier.badgeCount([task(.readyForFeedback, comments: 1), other]) == 2)
    }
}

@Suite struct BumpTests {
    let lookup = Lookup(unitCode: "C", students: [:], taskDefs: [:])

    @Test func waitTiers() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        func at(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
        #expect(WaitTier.of(status: .readyForFeedback, submitted: at(1.9), now: now) == .none)
        #expect(WaitTier.of(status: .readyForFeedback, submitted: at(2.1), now: now) == .first)
        #expect(WaitTier.of(status: .readyForFeedback, submitted: at(3.5), now: now) == .second)
        #expect(WaitTier.of(status: .readyForFeedback, submitted: at(4), now: now) == .third)
        #expect(WaitTier.of(status: .readyForFeedback, submitted: at(9), now: now) == .overdue)
        #expect(WaitTier.of(status: .readyForFeedback, submitted: at(5), now: now, after: [1, 5, 6, 10]) == .second)
        #expect(WaitTier.of(status: .complete, submitted: at(9), now: now) == .none)
        #expect(WaitTier.third.tag(days: 6) == "Waiting 6 days")
        #expect(WaitTier.overdue.tag(days: 7) == "Overdue · 1 week, no feedback")
        #expect(WaitTier.overdue.tag(days: 9) == "Overdue · 9 days, no feedback")
    }

    @Test func schedulesBumps() {
        let now = Date.now
        let submitted = now.addingTimeInterval(-2.5 * 86_400).formatted(Date.ISO8601FormatStyle())
        let t = task(.readyForFeedback, id: 7, submitted: submitted)
        var prefs = Prefs()
        prefs.quietHours = false
        let ids = Notifier.bumpRequests(inbox: [t], lookup: lookup, prefs: prefs, now: now).map(\.identifier)
        #expect(ids == ["bump-7-3", "bump-7-4", "bump-7-7"])
        prefs.setBump(.third, false)
        #expect(Notifier.bumpRequests(inbox: [t], lookup: lookup, prefs: prefs, now: now).map(\.identifier) == ["bump-7-3", "bump-7-7"])
        let done = task(.complete, id: 7, submitted: submitted, assessed: 1)
        #expect(Notifier.bumpRequests(inbox: [done], lookup: lookup, prefs: prefs, now: now).isEmpty)
    }

    @Test func defaultQuietHours() {
        let cal = Calendar.current
        let prefs = Prefs()
        let late = cal.date(bySettingHour: 23, minute: 30, second: 0, of: Date.now)!
        let moved = prefs.outOfQuiet(late)
        #expect(cal.component(.hour, from: moved) == 8)
        #expect(moved > late)
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date.now)!
        #expect(prefs.outOfQuiet(noon) == noon)
    }

    @Test func customQuietHours() {
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: Date.now)! }
        var p = Prefs()
        p.quietFrom = 21 * 60 + 30
        p.quietUntil = 7 * 60
        #expect(p.isQuiet(at(21, 30)))
        #expect(p.isQuiet(at(3)))
        #expect(!p.isQuiet(at(7)))
        #expect(!p.isQuiet(at(21, 29)))
        let moved = p.outOfQuiet(at(22))
        #expect(cal.component(.hour, from: moved) == 7 && moved > at(22))
        p.quietFrom = 12 * 60
        p.quietUntil = 14 * 60
        #expect(p.isQuiet(at(13)) && !p.isQuiet(at(14)) && !p.isQuiet(at(11)))
        #expect(cal.component(.hour, from: p.outOfQuiet(at(13))) == 14)
        p.quietHours = false
        #expect(!p.isQuiet(at(13)))
    }

    @Test func reminderDaysStayInOrder() {
        var p = Prefs()
        p.setDays(.first, 5)
        #expect(p.bumpAfter == [5, 6, 7, 8])
        p.setDays(.overdue, 3)
        #expect(p.bumpAfter == [1, 2, 3, 4], "overdue can't come before three earlier reminders")
        p.setDays(.second, 40)
        #expect(p.bumpAfter == [1, 26, 27, 28], "capped so the later ones still fit")
    }

    @Test func decodesOldPrefs() throws {
        let old = """
        {"notifyWork":false,"notifyComments":true,"notifyExtensions":true,"notifyExpiry":true,"dailySummary":false,"quietHours":true,
         "bumpDays":[2,7],"hideComplete":false,"hideMoodle":true,"oldestFirst":true,"theme":"dark"}
        """
        let p = try JSONDecoder().decode(Prefs.self, from: Data(old.utf8))
        #expect(p.notifyWork == false && p.dailySummary == false && p.hideComplete == false)
        #expect(p.bumpEnabled == [true, false, false, true])
        #expect(p.bumpAfter == [2, 3, 4, 7] && p.summaryAt == 480 && p.quietFrom == 1320 && p.bumpAt == nil)
        var q = p
        q.bumpAt = 9 * 60
        q.summaryDays = [1, 7]
        let back = try JSONDecoder().decode(Prefs.self, from: JSONEncoder().encode(q))
        #expect(back == q)
    }

    @Test func summarySchedule() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        var p = Prefs()
        p.summaryAt = 17 * 60 + 30
        p.summaryDays = [1]  // sundays only
        let now = Date.now
        let next = Notifier.nextSummary(after: now, prefs: p, calendar: cal)!
        #expect(next > now && next.timeIntervalSince(now) <= 7 * 86_400 + 3600)
        #expect(cal.component(.weekday, from: next) == 1)
        #expect(cal.component(.hour, from: next) == 17 && cal.component(.minute, from: next) == 30)
        p.summaryDays = []
        #expect(Notifier.nextSummary(after: now, prefs: p, calendar: cal) == nil)
    }

    @Test func bumpsAtSetTime() {
        let cal = Calendar.current
        let now = Date.now
        // the 2-day bump should land on the first 09:15 after the 2-day mark
        let submitted = now.addingTimeInterval(-1.5 * 86_400)
        let t = task(.readyForFeedback, id: 9, submitted: submitted.formatted(Date.ISO8601FormatStyle()))
        var prefs = Prefs()
        prefs.quietHours = false
        prefs.bumpAt = 9 * 60 + 15
        let reqs = Notifier.bumpRequests(inbox: [t], lookup: lookup, prefs: prefs, now: now)
        #expect(reqs.map(\.identifier) == ["bump-9-2", "bump-9-3", "bump-9-4", "bump-9-7"])
        let first = reqs[0].trigger as! UNTimeIntervalNotificationTrigger
        let fire = now.addingTimeInterval(first.timeInterval)
        let twoDayMark = submitted.addingTimeInterval(2 * 86_400)
        #expect(fire >= twoDayMark.addingTimeInterval(-2) && fire.timeIntervalSince(twoDayMark) < 86_400 + 2)
        #expect(cal.component(.hour, from: fire) == 9 && cal.component(.minute, from: fire) == 15)
        #expect(reqs[3].content.title == "Overdue · 1 week, no feedback")
    }
}

@Suite struct LabelTests {
    @MainActor @Test func unitLabelHasFullYear() {
        let u = UnitSummary(id: 1, code: "COMP1234/5678", startDate: "2026-09-14")
        let label = AppModel().unitLabel(u)
        #expect(label.hasPrefix("COMP1234/5678 · "))
        #expect(label.hasSuffix(" 2026"), "\(label)")
        #expect(AppModel().unitLabel(UnitSummary(id: 2, code: "COMP9020")) == "COMP9020")
    }
}

@Suite struct EncodingTests {
    @Test func multipartBody() {
        var m = Multipart(boundary: "B")
        m.add("comment", "hi there")
        m.add("reply_to_id", "42")
        let body = String(decoding: m.encoded(), as: UTF8.self)
        let expected = "--B\r\nContent-Disposition: form-data; name=\"comment\"\r\n\r\nhi there\r\n"
            + "--B\r\nContent-Disposition: form-data; name=\"reply_to_id\"\r\n\r\n42\r\n--B--\r\n"
        #expect(m.contentType == "multipart/form-data; boundary=B")
        #expect(body == expected)
    }

    @Test func zipSkipsJunk() throws {
        let entries = try Zip.entries(TestZip.stored(["a.tex": "\\section{x}", "dir/": "", "__MACOSX/a.tex": "junk", "b.txt": "hello"]))
        #expect(entries.map(\.path).sorted() == ["a.tex", "b.txt"])
        let b = try #require(entries.first { $0.path == "b.txt" })
        #expect(String(decoding: b.data, as: UTF8.self) == "hello")
        #expect(entries.allSatisfy { $0.isText })
    }

    @Test func signInRedirect() {
        let url = URL(string: "https://formatif.cse.unsw.edu.au/sign_in?authToken=abc123&username=z1234567")!
        let got = SSOWebView.Coordinator.token(from: url)
        #expect(got?.0 == "abc123")
        #expect(got?.1 == "z1234567")
        #expect(SSOWebView.Coordinator.token(from: URL(string: "https://login.microsoftonline.com/x?authToken=a&username=b")!) == nil)
    }
}

// uncompressed zip with zero crcs, which Zip doesn't check
enum TestZip {
    static func stored(_ files: [String: String]) -> Data {
        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8 & 0xff)] }
        func u32(_ v: Int) -> [UInt8] { u16(v & 0xffff) + u16(v >> 16 & 0xffff) }
        func zeros(_ n: Int) -> [UInt8] { [UInt8](repeating: 0, count: n) }

        var local: [UInt8] = [], central: [UInt8] = []
        for (name, text) in files.sorted(by: { $0.key < $1.key }) {
            let n = [UInt8](name.utf8), d = [UInt8](text.utf8)
            // crc, compressed size, size, name length
            let sizes = u32(0) + u32(d.count) + u32(d.count) + u16(n.count)
            central += u32(0x02014b50) + u16(20) + u16(20) + zeros(8) + sizes + zeros(12) + u32(local.count) + n
            local += u32(0x04034b50) + u16(20) + zeros(8) + sizes + u16(0) + n + d
        }
        let end = u32(0x06054b50) + zeros(4) + u16(files.count) + u16(files.count) + u32(central.count) + u32(local.count) + u16(0)
        return Data(local + central + end)
    }
}

final class MockProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: String], Data))?
    nonisolated(unsafe) static var log: [URLRequest] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var req = request
        if req.httpBody == nil, let stream = req.httpBodyStream {
            stream.open()
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            stream.close()
            req.httpBody = data
        }
        Self.lock.lock()
        Self.log.append(req)
        let (code, headers, body) = Self.handler?(req) ?? (500, [:], Data())
        Self.lock.unlock()
        let resp = HTTPURLResponse(url: req.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct ClientTests {
    func makeClient() -> FormatifClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockProtocol.self]
        let now = Date.now
        let creds = Credentials(username: "z1234567", authToken: "old", refreshToken: "R1", userID: 1,
                                signedInAt: now, refreshExpiry: now.addingTimeInterval(86_400), tokenIssuedAt: now)
        MockProtocol.log = []
        return FormatifClient(credentials: creds, session: URLSession(configuration: cfg), persist: false)
    }

    @Test func setStatusRequest() async throws {
        let client = makeClient()
        MockProtocol.handler = { _ in (200, ["Content-Type": "application/json"], Data("{}".utf8)) }
        try await LiveBackend(client: client).setStatus(TaskKey(projectID: 5, taskDefID: 6), trigger: .complete, grade: nil, qualityPts: -1)
        let req = try #require(MockProtocol.log.last)
        #expect(req.httpMethod == "PUT")
        #expect(req.url?.path == "/api/projects/5/task_def_id/6")
        #expect(req.value(forHTTPHeaderField: "auth-token") == "old")
        #expect(req.value(forHTTPHeaderField: "username") == "z1234567")
        let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]
        #expect(body?["trigger"] as? String == "complete")
        #expect(body?["quality_pts"] as? Int == -1)
        #expect(body?["discussed"] == nil)
        #expect(body?["grade"] is NSNull)
    }

    @Test func commentRequest() async throws {
        let client = makeClient()
        MockProtocol.handler = { _ in (201, [:], Data(#"{"id":9,"comment":"hey","type":"text"}"#.utf8)) }
        let c = try await LiveBackend(client: client).postComment(TaskKey(projectID: 1, taskDefID: 2), text: "hey", replyTo: 7)
        #expect(c.id == 9)
        let req = try #require(MockProtocol.log.last)
        #expect(req.url?.absoluteString == "https://formatif.cse.unsw.edu.au/api/projects/1/task_def_id/2/comments/")
        #expect(req.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = String(decoding: req.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("name=\"comment\"\r\n\r\nhey"))
        #expect(body.contains("name=\"reply_to_id\"\r\n\r\n7"))
    }

    @Test func duplicateComment() async {
        let client = makeClient()
        MockProtocol.handler = { _ in (403, [:], Data(#"{"error":"This comment duplicates the last one"}"#.utf8)) }
        await #expect(throws: APIError.duplicate("This comment duplicates the last one")) {
            _ = try await LiveBackend(client: client).postComment(TaskKey(projectID: 1, taskDefID: 2), text: "x", replyTo: nil)
        }
    }

    @Test func refreshesOnce() async throws {
        let client = makeClient()
        MockProtocol.handler = { req in
            if req.url?.path == "/api/auth/access-token" {
                return (201, ["Set-Cookie": "refresh_token=R2; path=/api/auth; HttpOnly"], Data(#"{"auth_token":"new","user":{"id":1}}"#.utf8))
            }
            if req.value(forHTTPHeaderField: "auth-token") == "new" { return (200, [:], Data("[]".utf8)) }
            return (419, [:], Data(#"{"error":"expired"}"#.utf8))
        }
        let backend = LiveBackend(client: client)
        async let a = backend.inbox(unitID: 1, myStudentsOnly: true)
        async let b = backend.explorer(unitID: 1, taskDefID: 2)
        async let c = backend.prerequisites(unitID: 1)
        _ = try await (a, b, c)
        let refreshes = MockProtocol.log.filter { $0.url?.path == "/api/auth/access-token" }
        #expect(refreshes.count == 1)
        #expect(refreshes[0].value(forHTTPHeaderField: "Cookie") == "username=z1234567; refresh_token=R1")
        let creds = await client.credentials
        #expect(creds?.authToken == "new")
        #expect(creds?.refreshToken == "R2")
    }

    @Test func deadRefreshTokenEndsSession() async {
        let client = makeClient()
        MockProtocol.handler = { req in
            req.url?.path == "/api/auth/access-token" ? (401, [:], Data()) : (419, [:], Data())
        }
        await #expect(throws: APIError.sessionExpired) {
            _ = try await LiveBackend(client: client).inbox(unitID: 1, myStudentsOnly: true)
        }
        #expect(await client.credentials == nil)
    }
}
