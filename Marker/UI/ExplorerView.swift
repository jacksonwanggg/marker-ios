import SwiftUI

struct ExplorerView: View {
    @Environment(AppModel.self) private var model
    @State private var tdID: Int?
    @State private var rows: [TaskSummary] = []
    @State private var fetchedAt = Date.distantPast
    @State private var loading = false
    @State private var error: String?
    @State private var status: TaskStatus?
    @State private var tutorial: Int?
    @State private var mineOnly = true

    private var taskDefs: [TaskDefinition] { model.unit?.taskDefinitions ?? [] }

    private var scoped: [TaskSummary] {
        let mine = model.myTutorialIDs
        return rows.map { model.applying($0, fetchedAt: fetchedAt) }.filter { t in
            if let tutorial { return t.tutorialId == tutorial }
            if mineOnly { return mine.contains(t.tutorialId ?? -1) }
            return true
        }
    }

    private var filtered: [TaskSummary] {
        let name = { (t: TaskSummary) in model.studentName(t.projectId) }
        return scoped.filter { status == nil || $0.status == status }
            .sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
    }

    var body: some View {
        let list = filtered
        List {
            VStack(alignment: .leading, spacing: 12) {
                Menu {
                    Picker("Task", selection: $tdID) {
                        ForEach(taskDefs) { td in Text(td.line).tag(Int?.some(td.id)) }
                    }
                } label: {
                    HStack {
                        Text(tdID.flatMap(model.taskDef)?.line ?? "Choose a task").lineLimit(1).foregroundStyle(Palette.fg)
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Palette.fg2)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.hair))
                }
                .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(counts, id: \.0) { s, n in
                            Chip(on: status == s, action: { status = status == s ? nil : s }) {
                                StatusDot(status: s, size: 8)
                                Text("\(n)").fontWeight(.bold).monospacedDigit()
                                Text(s.label)
                            }
                            .accessibilityLabel("\(n) \(s.label)")
                        }
                    }
                    .padding(.horizontal, 16)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(on: tutorial == nil && mineOnly, action: { tutorial = nil; mineOnly = true }) { Text("My tutorials") }
                        Chip(on: tutorial == nil && !mineOnly, action: { tutorial = nil; mineOnly = false }) { Text("All tutorials") }
                        ForEach(sortedTutorials) { t in
                            Chip(on: tutorial == t.id, action: { tutorial = t.id }) {
                                Text("\(model.myTutorialIDs.contains(t.id) ? "★ " : "")\(t.abbreviation)")
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 8)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Palette.bg)

            if loading, rows.isEmpty {
                ForEach(0..<6, id: \.self) { _ in PlaceholderRow().markerRow() }
            } else if let error {
                EmptyState(title: "Couldn't load this task.", detail: error, action: "Try again") { Task { await load() } }
                    .listRowSeparator(.hidden)
            } else if list.isEmpty {
                EmptyState(title: "No tasks match.").listRowSeparator(.hidden)
            } else {
                ForEach(list) { t in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.studentName(t.projectId)).font(.headline).lineLimit(1)
                            Text("\(model.tutorial(t.tutorialId)?.abbreviation ?? "") · \(model.zid(t.projectId))")
                                .font(.footnote).monospacedDigit().foregroundStyle(Palette.fg2)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 4) {
                            StatusPill(status: t.status)
                            Text(t.submitted.map { Fmt.relative($0) } ?? "Not submitted")
                                .font(.footnote).monospacedDigit().foregroundStyle(Palette.fg2)
                        }
                    }
                    .frame(minHeight: 60)
                    .contentShape(Rectangle())
                    .background(NavigationLink("", value: TaskRoute(key: t.key, context: list, fetchedAt: fetchedAt)).opacity(0))
                    .markerRow()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .navigationTitle("Explorer")
        .toolbar { ToolbarItem(placement: .topBarLeading) { UnitMenu() } }
        .refreshable { await load() }
        .task(id: "\(model.unitID ?? 0)-\(tdID ?? 0)-\(taskDefs.count)") {
            if tdID.flatMap(model.taskDef) == nil { tdID = defaultTask() }
            await load()
        }
        .onChange(of: tdID) { _, _ in status = nil }
    }

    private var counts: [(TaskStatus, Int)] {
        let all = scoped
        return TaskStatus.allCases.compactMap { s in
            let n = all.filter { $0.status == s }.count
            return n > 0 ? (s, n) : nil
        }
    }

    private var sortedTutorials: [Tutorial] {
        let mine = model.myTutorialIDs
        return (model.unit?.tutorials ?? []).sorted {
            let a = mine.contains($0.id), b = mine.contains($1.id)
            return a != b ? a : $0.abbreviation < $1.abbreviation
        }
    }

    // latest (W) task that's already due, otherwise the next one
    private func defaultTask() -> Int? {
        let weekly = taskDefs.filter { $0.name.hasPrefix("(W)") }
        let pool = weekly.isEmpty ? taskDefs.filter { !$0.isMoodle } : weekly
        let now = Date.now
        func target(_ td: TaskDefinition) -> Date? { Fmt.parse(td.targetDate) ?? Fmt.parse(td.dueDate) }
        if let latest = pool.compactMap(target).filter({ $0 <= now }).max() {
            return pool.first { target($0) == latest }?.id
        }
        let next = pool.filter { (target($0) ?? .distantFuture) > now }
            .min { (target($0) ?? .distantFuture) < (target($1) ?? .distantFuture) }
        return (next ?? pool.first ?? taskDefs.first)?.id
    }

    private func load() async {
        guard let unitID = model.unitID, let tdID else { return }
        loading = true
        defer { loading = false }
        do {
            rows = try await model.backend.explorer(unitID: unitID, taskDefID: tdID)
            fetchedAt = .now
            error = nil
        } catch {
            self.error = model.message(error)
            model.handle(error, quiet: true)
        }
    }
}
