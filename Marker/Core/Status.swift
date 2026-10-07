import SwiftUI

// Doubtfire's STATUS_KEYS plus the older do_not_resubmit
enum TaskStatus: String, CaseIterable, Codable, Sendable, Identifiable {
    case notStarted = "not_started"
    case workingOnIt = "working_on_it"
    case needHelp = "need_help"
    case readyForFeedback = "ready_for_feedback"
    case discuss
    case demonstrate
    case fixAndResubmit = "fix_and_resubmit"
    case feedbackExceeded = "feedback_exceeded"
    case redo
    case attentionRequired = "attention_required"
    case complete
    case fail
    case timeExceeded = "time_exceeded"
    case doNotResubmit = "do_not_resubmit"
    case assessInPortfolio = "assess_in_portfolio"

    var id: String { rawValue }

    init(key: String?) { self = TaskStatus(rawValue: key ?? "") ?? .notStarted }

    static let triggers: [TaskStatus] = [.complete, .fixAndResubmit, .redo, .discuss, .attentionRequired, .demonstrate]
    static let more: [TaskStatus] = [.feedbackExceeded, .fail, .timeExceeded]

    var label: String {
        switch self {
        case .notStarted: "Not started"
        case .workingOnIt: "Working on it"
        case .needHelp: "Need help"
        case .readyForFeedback: "Ready for feedback"
        case .discuss: "Discuss"
        case .demonstrate: "Demonstrate"
        case .fixAndResubmit: "Resubmit"
        case .feedbackExceeded: "Feedback exceeded"
        case .redo: "Redo"
        case .attentionRequired: "Attention required"
        case .complete: "Complete"
        case .fail: "Fail"
        case .timeExceeded: "Time exceeded"
        case .doNotResubmit: "Do not resubmit"
        case .assessInPortfolio: "Assess in portfolio"
        }
    }

    var short: String {
        self == .attentionRequired ? "Attention" : label
    }

    var color: Color {
        switch self {
        case .notStarted: Color(light: 0x6b6b6b, dark: 0xa0a0a5)
        case .workingOnIt: Color(light: 0x8a5400, dark: 0xe3a548)
        case .needHelp: Color(light: 0x5b4a86, dark: 0xbcaaea)
        case .readyForFeedback: Color(light: 0x0064b4, dark: 0x62b2f6)
        case .discuss: Color(light: 0x146a86, dark: 0x5fc6e8)
        case .demonstrate: Color(light: 0x2b5f8f, dark: 0x90bbea)
        case .fixAndResubmit: Color(light: 0xb4530a, dark: 0xf2a263)
        case .feedbackExceeded: Color(light: 0x9c3d29, dark: 0xf3907a)
        case .redo: Color(light: 0xb02a37, dark: 0xf27d87)
        case .attentionRequired: Color(light: 0xa8431a, dark: 0xf69c72)
        case .complete: Color(light: 0x2f7a2f, dark: 0x7fd07f)
        case .fail: Color(light: 0x8b1e2d, dark: 0xea7682)
        case .timeExceeded: Color(light: 0x7a3b3b, dark: 0xd6a0a0)
        case .doNotResubmit, .assessInPortfolio: Color(light: 0x3a3a3a, dark: 0xcfcfd3)
        }
    }

    var isSubmitted: Bool {
        ![.notStarted, .workingOnIt, .needHelp].contains(self)
    }
}

enum WaitTier: Int, Comparable, Sendable {
    case none = 0, first, second, third, overdue

    static func < (a: WaitTier, b: WaitTier) -> Bool { a.rawValue < b.rawValue }

    static let reminders: [WaitTier] = [.first, .second, .third, .overdue]

    // position in Prefs.bumpAfter
    var index: Int { rawValue - 1 }

    static func of(status: TaskStatus, submitted: Date?, now: Date = .now, after: [Int] = Prefs.defaultBumpAfter) -> WaitTier {
        guard status == .readyForFeedback, let submitted else { return .none }
        let days = now.timeIntervalSince(submitted) / 86_400
        return reminders.last { days >= Double(after[$0.index]) } ?? .none
    }

    static func days(since submitted: Date?, now: Date = .now) -> Int {
        guard let submitted else { return 0 }
        return max(0, Int(now.timeIntervalSince(submitted) / 86_400))
    }

    var settingLabel: String {
        switch self {
        case .none: ""
        case .first: "First reminder"
        case .second: "Second reminder"
        case .third: "Third reminder"
        case .overdue: "Overdue"
        }
    }

    func tag(days: Int) -> String {
        switch self {
        case .none: ""
        case .overdue: "Overdue · \(Fmt.days(days)), no feedback"
        default: "Waiting \(Fmt.days(days))"
        }
    }

    var color: Color {
        switch self {
        case .none, .first: Palette.fg2
        case .second: TaskStatus.workingOnIt.color
        case .third: TaskStatus.fixAndResubmit.color
        case .overdue: TaskStatus.redo.color
        }
    }
}
