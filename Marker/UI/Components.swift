import SwiftUI
import UIKit

struct StatusPill: View {
    let status: TaskStatus
    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .frame(minHeight: 22)
            .background(status.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("Status \(status.label)")
    }
}

struct StatusDot: View {
    let status: TaskStatus
    var size: CGFloat = 10
    var body: some View {
        Circle().fill(status.color).frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct UnreadDot: View {
    let count: Int
    var body: some View {
        Circle().fill(Palette.acc).frame(width: 8, height: 8)
            .accessibilityLabel("\(count) unread comment\(count == 1 ? "" : "s")")
    }
}

struct WaitTag: View {
    let tier: WaitTier
    let days: Int
    var body: some View {
        if tier != .none {
            HStack(spacing: 4) {
                Image(systemName: tier == .overdue ? "exclamationmark.circle.fill" : "clock")
                    .imageScale(.small)
                Text(tier.tag(days: days))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(tier.color)
            .accessibilityElement(children: .combine)
        }
    }
}

struct Chip<Label: View>: View {
    var on: Bool
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { label() }
                .chipStyle(on: on)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct MenuChip<Content: View>: View {
    var title: String
    var on: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu(content: content) {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .chipStyle(on: on)
        }
    }
}

private extension View {
    func chipStyle(on: Bool) -> some View {
        font(.footnote.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .foregroundStyle(on ? Palette.acc : Palette.fg)
            .background(on ? Palette.tint : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Palette.acc : Palette.hair, lineWidth: 1))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.sectionLabel)
            .kerning(0.3)
            .foregroundStyle(Palette.fg2)
    }
}

struct EmptyState: View {
    let title: String
    var detail: String?
    var action: String?
    var perform: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(Palette.fg2).multilineTextAlignment(.center)
            }
            if let action, let perform {
                Button(action, action: perform).font(.headline).padding(.top, 4).frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .padding(.horizontal, 24)
    }
}

struct ToastView: View {
    let toast: Toast
    var body: some View {
        Text(toast.text)
            .font(.footnote.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(toast.isError ? .white : Palette.bg)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(toast.isError ? Palette.err : Palette.fg, in: Capsule())
            .padding(.horizontal, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

struct UnitMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(model.unitRoles) { role in
                Button {
                    Task { await model.selectUnit(role.unit.id) }
                } label: {
                    if role.unit.id == model.unitID {
                        Label(model.unitLabel(role.unit), systemImage: "checkmark")
                    } else {
                        Text(model.unitLabel(role.unit))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(model.currentRole.map { model.unitLabel($0.unit) } ?? "Unit")
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                if model.isDemo {
                    Text("DEMO").font(.caption2.weight(.bold)).kerning(0.6).foregroundStyle(Palette.acc)
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.fg)
        }
        .accessibilityLabel("Unit")
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

enum TempFiles {
    static func write(_ data: Data, name: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let url = dir.appendingPathComponent(safe.isEmpty ? "file" : safe)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

extension View {
    func markerRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparatorTint(Palette.hair)
            .listRowBackground(Palette.bg)
    }
}
