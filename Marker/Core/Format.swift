import Foundation

enum Fmt {
    static let sydney = TimeZone(identifier: "Australia/Sydney") ?? .current

    static func days(_ n: Int) -> String {
        if n > 0, n % 7 == 0 { return n == 7 ? "1 week" : "\(n / 7) weeks" }
        return n == 1 ? "1 day" : "\(n) days"
    }

    // "2026-09-14T07:24:04.146Z" or "2026-10-02"
    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let d = try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return d }
        if let d = try? Date(s, strategy: Date.ISO8601FormatStyle()) { return d }
        if let d = try? Date(s, strategy: Date.ISO8601FormatStyle(timeZone: sydney).year().month().day()) { return d }
        return nil
    }

    // "now", "5m", "2h", "Yesterday", "3d", "12 Sep"
    static func relative(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "" }
        let secs = now.timeIntervalSince(date)
        if secs < 60 { return "now" }
        if secs < 3600 { return "\(Int(secs / 60))m" }
        if Calendar.current.isDateInToday(date) || secs < 6 * 3600 { return "\(Int(secs / 3600))h" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let days = Int(secs / 86_400)
        if days < 7 { return "\(max(days, 2))d" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func long(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    static func day(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func thread(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "" }
        if Calendar.current.isDateInToday(date) { return date.formatted(.dateTime.hour().minute()) }
        if now.timeIntervalSince(date) < 6 * 86_400 {
            return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func dayGroup(_ date: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if now.timeIntervalSince(date) < 6 * 86_400 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
