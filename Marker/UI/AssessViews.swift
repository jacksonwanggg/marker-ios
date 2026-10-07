import SwiftUI

struct ConfirmRequest: Identifiable {
    let id = UUID()
    let task: TaskSummary
    let target: TaskStatus
}

struct AssessBar: View {
    let current: TaskStatus
    let onPick: (TaskStatus) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TaskStatus.triggers) { s in
                Button {
                    onPick(s)
                } label: {
                    VStack(spacing: 6) {
                        StatusDot(status: s)
                        Text(s.short)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(Palette.fg)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(current == s ? Palette.fill : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set status to \(s.label)")
                .accessibilityAddTraits(current == s ? .isSelected : [])
            }
        }
        .padding(6)
    }
}

struct ConfirmStatusSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: ConfirmRequest
    /// Set when opened from a task, so a typed comment can be sent first.
    var detail: TaskDetailModel?
    var onSent: (() -> Void)?

    @State private var grade = 0
    @State private var quality = 0
    @State private var withComment = true

    private var td: TaskDefinition? { model.taskDef(request.task.taskDefinitionId) }
    private var graded: Bool { td?.isGraded ?? false }
    private var current: TaskStatus { model.applying(request.task, fetchedAt: .distantPast).status }
    private var draft: String? {
        guard let d = detail?.draft.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty else { return nil }
        return d
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Set status").font(.title2.bold())
                Text("\(model.studentName(request.task.projectId)) · \(model.taskLine(request.task.taskDefinitionId))")
                    .font(.subheadline)
                    .foregroundStyle(Palette.fg2)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                StatusPill(status: current)
                Image(systemName: "arrow.right").font(.footnote).foregroundStyle(Palette.fg2)
                StatusPill(status: request.target)
            }
            if graded {
                Picker("Grade", selection: $grade) {
                    ForEach(0..<4) { Text(Grade.letter($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                if let max = td?.maxQualityPts, max > 0 {
                    Stepper("Quality \(quality) of \(max)", value: $quality, in: 0...max)
                }
            }
            if let draft {
                Toggle(isOn: $withComment) {
                    Text("Send your comment too")
                    Text(draft).lineLimit(2)
                }
            }
            Text(draft != nil && withComment
                 ? "The comment goes first, then the status. If Formatif refuses the comment, the status isn't changed and the comment stays in the box."
                 : "The status goes to Formatif straight away. If Formatif refuses it, the status rolls back and you'll see why.")
                .font(.footnote)
                .foregroundStyle(Palette.fg2)
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 12))

                Button {
                    send()
                } label: {
                    Text(draft != nil && withComment ? "Send and set \(request.target.label)" : "Set \(request.target.label)")
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func send() {
        let task = request.task, target = request.target
        let g: Int? = graded ? grade : nil
        let q = graded ? quality : -1
        let done = onSent
        let detail = withComment && draft != nil ? self.detail : nil
        dismiss()
        Task {
            if let detail, !(await detail.sendDraft()) {
                model.show("The comment didn't send, so the status wasn't changed. \(detail.sendError ?? "")", error: true)
                return
            }
            if await model.setStatus(task, to: target, grade: g, qualityPts: q) { done?() }
        }
    }
}
