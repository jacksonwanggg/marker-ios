import SwiftUI

struct StudentsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var mineOnly = true

    private var rows: [ProjectSummary] {
        let mine = model.myTutorialIDs
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return model.students.filter { p in
            if mineOnly, q.isEmpty, !p.tutorialIDs.contains(where: mine.contains) { return false }
            if !q.isEmpty { return p.student.name.lowercased().contains(q) || p.student.zid.lowercased().contains(q) }
            return true
        }
    }

    var body: some View {
        let mine = model.myTutorialIDs
        let list = rows
        let inMine = model.students.filter { $0.tutorialIDs.contains(where: mine.contains) }.count
        List {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(model.students.count) enrolled · \(inMine) in your tutorials")
                    .font(.footnote).monospacedDigit().foregroundStyle(Palette.fg2)
                HStack(spacing: 8) {
                    Chip(on: mineOnly, action: { mineOnly = true }) { Text("My tutorials") }
                    Chip(on: !mineOnly, action: { mineOnly = false }) { Text("Everyone") }
                }
            }
            .padding(.bottom, 8)
            .listRowSeparator(.hidden)
            .listRowBackground(Palette.bg)

            if model.students.isEmpty {
                ForEach(0..<6, id: \.self) { _ in PlaceholderRow().markerRow() }
            } else if list.isEmpty {
                EmptyState(title: "No students match.").listRowSeparator(.hidden)
            } else {
                ForEach(list) { p in
                    NavigationLink(value: StudentRoute(projectID: p.id)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.student.name).font(.headline).lineLimit(1)
                                Text("\(tutorials(p, mine: mine)) · \(p.student.zid)")
                                    .font(.footnote).monospacedDigit().foregroundStyle(Palette.fg2)
                            }
                            Spacer()
                            Text(Grade.letter(p.targetGrade)).font(.footnote.weight(.semibold)).foregroundStyle(Palette.fg2)
                                .accessibilityLabel("Target \(Grade.letter(p.targetGrade))")
                        }
                        .frame(minHeight: 56)
                    }
                    .markerRow()
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .navigationTitle("Students")
        .toolbar { ToolbarItem(placement: .topBarLeading) { UnitMenu() } }
        .searchable(text: $search, prompt: "Name or zID")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    private func tutorials(_ p: ProjectSummary, mine: Set<Int>) -> String {
        let s = p.tutorialIDs.compactMap { id in model.tutorial(id).map { $0.abbreviation + (mine.contains(id) ? " ★" : "") } }
        return s.isEmpty ? "No tutorial" : s.joined(separator: ", ")
    }
}

struct StudentDetailView: View {
    @Environment(AppModel.self) private var model
    let projectID: Int

    @State private var project: ProjectDetail?
    @State private var fetchedAt = Date.distantPast
    @State private var error: String?
    @State private var notes: [StaffNote] = []
    @State private var notesLoaded = false
    @State private var drafting = false
    @State private var draft = ""
    @State private var saving = false
    @State private var deleteNote: StaffNote?
    @FocusState private var noteFocused: Bool

    private var student: ProjectSummary? { model.projects[projectID] }

    private var tasks: [TaskSummary] {
        guard let project else { return [] }
        let defs = model.unit?.taskDefinitions ?? []
        let order = Dictionary(defs.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        return project.tasks
            .sorted { (order[$0.taskDefinitionId] ?? .max) < (order[$1.taskDefinitionId] ?? .max) }
            .map { model.applying(TaskSummary(projectID: project.id, task: $0), fetchedAt: fetchedAt) }
    }

    var body: some View {
        let list = tasks
        List {
            VStack(alignment: .leading, spacing: 2) {
                Text(student?.student.name ?? model.studentName(projectID)).font(.title.bold())
                Text(subtitle).font(.subheadline).monospacedDigit().foregroundStyle(Palette.fg2)
            }
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)
            .markerRow()

            Section {
                if project == nil, error == nil {
                    ForEach(0..<4, id: \.self) { _ in PlaceholderRow().markerRow() }
                } else if let error {
                    EmptyState(title: "Couldn't load tasks.", detail: error, action: "Try again") { Task { await load() } }
                }
                ForEach(list) { t in
                    let td = model.taskDef(t.taskDefinitionId)
                    let due = project?.tasks.first { $0.id == t.id }?.dueDate ?? td?.dueDate
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            (Text(td?.abbreviation ?? "").fontWeight(.semibold).monospacedDigit()
                             + Text(" " + (td?.name ?? "")))
                                .lineLimit(1)
                            Text([Fmt.parse(due).map { "Due \(Fmt.day($0))" }, t.submitted.map { "Submitted \(Fmt.long($0))" }]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.footnote).monospacedDigit().foregroundStyle(Palette.fg2).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        StatusPill(status: t.status)
                    }
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                    .background(NavigationLink("", value: TaskRoute(key: t.key, context: list, fetchedAt: fetchedAt)).opacity(0))
                    .markerRow()
                }
            } header: {
                SectionLabel(text: "Tasks")
            }

            Section {
                if drafting {
                    HStack(spacing: 8) {
                        TextField("Visible to staff only", text: $draft, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($noteFocused)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") { Task { await saveNote() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                    }
                    .padding(.vertical, 8)
                    .markerRow()
                }
                ForEach(notes) { n in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(n.note ?? "").font(.subheadline)
                        HStack {
                            Text("\(author(n)) · \(Fmt.thread(Fmt.parse(n.createdAt)))").font(.footnote).foregroundStyle(Palette.fg2)
                            Spacer()
                            if n.userId == model.myUserID {
                                Button("Delete") { deleteNote = n }
                                    .font(.footnote.weight(.semibold)).foregroundStyle(Palette.err).buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .markerRow()
                }
                if notesLoaded, notes.isEmpty, !drafting {
                    Text("No notes yet.").font(.subheadline).foregroundStyle(Palette.fg2).markerRow()
                }
            } header: {
                HStack {
                    SectionLabel(text: "Staff notes")
                    Spacer()
                    Button("Add note") { drafting = true; noteFocused = true }.font(.subheadline.weight(.semibold))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog("Delete this note?", isPresented: Binding(get: { deleteNote != nil }, set: { if !$0 { deleteNote = nil } }),
                            titleVisibility: .visible, presenting: deleteNote) { n in
            Button("Delete", role: .destructive) { Task { await removeNote(n) } }
        }
    }

    private var subtitle: String {
        guard let s = student else { return "" }
        let tuts = s.tutorialIDs.compactMap { model.tutorial($0)?.abbreviation }.joined(separator: ", ")
        return [s.student.zid, tuts, "Target \(Grade.letter(s.targetGrade))"].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func author(_ n: StaffNote) -> String {
        if n.userId == model.myUserID { return "You" }
        return model.unit?.staff?.first { $0.user.id == n.userId }?.user.fullName ?? "Staff"
    }

    private func load() async {
        let b = model.backend
        do {
            project = try await b.project(projectID)
            fetchedAt = .now
            error = nil
        } catch {
            self.error = model.message(error)
        }
        notes = ((try? await b.staffNotes(projectID: projectID)) ?? []).sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
        notesLoaded = true
    }

    private func saveNote() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        saving = true
        defer { saving = false }
        do {
            let n = try await model.backend.addStaffNote(projectID: projectID, text: text)
            notes.insert(n, at: 0)
            draft = ""
            drafting = false
            model.show("Note saved")
        } catch {
            model.show(model.message(error), error: true)
        }
    }

    private func removeNote(_ n: StaffNote) async {
        do {
            try await model.backend.deleteStaffNote(projectID: projectID, id: n.id)
            notes.removeAll { $0.id == n.id }
            model.show("Note deleted")
        } catch {
            model.show(model.message(error), error: true)
        }
    }
}
