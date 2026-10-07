import Foundation

// times are minutes after midnight, weekdays are Calendar numbers (1 is Sunday)
struct Prefs: Codable, Equatable, Sendable {
    var notifyWork = true
    var notifyComments = true
    var notifyExtensions = true
    var notifyExpiry = true
    var expiryWarnHours = 12
    var dailySummary = true
    var summaryAt = 8 * 60
    var summaryDays: [Int] = [2, 3, 4, 5, 6]
    var quietHours = true
    var quietFrom = 22 * 60
    var quietUntil = 8 * 60
    // days before each reminder: three nudges, then overdue
    var bumpAfter: [Int] = Prefs.defaultBumpAfter
    var bumpEnabled: [Bool] = [true, true, true, true]
    // nil means at the submission time
    var bumpAt: Int?
    var capitaliseComments = false
    var hideComplete = true
    var hideMoodle = true
    var oldestFirst = true
    var theme: ThemeChoice = .system

    static let defaultBumpAfter = [2, 3, 4, 7]
    static let expiryChoices = [1, 3, 6, 12, 24, 48]
    static let maxBumpDays = 28
    private static let key = "prefs.v1"

    init() {}

    // older saved settings can be missing keys
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Prefs()
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? fallback }
        notifyWork = v(.notifyWork, d.notifyWork)
        notifyComments = v(.notifyComments, d.notifyComments)
        notifyExtensions = v(.notifyExtensions, d.notifyExtensions)
        notifyExpiry = v(.notifyExpiry, d.notifyExpiry)
        expiryWarnHours = v(.expiryWarnHours, d.expiryWarnHours)
        dailySummary = v(.dailySummary, d.dailySummary)
        summaryAt = v(.summaryAt, d.summaryAt)
        summaryDays = v(.summaryDays, d.summaryDays)
        quietHours = v(.quietHours, d.quietHours)
        quietFrom = v(.quietFrom, d.quietFrom)
        quietUntil = v(.quietUntil, d.quietUntil)
        bumpAfter = v(.bumpAfter, d.bumpAfter)
        if bumpAfter.count != 4 { bumpAfter = d.bumpAfter }
        if let on = try? c.decodeIfPresent([Bool].self, forKey: .bumpEnabled), on.count == 4 {
            bumpEnabled = on
        } else if let old = try? decoder.container(keyedBy: OldKeys.self).decodeIfPresent([Int].self, forKey: .bumpDays) {
            // older builds saved the enabled reminders as day counts
            bumpEnabled = Prefs.defaultBumpAfter.map(old.contains)
        }
        bumpAt = v(.bumpAt, d.bumpAt)
        capitaliseComments = v(.capitaliseComments, d.capitaliseComments)
        hideComplete = v(.hideComplete, d.hideComplete)
        hideMoodle = v(.hideMoodle, d.hideMoodle)
        oldestFirst = v(.oldestFirst, d.oldestFirst)
        theme = v(.theme, d.theme)
    }

    private enum CodingKeys: String, CodingKey {
        case notifyWork, notifyComments, notifyExtensions, notifyExpiry, expiryWarnHours
        case dailySummary, summaryAt, summaryDays, quietHours, quietFrom, quietUntil
        case bumpAfter, bumpEnabled, bumpAt, capitaliseComments
        case hideComplete, hideMoodle, oldestFirst, theme
    }

    private enum OldKeys: String, CodingKey { case bumpDays }

    static func load() -> Prefs {
        guard let data = UserDefaults.standard.data(forKey: key),
              let p = try? JSONDecoder().decode(Prefs.self, from: data) else { return Prefs() }
        return p
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    func bumpOn(_ tier: WaitTier) -> Bool { tier != .none && bumpEnabled[tier.index] }

    mutating func setBump(_ tier: WaitTier, _ on: Bool) {
        guard tier != .none else { return }
        bumpEnabled[tier.index] = on
    }

    func days(_ tier: WaitTier) -> Int { tier == .none ? 0 : bumpAfter[tier.index] }

    // pushes the other reminders along to keep them in order
    mutating func setDays(_ tier: WaitTier, _ days: Int) {
        guard tier != .none else { return }
        let i = tier.index, n = bumpAfter.count
        bumpAfter[i] = min(max(days, i + 1), Self.maxBumpDays - (n - 1 - i))
        for j in (i + 1)..<n where bumpAfter[j] <= bumpAfter[j - 1] { bumpAfter[j] = bumpAfter[j - 1] + 1 }
        for j in stride(from: i - 1, through: 0, by: -1) where bumpAfter[j] >= bumpAfter[j + 1] { bumpAfter[j] = bumpAfter[j + 1] - 1 }
    }

    // can wrap past midnight, e.g. 22:00 to 08:00
    func isQuiet(_ date: Date, calendar cal: Calendar = .current) -> Bool {
        guard quietHours, quietFrom != quietUntil else { return false }
        let c = cal.dateComponents([.hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return quietFrom < quietUntil ? (m >= quietFrom && m < quietUntil) : (m >= quietFrom || m < quietUntil)
    }

    func outOfQuiet(_ date: Date, calendar cal: Calendar = .current) -> Date {
        guard isQuiet(date, calendar: cal) else { return date }
        return cal.nextDate(after: date, matching: Self.components(quietUntil), matchingPolicy: .nextTime) ?? date
    }

    static func components(_ minutes: Int) -> DateComponents {
        DateComponents(hour: minutes / 60, minute: minutes % 60)
    }

    static func clock(_ minutes: Int) -> String {
        let d = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        return d.formatted(date: .omitted, time: .shortened)
    }
}

enum DiskCache {
    private static func folder(support: Bool) -> URL {
        let base = FileManager.default.urls(for: support ? .applicationSupportDirectory : .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Marker", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func url(_ name: String, support: Bool) -> URL {
        folder(support: support).appendingPathComponent(name)
    }

    // snake for API models so the keys match Formatif's JSON
    static func write<T: Encodable>(_ value: T, _ name: String, support: Bool = false, snake: Bool = false) {
        let enc = snake ? JSON.encoder() : JSONEncoder()
        guard let data = try? enc.encode(value) else { return }
        try? data.write(to: url(name, support: support), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func read<T: Decodable>(_ type: T.Type, _ name: String, support: Bool = false, snake: Bool = false) -> T? {
        guard let data = try? Data(contentsOf: url(name, support: support)) else { return nil }
        let dec = snake ? JSON.decoder() : JSONDecoder()
        return try? dec.decode(T.self, from: data)
    }

    static func clearAll() {
        for support in [true, false] {
            try? FileManager.default.removeItem(at: folder(support: support))
        }
    }
}
