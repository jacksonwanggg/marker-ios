import SwiftUI

struct InboxView: View {
    @Environment(AppModel.self) private var model
    @State private var confirm: ConfirmRequest?

    var body: some View {
        @Bindable var model = model
        let rows = model.inboxRows
        List {
            InboxHeader(rows: rows)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Palette.bg)

            if model.inboxLoading, model.inbox.isEmpty {
                ForEach(0..<6, id: \.self) { _ in PlaceholderRow().markerRow() }
            } else if let err = model.inboxError, model.inbox.isEmpty {
                EmptyState(title: "Couldn't load the inbox.", detail: err, action: "Try again") {
                    Task { await model.refreshInbox() }
                }
                .listRowSeparator(.hidden)
            } else if rows.isEmpty {
                emptyState.listRowSeparator(.hidden)
            } else {
                ForEach(rows) { t in
                    InboxRow(task: t)
                        .accessibilityAddTraits(.isButton)
                        .background(NavigationLink("", value: TaskRoute(key: t.key, context: rows, fetchedAt: model.inboxFetchedAt)).opacity(0))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Complete") { confirm = ConfirmRequest(task: t, target: .complete) }
                                .tint(TaskStatus.complete.color)
                            Button(t.pinned ? "Unpin" : "Pin") { Task { await model.togglePin(t) } }
                                .tint(Palette.acc)
                        }
                        .markerRow()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .navigationTitle("Inbox")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { UnitMenu() }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.refreshInbox() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
                .disabled(model.inboxLoading)
            }
        }
        .searchable(text: $model.search, prompt: "Name, zID or task")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .refreshable { await model.refreshInbox() }
        .onChange(of: model.scope) { _, _ in Task { await model.refreshInbox() } }
        .sheet(item: $confirm) { ConfirmStatusSheet(request: $0) }
    }

    @ViewBuilder private var emptyState: some View {
        let q = model.search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            EmptyState(title: "No tasks match \u{201C}\(q)\u{201D}.", action: "Clear search") { model.search = "" }
        } else if model.statusFilter != nil || model.waitingOnly {
            EmptyState(title: "Nothing matches these filters.", action: "Clear filters") {
                model.statusFilter = nil
                model.waitingOnly = false
            }
        } else if model.scope != .all {
            let detail = model.scope == .mine ? "Your students are all caught up." : "\(model.scopeLabel) is all caught up."
            EmptyState(title: "Nothing to mark.", detail: detail, action: "Show all students") { model.scope = .all }
        } else {
            EmptyState(title: "Nothing to mark.")
        }
    }
}

private struct InboxHeader: View {
    @Environment(AppModel.self) private var model
    let rows: [TaskSummary]

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if model.inboxLoading { ProgressView().controlSize(.mini) }
                Text(summary)
            }
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(Palette.fg2)
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    MenuChip(title: model.scopeLabel, on: model.scope != .mine) {
                        // units can have 50+ tutorials, so the rest go in a submenu
                        scopeButton("My students", .mine)
                        scopeButton("All students", .all)
                        let mine = tutorials.filter { model.myTutorialIDs.contains($0.id) }
                        let others = tutorials.filter { !model.myTutorialIDs.contains($0.id) }
                        if !mine.isEmpty {
                            Section("Your tutorials") {
                                ForEach(mine) { t in scopeButton("★ Tutorial \(t.abbreviation)", .tutorial(t.id)) }
                            }
                        }
                        if !others.isEmpty {
                            Menu("Other tutorials") {
                                ForEach(others) { t in scopeButton("Tutorial \(t.abbreviation)", .tutorial(t.id)) }
                            }
                        }
                    }
                    Chip(on: model.prefs.hideComplete, action: { model.prefs.hideComplete.toggle() }) { Text("Hide complete") }
                    Chip(on: model.prefs.hideMoodle, action: { model.prefs.hideMoodle.toggle() }) { Text("Hide Moodle") }
                    Chip(on: model.waitingOnly, action: { model.waitingOnly.toggle() }) {
                        Image(systemName: "clock").imageScale(.small)
                        Text("Waiting \(model.prefs.bumpAfter[0])d+")
                    }
                    MenuChip(title: model.statusFilter?.label ?? "Any status", on: model.statusFilter != nil) {
                        Picker("Status", selection: $model.statusFilter) {
                            Text("Any status").tag(TaskStatus?.none)
                            ForEach([TaskStatus.readyForFeedback, .needHelp, .discuss, .workingOnIt,
                                     .fixAndResubmit, .demonstrate, .complete]) { s in
                                Text(s.label).tag(TaskStatus?.some(s))
                            }
                        }
                    }
                    MenuChip(title: model.prefs.oldestFirst ? "Oldest first" : "Newest first", on: false) {
                        Picker("Order", selection: $model.prefs.oldestFirst) {
                            Text("Oldest first").tag(true)
                            Text("Newest first").tag(false)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func scopeButton(_ title: String, _ scope: AppModel.Scope) -> some View {
        Button {
            model.scope = scope
        } label: {
            if model.scope == scope { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    private var summary: String {
        if model.inboxLoading { return "Loading \(model.scopeLabel.lowercased())…" }
        if rows.isEmpty {
            return model.search.trimmingCharacters(in: .whitespaces).isEmpty ? "Nothing in scope" : "No matches"
        }
        let awaiting = rows.filter { $0.status == .readyForFeedback }.count
        let unread = rows.filter { $0.numNewComments > 0 }.count
        return "\(rows.count) task\(rows.count == 1 ? "" : "s") · \(awaiting) awaiting feedback · \(unread) unread"
    }

    private var tutorials: [Tutorial] {
        (model.unit?.tutorials ?? []).sorted { $0.abbreviation < $1.abbreviation }
    }
}

struct InboxRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskSummary

    var body: some View {
        let tier = model.tier(task)
        let flags = Self.flags(task)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    if task.pinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Palette.fg2).accessibilityLabel("Pinned")
                    }
                    Text(model.studentName(task.projectId)).font(.headline).lineLimit(1)
                }
                Text(model.taskLine(task.taskDefinitionId)).font(.subheadline).foregroundStyle(Palette.fg2).lineLimit(1)
                if !flags.isEmpty {
                    Text(flags).font(.caption).monospacedDigit().foregroundStyle(Palette.fg2).padding(.top, 1)
                }
                if tier != .none {
                    WaitTag(tier: tier, days: WaitTier.days(since: task.submitted)).padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                StatusPill(status: task.status)
                HStack(spacing: 6) {
                    if task.numNewComments > 0 { UnreadDot(count: task.numNewComments) }
                    Text(Fmt.relative(task.submitted)).font(.footnote).monospacedDigit().foregroundStyle(Palette.fg2)
                }
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    static func flags(_ t: TaskSummary) -> String {
        var out: [String] = []
        if t.status == .readyForFeedback, let n = t.timesAssessed, n > 0 { out.append("Attempt \(n + 1)") }
        if t.hasExtensions { out.append("Extension requested") }
        if t.similarityFlag { out.append("Similarity flagged") }
        return out.joined(separator: " · ")
    }
}

struct PlaceholderRow: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Student name here").font(.headline)
                Text("3.2 · (W) Task name").font(.subheadline)
            }
            Spacer()
            Text("Ready for feedback").font(.caption)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}
