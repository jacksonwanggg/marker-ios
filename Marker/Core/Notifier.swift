import BackgroundTasks
import Foundation
import UserNotifications

/// Names for notification text, cached so background refresh needs no extra API calls.
struct Lookup: Codable, Sendable {
    var unitCode: String
    var students: [Int: String]
    var taskDefs: [Int: String]

    func title(_ t: TaskSummary) -> String {
        let name = students[t.projectId] ?? "A student"
        let td = taskDefs[t.taskDefinitionId] ?? "a task"
        return "\(name) · \(td)"
    }
}

struct SnapItem: Codable, Sendable, Equatable {
    var status: String
    var submission: String?
    var newComments: Int
    var ext: Bool
}

struct AlertEvent: Codable, Sendable, Identifiable, Hashable {
    enum Kind: String, Codable, Sendable {
        case newWork, resubmission, comment, extensionRequest, signIn
    }

    var id: String
    var kind: Kind
    var title: String
    var body: String
    var date: Date
    var key: TaskKey?
    var openComments: Bool
    var seen: Bool

    var kindLabel: String {
        switch kind {
        case .newWork: "New submission"
        case .resubmission: "Resubmission"
        case .comment: "New comment"
        case .extensionRequest: "Extension request"
        case .signIn: "Sign-in"
        }
    }
}

struct DeepLink: Equatable, Sendable {
    let key: TaskKey
    let comments: Bool
}

/// Formatif has no push, so we diff inbox snapshots and schedule our own local notifications.
enum Notifier {
    static let refreshTaskID = "com.jacksonwang.marker.refresh"
    static let category = "TASK"
    static let laterAction = "LATER"

    static func snapshot(_ tasks: [TaskSummary]) -> [Int: SnapItem] {
        let items = tasks.map { t in
            (t.id, SnapItem(status: t.statusKey, submission: t.submissionDate, newComments: t.numNewComments, ext: t.hasExtensions))
        }
        return Dictionary(items, uniquingKeysWith: { first, _ in first })
    }

    static func diff(old: [Int: SnapItem]?, new: [TaskSummary], lookup: Lookup, now: Date = .now) -> [AlertEvent] {
        guard let old else { return [] }
        let stamp = Int(now.timeIntervalSince1970)
        var out: [AlertEvent] = []
        for t in new {
            let o = old[t.id]
            let title = lookup.title(t)
            if t.status == .readyForFeedback {
                let resub = (t.timesAssessed ?? 0) > 0
                if o?.status != t.statusKey {
                    out.append(AlertEvent(id: "work-\(t.id)-\(stamp)", kind: resub ? .resubmission : .newWork, title: title,
                                          body: resub ? "Resubmitted. Ready for feedback." : "Ready for feedback.",
                                          date: t.submitted ?? now, key: t.key, openComments: false, seen: false))
                } else if o?.submission != t.submissionDate {
                    out.append(AlertEvent(id: "resub-\(t.id)-\(stamp)", kind: .resubmission, title: title,
                                          body: "A new attempt is ready for feedback.", date: t.submitted ?? now,
                                          key: t.key, openComments: false, seen: false))
                }
            }
            let before = o?.newComments ?? 0
            if t.numNewComments > before {
                let n = t.numNewComments - before
                out.append(AlertEvent(id: "comment-\(t.id)-\(stamp)", kind: .comment, title: title,
                                      body: n == 1 ? "1 new comment." : "\(n) new comments.", date: now,
                                      key: t.key, openComments: true, seen: false))
            }
            if t.hasExtensions, !(o?.ext ?? false) {
                out.append(AlertEvent(id: "ext-\(t.id)-\(stamp)", kind: .extensionRequest, title: title,
                                      body: "Grant or deny it in the thread.", date: now, key: t.key, openComments: true, seen: false))
            }
        }
        return out
    }

    static func badgeCount(_ inbox: [TaskSummary]) -> Int {
        inbox.filter { $0.status == .readyForFeedback || $0.numNewComments > 0 }.count
    }

    static func loadEvents() -> [AlertEvent] { DiskCache.read([AlertEvent].self, "events.json", support: true) ?? [] }
    static func saveEvents(_ events: [AlertEvent]) { DiskCache.write(Array(events.prefix(200)), "events.json", support: true) }

    @discardableResult
    static func process(unitID: Int, inbox: [TaskSummary], lookup: Lookup, prefs: Prefs, expiry: Date?) async -> [AlertEvent] {
        let snapName = "snapshot-\(unitID).json"
        let old = DiskCache.read([Int: SnapItem].self, snapName, support: true)
        let events = diff(old: old, new: inbox, lookup: lookup)
        DiskCache.write(snapshot(inbox), snapName, support: true)
        if !events.isEmpty {
            saveEvents(events.sorted { $0.date > $1.date } + loadEvents())
            for e in events where wants(e, prefs) { await post(e, prefs: prefs) }
        }
        await reschedule(inbox: inbox, lookup: lookup, prefs: prefs, expiry: expiry)
        return events
    }

    static func wants(_ e: AlertEvent, _ p: Prefs) -> Bool {
        switch e.kind {
        case .newWork, .resubmission: p.notifyWork
        case .comment: p.notifyComments
        case .extensionRequest: p.notifyExtensions
        case .signIn: p.notifyExpiry
        }
    }

    static func post(_ e: AlertEvent, prefs: Prefs) async {
        let content = UNMutableNotificationContent()
        content.title = e.kindLabel
        content.body = "\(e.title). \(e.body)"
        apply(content, key: e.key, comments: e.openComments, prefs: prefs, at: .now)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: e.id, content: content, trigger: nil))
    }

    private static func apply(_ content: UNMutableNotificationContent, key: TaskKey?, comments: Bool, prefs: Prefs, at date: Date) {
        content.categoryIdentifier = category
        if let key {
            content.threadIdentifier = "task-\(key.projectID)-\(key.taskDefID)"
            content.userInfo = ["projectID": key.projectID, "taskDefID": key.taskDefID, "comments": comments]
        }
        if prefs.isQuiet(date) {
            content.interruptionLevel = .passive
        } else {
            content.sound = .default
        }
    }

    static func reschedule(inbox: [TaskSummary], lookup: Lookup, prefs: Prefs, expiry: Date?) async {
        let center = UNUserNotificationCenter.current()
        try? await center.setBadgeCount(badgeCount(inbox))
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix("bump-") || $0 == "daily-summary" || $0 == "expiry" })
        for r in bumpRequests(inbox: inbox, lookup: lookup, prefs: prefs) { try? await center.add(r) }
        if prefs.dailySummary, let r = summaryRequest(inbox: inbox, lookup: lookup, prefs: prefs) { try? await center.add(r) }
        if prefs.notifyExpiry, let expiry, let r = expiryRequest(expiry, hoursBefore: prefs.expiryWarnHours) { try? await center.add(r) }
    }

    /// Timed from the submission, so reminders fire even if background refresh never runs.
    static func bumpRequests(inbox: [TaskSummary], lookup: Lookup, prefs: Prefs, now: Date = .now,
                             calendar cal: Calendar = .current) -> [UNNotificationRequest] {
        var items: [(Date, UNNotificationRequest)] = []
        for t in inbox where t.status == .readyForFeedback {
            guard let submitted = t.submitted else { continue }
            for tier in WaitTier.reminders where prefs.bumpOn(tier) {
                let days = prefs.days(tier)
                var fire = submitted.addingTimeInterval(Double(days) * 86_400)
                if let at = prefs.bumpAt {
                    // the first chosen time of day at or after the mark
                    fire = cal.nextDate(after: fire.addingTimeInterval(-1), matching: Prefs.components(at), matchingPolicy: .nextTime) ?? fire
                }
                fire = prefs.outOfQuiet(fire, calendar: cal)
                guard fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = tier == .overdue ? "Overdue · \(Fmt.days(days)), no feedback" : "Waiting \(Fmt.days(days))"
                content.body = "\(lookup.title(t)) has waited since \(Fmt.long(submitted)) without feedback."
                apply(content, key: t.key, comments: false, prefs: prefs, at: fire)
                content.threadIdentifier = "bumps"
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, fire.timeIntervalSince(now)), repeats: false)
                items.append((fire, UNNotificationRequest(identifier: "bump-\(t.id)-\(days)", content: content, trigger: trigger)))
            }
        }
        // iOS allows 64 pending, so keep the soonest. Each refresh tops them up.
        return items.sorted { $0.0 < $1.0 }.prefix(48).map(\.1)
    }

    static func nextSummary(after now: Date, prefs: Prefs, calendar cal: Calendar = .current) -> Date? {
        let days = Set(prefs.summaryDays)
        guard !days.isEmpty else { return nil }
        var next = now
        for _ in 0..<8 {
            guard let d = cal.nextDate(after: next, matching: Prefs.components(prefs.summaryAt), matchingPolicy: .nextTime) else { return nil }
            if days.contains(cal.component(.weekday, from: d)) { return d }
            next = d
        }
        return nil
    }

    static func summaryRequest(inbox: [TaskSummary], lookup: Lookup, prefs: Prefs, now: Date = .now) -> UNNotificationRequest? {
        let awaiting = inbox.filter { $0.status == .readyForFeedback }.count
        let unread = inbox.filter { $0.numNewComments > 0 }.count
        let ext = inbox.filter(\.hasExtensions).count
        guard awaiting + unread + ext > 0, let next = nextSummary(after: now, prefs: prefs) else { return nil }
        let threads = unread == 1 ? "1 thread has" : "\(unread) threads have"
        let requests = ext == 1 ? "1 extension request needs" : "\(ext) extension requests need"
        let hour = prefs.summaryAt / 60
        let content = UNMutableNotificationContent()
        content.title = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        content.body = "\(awaiting) waiting for feedback in \(lookup.unitCode). \(threads) unread comments and \(requests) a decision."
        content.categoryIdentifier = category
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: next)
        return UNNotificationRequest(identifier: "daily-summary", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }

    static func expiryRequest(_ expiry: Date, hoursBefore: Int = 12, now: Date = .now) -> UNNotificationRequest? {
        let fire = expiry.addingTimeInterval(-Double(hoursBefore) * 3600)
        guard fire > now else { return nil }
        let content = UNMutableNotificationContent()
        content.title = "Sign in again"
        content.body = "Your UNSW sign-in ends \(Fmt.long(expiry)). Sign in again to keep notifications coming."
        content.sound = .default
        return UNNotificationRequest(identifier: "expiry", content: content,
                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: fire.timeIntervalSince(now), repeats: false))
    }

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    static func registerCategories() {
        let later = UNNotificationAction(identifier: laterAction, title: "Mark as read later", options: [])
        let cat = UNNotificationCategory(identifier: category, actions: [later], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([cat])
    }

    static func clearAll() async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        try? await center.setBadgeCount(0)
    }

    static func scheduleAppRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    static func refreshInBackground() async {
        scheduleAppRefresh()
        guard let creds = Keychain.loadCredentials(),
              let unitID = UserDefaults.standard.object(forKey: AppModel.unitKey) as? Int,
              let lookup = DiskCache.read(Lookup.self, "lookup-\(unitID).json", support: true) else { return }
        let backend = LiveBackend(client: FormatifClient(credentials: creds))
        guard let inbox = try? await backend.inbox(unitID: unitID, myStudentsOnly: true) else { return }
        DiskCache.write(inbox, "inbox-mine-\(unitID).json", snake: true)
        await process(unitID: unitID, inbox: inbox, lookup: lookup, prefs: .load(), expiry: creds.refreshExpiry)
    }
}
