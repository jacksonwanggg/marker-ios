import SwiftUI

enum DetailTab: String, CaseIterable, Identifiable {
    case submission = "Submission", files = "Files", sheet = "Sheet", comments = "Comments"
    var id: String { rawValue }
}

struct TaskDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let route: TaskRoute

    @State private var current: TaskKey
    @State private var tab: DetailTab
    @State private var base: TaskSummary?
    @State private var detail: TaskDetailModel?
    @State private var confirm: ConfirmRequest?
    @State private var showStudent = false
    @State private var askRegenerate = false
    @State private var notFound = false

    init(route: TaskRoute) {
        self.route = route
        _current = State(initialValue: route.key)
        _tab = State(initialValue: route.tab ?? (route.openComments ? .comments : .submission))
    }

    private var task: TaskSummary? { base.map { model.applying($0, fetchedAt: route.fetchedAt) } }
    private var index: Int? { route.context.firstIndex { $0.key == current } }
    private var td: TaskDefinition? { model.taskDef(current.taskDefID) }

    var body: some View {
        VStack(spacing: 0) {
            if let task, let detail, detail.key == current {
                header(task)
                Divider().overlay(Palette.hair)
                content(detail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if notFound {
                EmptyState(title: "Task not found.", detail: "It may have moved to another unit.")
                Spacer()
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.bg)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let task, let detail {
                VStack(spacing: 0) {
                    if tab == .comments { Composer(detail: detail) }
                    Divider().overlay(Palette.hair)
                    AssessBar(current: task.status) { confirm = ConfirmRequest(task: task, target: $0) }
                }
                .background(.bar)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .toolbar(.hidden, for: .tabBar)
        .task(id: current) { await load(current) }
        .sheet(item: $confirm) { req in
            ConfirmStatusSheet(request: req, detail: detail) { Task { await detail?.statusChanged() } }
        }
        .navigationDestination(isPresented: $showStudent) { StudentDetailView(projectID: current.projectID) }
        .confirmationDialog("Ask Formatif to rebuild the submission PDF?", isPresented: $askRegenerate, titleVisibility: .visible) {
            Button("Regenerate PDF") { Task { await detail?.regeneratePDF() } }
        }
    }

    private func header(_ t: TaskSummary) -> some View {
        let tier = model.tier(t)
        let flags = InboxRow.flags(t)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatusPill(status: t.status)
                    .id(t.status)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                Text(t.submitted.map { "Submitted \(Fmt.long($0))" } ?? dueLine)
                    .font(.footnote).monospacedDigit().foregroundStyle(Palette.fg2).lineLimit(1)
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.35), value: t.status)
            if !flags.isEmpty || tier != .none {
                HStack(spacing: 8) {
                    if tier != .none { WaitTag(tier: tier, days: WaitTier.days(since: t.submitted)) }
                    if !flags.isEmpty { Text(flags).font(.footnote).foregroundStyle(Palette.fg2) }
                }
            }
            SegmentBar(tab: $tab, hasNew: t.numNewComments > 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func content(_ d: TaskDetailModel) -> some View {
        switch tab {
        case .submission: SubmissionTab(detail: d, dueLine: dueLine)
        case .files: FilesTab(detail: d)
        case .sheet: SheetTab(detail: d, td: td)
        case .comments: CommentsTab(detail: d)
        }
    }

    private var dueLine: String {
        guard let due = Fmt.parse(td?.dueDate) else { return "No due date" }
        return "Due \(Fmt.day(due))"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text(model.studentName(current.projectID)).font(.headline).lineLimit(1)
                Text(model.taskLine(current.taskDefID)).font(.caption).foregroundStyle(Palette.fg2).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { step(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(index.map { $0 == 0 } ?? true)
                .keyboardShortcut(.upArrow, modifiers: [])
                .accessibilityLabel("Previous task")
            Button { step(1) } label: { Image(systemName: "chevron.down") }
                .disabled(index.map { $0 >= route.context.count - 1 } ?? true)
                .keyboardShortcut(.downArrow, modifiers: [])
                .accessibilityLabel("Next task")
            Menu {
                if let task {
                    Button(task.pinned ? "Unpin" : "Pin", systemImage: task.pinned ? "pin.slash" : "pin") {
                        Task { await model.togglePin(task) }
                    }
                    Menu("More statuses", systemImage: "ellipsis.circle") {
                        ForEach(TaskStatus.more) { s in
                            Button(s.label) { confirm = ConfirmRequest(task: task, target: s) }
                        }
                    }
                }
                Button("Regenerate PDF", systemImage: "arrow.triangle.2.circlepath") { askRegenerate = true }
                Button("Student and staff notes", systemImage: "person.text.rectangle") { showStudent = true }
                if task?.similarityFlag == true {
                    Label("Similarity flagged in Formatif", systemImage: "exclamationmark.triangle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
    }

    private func load(_ key: TaskKey) async {
        notFound = false
        if base?.key != key {
            base = route.context.first { $0.key == key }
        }
        if base == nil { base = await model.summary(for: key) }
        guard base != nil else { notFound = true; return }
        if detail?.key != key { detail = TaskDetailModel(key: key, unitID: model.unitID ?? 0, model: model) }
    }

    private func step(_ dir: Int) {
        guard let i = index else { return }
        let j = i + dir
        guard route.context.indices.contains(j) else { return }
        let next = route.context[j]
        base = next
        detail = TaskDetailModel(key: next.key, unitID: model.unitID ?? 0, model: model)
        current = next.key
    }
}

struct SegmentBar: View {
    @Binding var tab: DetailTab
    var hasNew: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases) { t in
                Button {
                    tab = t
                } label: {
                    HStack(spacing: 5) {
                        Text(t.rawValue).lineLimit(1).minimumScaleFactor(0.8)
                        if t == .comments, hasNew { Circle().fill(Palette.acc).frame(width: 7, height: 7) }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tab == t ? Palette.fg : Palette.fg2)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(tab == t ? Palette.seg : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        if tab == t { RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.hair, lineWidth: 1) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
                .accessibilityLabel(t == .comments && hasNew ? "Comments, unread" : t.rawValue)
            }
        }
        .padding(2)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - Submission

struct SubmissionTab: View {
    let detail: TaskDetailModel
    let dueLine: String

    var body: some View {
        Group {
            switch detail.submission {
            case .idle, .loading:
                ProgressView("Loading the submission")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let msg):
                EmptyState(title: "Couldn't load the submission.", detail: msg, action: "Try again") {
                    Task { await detail.loadSubmission(force: true) }
                }
            case .done(.none):
                EmptyState(title: "No submission yet.", detail: dueLine)
            case .done(.noUploads):
                EmptyState(title: "Nothing to upload for this task.", detail: "It's assessed by its status, in class or on Moodle.")
            case .done(.processing):
                EmptyState(title: "Formatif is still building the PDF.", detail: "Formatif builds PDFs every 5 minutes, so it can take up to about 15.", action: "Check again") {
                    Task { await detail.loadSubmission(force: true) }
                }
            case .done(.noPDF):
                EmptyState(title: "Formatif has no PDF for this submission.",
                           detail: "The uploaded files are under Files. Regenerate PDF is in the ••• menu.", action: "Check again") {
                    Task { await detail.loadSubmission(force: true) }
                }
            case .done(.pdf(let doc, let name)):
                PDFPane(document: doc, name: name)
            }
        }
        .task { await detail.loadSubmission() }
    }
}

// MARK: - Files

struct FilesTab: View {
    @Environment(AppModel.self) private var model
    let detail: TaskDetailModel
    @State private var openText: ZipEntry?
    @State private var preview: URL?

    var body: some View {
        Group {
            switch detail.files {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let msg):
                EmptyState(title: "Couldn't load the files.", detail: msg)
            case .done(nil):
                if model.taskDef(detail.key.taskDefID)?.hasUploads == false {
                    EmptyState(title: "Nothing to upload for this task.")
                } else {
                    EmptyState(title: "No files uploaded.")
                }
            case .done(let bundle?):
                FileList(bundle: bundle) { open($0) }
            }
        }
        .navigationDestination(item: $openText) { CodeView(entry: $0) }
        .quickLookPreview($preview)
        .task { await detail.loadFiles() }
    }

    private func open(_ e: ZipEntry) {
        if e.isText { openText = e } else { preview = TempFiles.write(e.data, name: e.name) }
    }
}

struct FileList: View {
    let bundle: FileBundle
    let open: (ZipEntry) -> Void

    var body: some View {
        List {
            Text("\(bundle.name) · \(bundle.entries.count) file\(bundle.entries.count == 1 ? "" : "s") · \(Fmt.size(bundle.totalSize))")
                .font(.footnote.monospaced())
                .foregroundStyle(Palette.fg2)
                .listRowSeparator(.hidden)
                .markerRow()
            ForEach(bundle.entries) { e in
                Button {
                    open(e)
                } label: {
                    HStack(spacing: 12) {
                        Text(e.badge)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.fg2)
                            .frame(width: 36, height: 36)
                            .background(Palette.fill, in: RoundedRectangle(cornerRadius: 8))
                        Text(e.path).font(.system(.subheadline, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(Palette.fg)
                        Spacer(minLength: 8)
                        Text(Fmt.size(e.size)).font(.footnote).monospacedDigit().foregroundStyle(Palette.fg2)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.fg3)
                    }
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .markerRow()
            }
        }
        .listStyle(.plain)
    }
}

struct CodeView: View {
    @Environment(AppModel.self) private var model
    let entry: ZipEntry

    private var text: String { String(decoding: entry.data, as: UTF8.self) }

    var body: some View {
        let lines = text.components(separatedBy: "\n")
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(i + 1)").foregroundStyle(Palette.fg3).frame(minWidth: 24, alignment: .trailing)
                        Text(Highlighter.line(lines[i], latex: entry.isLatex))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 18)
                }
            }
            .padding(12)
            .textSelection(.enabled)
        }
        .background(Palette.bg)
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Copy") {
                UIPasteboard.general.string = text
                model.show("Copied \(entry.name)")
            }
        }
    }
}

enum Highlighter {
    static func line(_ s: String, latex: Bool) -> AttributedString {
        latex ? latexLine(s) : codeLine(s)
    }

    private static func codeLine(_ s: String) -> AttributedString {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        var a = AttributedString(s)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") {
            a.foregroundColor = Palette.fg2
        }
        return a
    }

    private static func latexLine(_ s: String) -> AttributedString {
        let math = TaskStatus.needHelp.color
        var out = AttributedString()
        let chars = Array(s)
        var plain = ""
        var inMath = false
        var i = 0
        func emit(_ text: String, _ color: Color?, italic: Bool = false) {
            guard !text.isEmpty else { return }
            var a = AttributedString(text)
            if let color { a.foregroundColor = color }
            if italic { a.font = .system(size: 12, design: .monospaced).italic() }
            out.append(a)
        }
        while i < chars.count {
            let c = chars[i]
            if c == "%", i == 0 || chars[i - 1] != "\\" {
                emit(plain, inMath ? math : nil)
                emit(String(chars[i...]), Palette.fg2, italic: true)
                return out
            }
            if c == "\\" {
                emit(plain, inMath ? math : nil)
                plain = ""
                var j = i + 1
                while j < chars.count, chars[j].isLetter || chars[j] == "@" { j += 1 }
                if j == i + 1, j < chars.count { j += 1 }
                let cmd = String(chars[i..<j])
                if ["\\[", "\\("].contains(cmd) { inMath = true; emit(cmd, math) }
                else if ["\\]", "\\)"].contains(cmd) { emit(cmd, math); inMath = false }
                else { emit(cmd, inMath ? math : Palette.acc) }
                i = j
                continue
            }
            if c == "$" {
                if inMath {
                    plain.append(c)
                    emit(plain, math)
                    plain = ""
                    inMath = false
                } else {
                    emit(plain, nil)
                    plain = "$"
                    inMath = true
                }
                i += 1
                continue
            }
            plain.append(c)
            i += 1
        }
        emit(plain, inMath ? math : nil)
        return out
    }
}

// MARK: - Task sheet

struct SheetTab: View {
    @Environment(AppModel.self) private var model
    let detail: TaskDetailModel
    let td: TaskDefinition?
    @State private var showInfo = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(info).font(.footnote).monospacedDigit().foregroundStyle(Palette.fg2).lineLimit(1)
                Spacer()
                Button("Details") { showInfo = true }.font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            switch detail.sheet {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let msg):
                EmptyState(title: "Couldn't load the task sheet.", detail: msg)
                Spacer()
            case .done(nil):
                ScrollView { TaskInfo(detail: detail, td: td).padding(16) }
            case .done(let doc?):
                PDFPane(document: doc, name: "\(td?.abbreviation ?? "task")-sheet.pdf")
            }
        }
        .sheet(isPresented: $showInfo) {
            NavigationStack {
                ScrollView { TaskInfo(detail: detail, td: td).padding(16) }
                    .navigationTitle(td?.abbreviation ?? "Task")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Done") { showInfo = false } }
            }
            .environment(model)
            .presentationDetents([.medium, .large])
        }
        .task { await detail.loadSheet(hasSheet: td?.hasTaskSheet ?? false) }
    }

    private var info: String {
        var parts: [String] = []
        if let d = Fmt.parse(td?.dueDate) { parts.append("Due \(Fmt.day(d))") }
        if let td { parts.append("Target \(td.gradeLetter)") }
        return parts.joined(separator: " · ")
    }
}

struct TaskInfo: View {
    @Environment(AppModel.self) private var model
    let detail: TaskDetailModel
    let td: TaskDefinition?
    @State private var showResources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(td?.name ?? "Task").font(.title3.bold())
            if let desc = td?.description, !desc.isEmpty {
                Text(desc).font(.body).foregroundStyle(Palette.fg)
            }
            let prereqs = model.prerequisites.filter { $0.taskDefinitionId == td?.id }
            if !prereqs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Prerequisites")
                    ForEach(prereqs) { p in
                        Text("\(model.taskLine(p.prerequisiteId))\(p.taskStatus.map { " · \(TaskStatus(key: $0).label)" } ?? "")")
                            .font(.subheadline)
                    }
                }
            }
            if td?.hasTaskResources ?? false {
                Button {
                    showResources = true
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Resources").font(.body)
                            Text("Starter files from the task").font(.footnote).foregroundStyle(Palette.fg2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Palette.fg3)
                    }
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationDestination(isPresented: $showResources) { ResourcesView(detail: detail) }
    }
}

struct ResourcesView: View {
    let detail: TaskDetailModel
    @State private var openText: ZipEntry?
    @State private var preview: URL?

    var body: some View {
        Group {
            switch detail.resources {
            case .idle, .loading: ProgressView()
            case .failed(let msg): EmptyState(title: "Couldn't load resources.", detail: msg)
            case .done(nil): EmptyState(title: "No resources for this task.")
            case .done(let b?):
                FileList(bundle: b) { e in
                    if e.isText { openText = e } else { preview = TempFiles.write(e.data, name: e.name) }
                }
            }
        }
        .navigationTitle("Resources")
        .navigationDestination(item: $openText) { CodeView(entry: $0) }
        .quickLookPreview($preview)
        .task { await detail.loadResources() }
    }
}
