import Foundation
import Observation
import WebKit

/// A local edit. It wins over list data fetched before it.
struct Patch: Sendable {
    var status: TaskStatus?
    var newComments: Int?
    var pinned: Bool?
    var hasExtensions: Bool?
    var at: Date = .now
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

@MainActor @Observable
final class DeepLinks {
    static let shared = DeepLinks()
    var pending: DeepLink?
}

@MainActor @Observable
final class AppModel {
    nonisolated static let unitKey = "unitID"

    enum Phase { case launching, signedOut, signedIn }
    enum Scope: Hashable { case mine, tutorial(Int), all }

    var phase: Phase = .launching
    var signOutReason: String?
    private(set) var backend: any MarkerBackend = SignedOutBackend()
    private var client: FormatifClient?
    private(set) var isDemo = false
    var credentials: Credentials?

    var unitRoles: [UnitRole] = []
    var unitID: Int?
    var unit: UnitDetail?
    var students: [ProjectSummary] = []
    var projects: [Int: ProjectSummary] = [:]
    var prerequisites: [Prerequisite] = []
    private var taskDefsByID: [Int: TaskDefinition] = [:]

    var inbox: [TaskSummary] = []
    var mineInbox: [TaskSummary] = []
    var inboxFetchedAt: Date = .distantPast
    var inboxLoading = false
    var inboxError: String?
    var lastRefresh: Date?

    var scope: Scope = .mine
    var search = ""
    var statusFilter: TaskStatus?
    var waitingOnly = false

    var prefs: Prefs = .load() {
        didSet {
            guard prefs != oldValue else { return }
            prefs.save()
            Task { await rescheduleReminders() }
        }
    }

    var events: [AlertEvent] = []
    var toast: Toast?
    var haptic = 0
    var patches: [TaskKey: Patch] = [:]

    // MARK: lookups

    var myUserID: Int? { credentials?.userID ?? unitRoles.first?.user?.id }

    var myTutorialIDs: Set<Int> {
        guard let me = myUserID else { return [] }
        return Set((unit?.tutorials ?? []).filter { $0.tutorId == me }.map(\.id))
    }

    var currentRole: UnitRole? { unitRoles.first { $0.unit.id == unitID } }

    func taskDef(_ id: Int) -> TaskDefinition? { taskDefsByID[id] }
    func studentName(_ projectID: Int) -> String { projects[projectID]?.student.name ?? "Student \(projectID)" }
    func zid(_ projectID: Int) -> String { projects[projectID]?.student.zid ?? "" }
    func taskLine(_ tdID: Int) -> String { taskDef(tdID)?.line ?? "Task \(tdID)" }
    func tutorial(_ id: Int?) -> Tutorial? { unit?.tutorials.first { $0.id == id } }

    var lookup: Lookup {
        Lookup(unitCode: unit?.code ?? "",
               students: projects.mapValues { $0.student.name },
               taskDefs: taskDefsByID.mapValues { $0.line },
               moodleTasks: Set(taskDefsByID.values.filter(\.isMoodle).map(\.id)))
    }

    func tier(_ t: TaskSummary, now: Date = .now) -> WaitTier {
        WaitTier.of(status: t.status, submitted: t.submitted, now: now, after: prefs.bumpAfter)
    }

    func unitLabel(_ u: UnitSummary) -> String {
        guard let d = Fmt.parse(u.startDate) else { return u.code }
        return "\(u.code) · \(d.formatted(.dateTime.month(.abbreviated).year()))"
    }

    // MARK: patches

    func applying(_ t: TaskSummary, fetchedAt: Date) -> TaskSummary {
        guard let p = patches[t.key], p.at > fetchedAt else { return t }
        var t = t
        if let s = p.status { t.statusKey = s.rawValue }
        if let n = p.newComments { t.numNewComments = n }
        if let pin = p.pinned { t.pinned = pin }
        if let e = p.hasExtensions { t.hasExtensions = e }
        return t
    }

    private func patch(_ key: TaskKey, _ change: (inout Patch) -> Void) {
        var p = patches[key] ?? Patch()
        change(&p)
        p.at = .now
        patches[key] = p
    }

    // MARK: inbox

    var inboxRows: [TaskSummary] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let now = Date.now
        var rows = inbox.map { applying($0, fetchedAt: inboxFetchedAt) }.filter { t in
            if case .tutorial(let id) = scope, t.tutorialId != id { return false }
            if prefs.hideComplete, t.status == .complete { return false }
            if prefs.hideMoodle, taskDef(t.taskDefinitionId)?.isMoodle == true { return false }
            if let f = statusFilter, t.status != f { return false }
            if waitingOnly, tier(t, now: now) == .none { return false }
            if !q.isEmpty {
                let hay = [studentName(t.projectId), zid(t.projectId), taskLine(t.taskDefinitionId)].joined(separator: " ").lowercased()
                if !hay.contains(q) { return false }
            }
            return true
        }
        let oldest = prefs.oldestFirst
        rows.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            switch (a.submitted, b.submitted) {
            case let (da?, db?): return oldest ? da < db : da > db
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return a.id < b.id
            }
        }
        return rows
    }

    var patchedMine: [TaskSummary] { mineInbox.map { applying($0, fetchedAt: inboxFetchedAt) } }
    var badgeCount: Int { Notifier.badgeCount(patchedMine.filter { taskDef($0.taskDefinitionId)?.isMoodle != true }) }
    var unseenCount: Int { events.filter { !$0.seen }.count }

    var scopeLabel: String {
        switch scope {
        case .mine: "My students"
        case .all: "All students"
        case .tutorial(let id): "Tutorial \(tutorial(id)?.abbreviation ?? "")"
        }
    }

    // MARK: session

    func bootstrap() async {
        // -demo YES skips sign-in, for UI tests and screenshots
        if UserDefaults.standard.bool(forKey: "demo") {
            await enterDemo()
            return
        }
        #if DEBUG
        // QA: sign in with an existing token and don't save it
        let env = ProcessInfo.processInfo.environment
        if let token = env["MARKER_QA_TOKEN"], let user = env["MARKER_QA_USER"] {
            let now = Date.now
            let c = Credentials(username: user, authToken: token, refreshToken: nil, userID: env["MARKER_QA_USER_ID"].flatMap { Int($0) },
                                firstName: nil, lastName: nil, signedInAt: now, refreshExpiry: now.addingTimeInterval(7 * 86_400), tokenIssuedAt: now)
            await startLive(c, persist: false)
            return
        }
        #endif
        if let c = Keychain.loadCredentials() {
            await startLive(c)
        } else {
            phase = .signedOut
        }
    }

    func signIn(oneTimeToken: String, username: String) async throws {
        let c = try await FormatifClient.exchange(oneTimeToken: oneTimeToken, username: username)
        signOutReason = nil
        await startLive(c)
        await Notifier.requestAuthorization()
    }

    private func startLive(_ c: Credentials, persist: Bool = true) async {
        let client = FormatifClient(credentials: c, persist: persist)
        self.client = client
        backend = LiveBackend(client: client)
        isDemo = false
        credentials = c
        unitID = UserDefaults.standard.object(forKey: Self.unitKey) as? Int
        loadCachedState()
        events = Notifier.loadEvents()
        phase = .signedIn
        await loadAll()
    }

    func enterDemo() async {
        client = nil
        backend = DemoBackend()
        isDemo = true
        let now = Date.now
        credentials = Credentials(username: "z5123456", authToken: "demo", refreshToken: nil, userID: DemoBackend.me.id,
                                  firstName: "Alex", lastName: "Tutor", signedInAt: now,
                                  refreshExpiry: now.addingTimeInterval(7 * 86_400 - 3600), tokenIssuedAt: now)
        unitID = 1
        events = DemoFeed.events(now: now)
        phase = .signedIn
        await loadAll()
    }

    func loadAll() async {
        do {
            let roles = try await backend.unitRoles().filter(\.isStaff)
            unitRoles = roles.sorted { ($0.unit.startDate ?? "") > ($1.unit.startDate ?? "") }
            if unitID == nil || !unitRoles.contains(where: { $0.unit.id == unitID }) {
                unitID = (unitRoles.first { $0.unit.active ?? false } ?? unitRoles.first)?.unit.id
            }
            if credentials?.userID == nil, let uid = unitRoles.first?.user?.id { credentials?.userID = uid }
            await loadUnit()
        } catch {
            handle(error)
        }
    }

    func selectUnit(_ id: Int) async {
        guard id != unitID else { return }
        unitID = id
        if !isDemo { UserDefaults.standard.set(id, forKey: Self.unitKey) }
        unit = nil; students = []; projects = [:]; inbox = []; mineInbox = []; taskDefsByID = [:]
        scope = .mine; statusFilter = nil
        loadCachedState()
        await loadUnit()
    }

    func loadUnit() async {
        guard let unitID else { return }
        let b = backend
        do {
            async let u = b.unit(unitID)
            async let s = b.students(unitID: unitID)
            let detail = try await u
            var studs = students
            do {
                studs = try await s
            } catch {
                show("Couldn't load the student list. \(message(error))", error: true)
            }
            setUnit(detail, studs)
            if !isDemo {
                UserDefaults.standard.set(unitID, forKey: Self.unitKey)
                DiskCache.write(detail, "unit-\(unitID).json", snake: true)
                DiskCache.write(studs, "students-\(unitID).json", snake: true)
                DiskCache.write(lookup, "lookup-\(unitID).json", support: true)
            }
            prerequisites = (try? await b.prerequisites(unitID: unitID)) ?? []
            await refreshInbox()
        } catch {
            handle(error)
        }
    }

    private func setUnit(_ detail: UnitDetail, _ studs: [ProjectSummary]) {
        unit = detail
        taskDefsByID = Dictionary(detail.taskDefinitions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        students = studs.sorted { $0.student.name.localizedCaseInsensitiveCompare($1.student.name) == .orderedAscending }
        projects = Dictionary(studs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func loadCachedState() {
        guard !isDemo, let unitID else { return }
        if let u = DiskCache.read(UnitDetail.self, "unit-\(unitID).json", snake: true) {
            setUnit(u, DiskCache.read([ProjectSummary].self, "students-\(unitID).json", snake: true) ?? [])
        }
        if let rows = DiskCache.read([TaskSummary].self, "inbox-mine-\(unitID).json", snake: true) {
            mineInbox = rows
            inbox = rows
        }
    }

    func refreshInbox() async {
        guard let unitID, phase == .signedIn else { return }
        inboxLoading = true
        defer { inboxLoading = false }
        let b = backend
        let mineOnly = scope == .mine
        do {
            let rows = try await b.inbox(unitID: unitID, myStudentsOnly: mineOnly)
            let fetched = Date.now
            if mineOnly {
                mineInbox = rows
            } else if let mine = try? await b.inbox(unitID: unitID, myStudentsOnly: true) {
                mineInbox = mine
            }
            inbox = rows
            inboxFetchedAt = fetched
            inboxError = nil
            lastRefresh = fetched
            if !isDemo {
                DiskCache.write(mineInbox, "inbox-mine-\(unitID).json", snake: true)
                await Notifier.process(unitID: unitID, inbox: mineInbox, lookup: lookup, prefs: prefs, expiry: credentials?.refreshExpiry)
                events = Notifier.loadEvents()
            }
        } catch {
            inboxError = message(error)
            handle(error, quiet: true)
        }
    }

    func foreground() async {
        guard phase == .signedIn else { return }
        if let client {
            await client.refreshIfStale()
            if let c = await client.credentials { credentials = c }
        }
        if let last = lastRefresh, Date.now.timeIntervalSince(last) < 60 { return }
        await refreshInbox()
    }

    #if DEBUG
    func startForTesting(_ b: any MarkerBackend, credentials c: Credentials?) async {
        client = nil
        backend = b
        isDemo = true // skips the disk cache and notifications
        credentials = c
        phase = .signedIn
        await loadAll()
    }

    func testRefresh() async {
        guard let client else { show("No live session", error: true); return }
        do {
            let c = try await client.doRefresh()
            credentials = c
            show("Refresh OK · token renewed")
        } catch {
            show("Refresh failed: \(message(error))", error: true)
        }
    }
    #endif

    func rescheduleReminders() async {
        guard !isDemo, phase == .signedIn else { return }
        await Notifier.reschedule(inbox: patchedMine, lookup: lookup, prefs: prefs, expiry: credentials?.refreshExpiry)
    }

    func signOut() async {
        await backend.signOut()
        await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        await reset(reason: nil)
    }

    private func reset(reason: String?) async {
        Keychain.deleteCredentials()
        if !isDemo {
            await Notifier.clearAll()
            DiskCache.clearAll()
        }
        client = nil
        backend = SignedOutBackend()
        isDemo = false
        credentials = nil
        unitRoles = []; unit = nil; students = []; projects = [:]; taskDefsByID = [:]
        inbox = []; mineInbox = []; events = []; patches = [:]; prerequisites = []
        scope = .mine; statusFilter = nil; search = ""; waitingOnly = false
        signOutReason = reason
        phase = .signedOut
    }

    // MARK: errors and toasts

    func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func handle(_ error: Error, quiet: Bool = false) {
        if let e = error as? APIError, e == .sessionExpired || e == .notSignedIn, phase == .signedIn, !isDemo {
            Task { await reset(reason: APIError.sessionExpired.errorDescription) }
            return
        }
        if !quiet { show(message(error), error: true) }
    }

    func show(_ text: String, error: Bool = false) {
        let t = Toast(text: text, isError: error)
        toast = t
        Task {
            try? await Task.sleep(for: .seconds(error ? 3.5 : 2))
            if toast == t { toast = nil }
        }
    }

    // MARK: writes

    @discardableResult
    func setStatus(_ t: TaskSummary, to status: TaskStatus, grade: Int?, qualityPts: Int) async -> Bool {
        let key = t.key
        let previous = patches[key]
        patch(key) { $0.status = status }
        do {
            try await backend.setStatus(key, trigger: status, grade: grade, qualityPts: qualityPts)
            haptic += 1
            show("Status sent · \(status.label)")
            await rescheduleReminders()
            return true
        } catch {
            patches[key] = previous
            show("\(status.label) not set. \(message(error))", error: true)
            handle(error, quiet: true)
            return false
        }
    }

    func togglePin(_ t: TaskSummary) async {
        let key = t.key
        let previous = patches[key]
        let pin = !t.pinned
        patch(key) { $0.pinned = pin }
        do {
            try await backend.setPinned(taskID: t.id, pinned: pin)
            show(pin ? "Pinned" : "Unpinned")
        } catch {
            patches[key] = previous
            show(message(error), error: true)
        }
    }

    func markRead(_ key: TaskKey) {
        patch(key) { $0.newComments = 0 }
    }

    func extensionDecided(_ key: TaskKey) {
        patch(key) { $0.hasExtensions = false }
    }

    // MARK: notifications feed

    func markSeen(_ id: String) {
        guard let i = events.firstIndex(where: { $0.id == id }), !events[i].seen else { return }
        events[i].seen = true
        if !isDemo { Notifier.saveEvents(events) }
    }

    func markAllSeen() {
        for i in events.indices { events[i].seen = true }
        if !isDemo { Notifier.saveEvents(events) }
    }

    func summary(for key: TaskKey) async -> TaskSummary? {
        if let t = inbox.first(where: { $0.key == key }) ?? mineInbox.first(where: { $0.key == key }) {
            return applying(t, fetchedAt: inboxFetchedAt)
        }
        guard let p = try? await backend.project(key.projectID),
              let pt = p.tasks.first(where: { $0.taskDefinitionId == key.taskDefID }) else { return nil }
        return TaskSummary(projectID: p.id, task: pt)
    }
}

enum DemoFeed {
    static func events(now: Date) -> [AlertEvent] {
        func k(_ sid: Int, _ td: Int) -> TaskKey { TaskKey(projectID: 500 + sid, taskDefID: td) }
        func h(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        return [
            AlertEvent(id: "e1", kind: .newWork, title: "Priya Raman · 3.2 · (W) Dynamic programming", body: "Ready for feedback.", date: h(2), key: k(1, 5), openComments: false, seen: false),
            AlertEvent(id: "e2", kind: .comment, title: "Tom Okafor · 3.1 · (W) Greedy exchange argument", body: "1 new comment.", date: h(3), key: k(2, 4), openComments: true, seen: false),
            AlertEvent(id: "e3", kind: .comment, title: "Daniel Kowalski · 3.2 · (W) Dynamic programming", body: "1 new comment.", date: h(8), key: k(4, 5), openComments: true, seen: false),
            AlertEvent(id: "e4", kind: .resubmission, title: "Daniel Kowalski · 2.2 · (W) Master theorem", body: "Resubmitted. Ready for feedback.", date: h(26), key: k(4, 3), openComments: false, seen: true),
            AlertEvent(id: "e5", kind: .comment, title: "Aisha Rahman · 3.1 · (W) Greedy exchange argument", body: "2 new comments.", date: h(27), key: k(5, 4), openComments: true, seen: true),
            AlertEvent(id: "e6", kind: .extensionRequest, title: "Lucas Ferreira · 2.1 · (W) Divide and conquer", body: "Grant or deny it in the thread.", date: h(51), key: k(6, 2), openComments: true, seen: true),
        ]
    }
}
