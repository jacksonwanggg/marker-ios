import SwiftUI

struct NotificationsView: View {
    @Environment(AppModel.self) private var model
    @Binding var path: NavigationPath
    let openInbox: () -> Void

    private var waiting: [TaskSummary] {
        model.patchedMine
            .filter { model.tier($0) != .none && !(model.taskDef($0.taskDefinitionId)?.isMoodle ?? false) }
            .sorted { ($0.submitted ?? .distantPast) < ($1.submitted ?? .distantPast) }
    }

    private var groups: [(String, [AlertEvent])] {
        let sorted = model.events.sorted { $0.date > $1.date }
        var out: [(String, [AlertEvent])] = []
        for e in sorted {
            let label = Fmt.dayGroup(e.date)
            if out.last?.0 == label { out[out.count - 1].1.append(e) } else { out.append((label, [e])) }
        }
        return out
    }

    var body: some View {
        let waitingList = waiting
        List {
            Text(model.unseenCount > 0 ? "\(model.unseenCount) new since you last looked" : "All caught up")
                .font(.footnote).monospacedDigit().foregroundStyle(Palette.fg2)
                .listRowSeparator(.hidden)
                .markerRow()

            SummaryCard(openInbox: openInbox)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Palette.bg)

            if !waitingList.isEmpty {
                Section {
                    ForEach(waitingList) { t in
                        Button {
                            path.append(TaskRoute(key: t.key, context: waitingList, fetchedAt: model.inboxFetchedAt))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.studentName(t.projectId)).font(.headline).foregroundStyle(Palette.fg).lineLimit(1)
                                Text(model.taskLine(t.taskDefinitionId)).font(.subheadline).foregroundStyle(Palette.fg2).lineLimit(1)
                                WaitTag(tier: model.tier(t), days: WaitTier.days(since: t.submitted))
                                    .padding(.top, 2)
                            }
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .markerRow()
                    }
                } header: {
                    SectionLabel(text: "Waiting for feedback")
                }
            }

            ForEach(groups, id: \.0) { day, items in
                Section {
                    ForEach(items) { e in
                        Button { open(e) } label: { EventRow(event: e) }
                            .buttonStyle(.plain)
                            .markerRow()
                    }
                } header: {
                    SectionLabel(text: day)
                }
            }

            if model.events.isEmpty {
                Text("No alerts yet. New submissions, comments and extension requests for your students show up here.")
                    .font(.subheadline).foregroundStyle(Palette.fg2)
                    .listRowSeparator(.hidden)
                    .markerRow()
            }

            Text("""
                Times are when things happened in Formatif. Alerts can come later, since iOS decides when Marker \
                checks in the background. Waiting reminders count from the submission time.
                """)
                .font(.footnote).foregroundStyle(Palette.fg2)
                .padding(.vertical, 12)
                .listRowSeparator(.hidden)
                .markerRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .navigationTitle("Notifications")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { UnitMenu() }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark all seen") { model.markAllSeen() }.disabled(model.unseenCount == 0)
            }
        }
        .refreshable { await model.refreshInbox() }
    }

    private func open(_ e: AlertEvent) {
        model.markSeen(e.id)
        if let key = e.key { path.append(TaskRoute(key: key, openComments: e.openComments)) } else { openInbox() }
    }
}

private struct EventRow: View {
    let event: AlertEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(event.seen ? Color.clear : Palette.acc).frame(width: 8, height: 8).padding(.top, 6)
                .accessibilityLabel(event.seen ? "" : "New")
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.kindLabel.uppercased()).font(.caption.weight(.bold)).kerning(0.4).foregroundStyle(Palette.fg2)
                    Spacer()
                    Text(event.date.formatted(.dateTime.hour().minute())).font(.footnote).monospacedDigit().foregroundStyle(Palette.fg2)
                }
                Text(event.title).font(.headline).foregroundStyle(Palette.fg).lineLimit(1)
                Text(event.body).font(.subheadline).foregroundStyle(Palette.fg2)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct SummaryCard: View {
    @Environment(AppModel.self) private var model
    let openInbox: () -> Void

    var body: some View {
        let mine = model.patchedMine.filter { !(model.taskDef($0.taskDefinitionId)?.isMoodle ?? false) }
        let awaiting = mine.filter { $0.status == .readyForFeedback }.count
        let unread = mine.filter { $0.numNewComments > 0 }.count
        let ext = mine.filter(\.hasExtensions).count
        let overdue = mine.filter { model.tier($0) == .overdue }.count
        let overdueAfter = Fmt.days(model.prefs.days(.overdue))
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("SUMMARY").font(.caption.weight(.bold)).kerning(0.4).foregroundStyle(Palette.acc)
                Spacer()
                Text(model.lastRefresh.map { "Updated \($0.formatted(.dateTime.hour().minute()))" } ?? "")
                    .font(.footnote).monospacedDigit().foregroundStyle(Palette.fg2)
            }
            Text(awaiting == 0 ? "Inbox is clear" : "\(awaiting) waiting for you").font(.title2.bold())
            Text(overdue > 0
                 ? "\(overdue) submission\(overdue == 1 ? " has" : "s have") waited \(overdueAfter) or more without feedback."
                 : "Nothing has waited \(overdueAfter) yet.")
                .font(.subheadline).foregroundStyle(overdue > 0 ? WaitTier.overdue.color : Palette.fg2)
            HStack(spacing: 20) {
                stat(awaiting, "awaiting feedback")
                stat(unread, "unread threads")
                stat(ext, "extension requests")
            }
            .padding(.top, 8)
            Button(action: openInbox) {
                Text("Open inbox").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .padding(.top, 8)
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.hair))
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(n)").font(.title.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Palette.fg2)
        }
        .accessibilityElement(children: .combine)
    }
}
