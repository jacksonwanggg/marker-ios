import PDFKit
import SwiftUI

struct PDFPane: View {
    let document: PDFDocument
    let name: String
    @State private var page = 1
    @State private var searching = false
    @State private var query = ""
    @State private var matches: [PDFSelection] = []
    @State private var matchIndex = 0
    @State private var fullScreen = false
    @FocusState private var searchFocused: Bool

    private var pageLabel: String { "Page \(page) of \(document.pageCount)" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(name)
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.fg2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(pageLabel).font(.caption).monospacedDigit().foregroundStyle(Palette.fg2)
                Button {
                    searching.toggle()
                    searchFocused = searching
                    if !searching { clearSearch() }
                } label: {
                    Image(systemName: "magnifyingglass").frame(width: 36, height: 36)
                }
                .accessibilityLabel("Search in PDF")
                Button { fullScreen = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 36, height: 36)
                }
                .accessibilityLabel("Full screen")
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)

            if searching {
                HStack(spacing: 8) {
                    TextField("Find in PDF", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .focused($searchFocused)
                        .onSubmit(runSearch)
                    Text(matches.isEmpty ? "" : "\(matchIndex + 1)/\(matches.count)")
                        .font(.caption).monospacedDigit().foregroundStyle(Palette.fg2)
                    Button { move(-1) } label: { Image(systemName: "chevron.up") }.disabled(matches.isEmpty)
                    Button { move(1) } label: { Image(systemName: "chevron.down") }.disabled(matches.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            PDFKitView(document: document, page: $page, highlights: matches,
                       focus: matches.indices.contains(matchIndex) ? matches[matchIndex] : nil, thumbnails: true)
        }
        .fullScreenCover(isPresented: $fullScreen) {
            NavigationStack {
                PDFKitView(document: document, page: $page, highlights: matches, focus: nil, thumbnails: false)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { fullScreen = false } }
                        ToolbarItem(placement: .status) { Text(pageLabel).font(.caption).monospacedDigit() }
                    }
            }
        }
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { clearSearch(); return }
        matches = document.findString(q, withOptions: .caseInsensitive)
        matchIndex = 0
    }

    private func move(_ d: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + d + matches.count) % matches.count
    }

    private func clearSearch() {
        query = ""
        matches = []
        matchIndex = 0
    }
}

final class PDFContainerView: UIView {
    let pdfView = PDFView()
    let thumbs = PDFThumbnailView()

    init(thumbnails: Bool) {
        super.init(frame: .zero)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.pageShadowsEnabled = false
        pdfView.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x1c1c1e) : UIColor(hex: 0xf2f2f7) }
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pdfView)
        var constraints = [
            pdfView.topAnchor.constraint(equalTo: topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ]
        if thumbnails {
            thumbs.pdfView = pdfView
            thumbs.layoutMode = .horizontal
            thumbs.thumbnailSize = CGSize(width: 30, height: 40)
            thumbs.backgroundColor = pdfView.backgroundColor
            thumbs.translatesAutoresizingMaskIntoConstraints = false
            addSubview(thumbs)
            constraints += [
                thumbs.topAnchor.constraint(equalTo: pdfView.bottomAnchor),
                thumbs.leadingAnchor.constraint(equalTo: leadingAnchor),
                thumbs.trailingAnchor.constraint(equalTo: trailingAnchor),
                thumbs.bottomAnchor.constraint(equalTo: bottomAnchor),
                thumbs.heightAnchor.constraint(equalToConstant: 56),
            ]
        } else {
            constraints.append(pdfView.bottomAnchor.constraint(equalTo: bottomAnchor))
        }
        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var page: Int
    var highlights: [PDFSelection]
    var focus: PDFSelection?
    var thumbnails: Bool

    func makeCoordinator() -> Coordinator { Coordinator(page: $page) }

    func makeUIView(context: Context) -> PDFContainerView {
        let view = PDFContainerView(thumbnails: thumbnails)
        view.pdfView.document = document
        context.coordinator.pdfView = view.pdfView
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged),
                                               name: .PDFViewPageChanged, object: view.pdfView)
        if let p = document.page(at: max(0, page - 1)) { view.pdfView.go(to: p) }
        return view
    }

    func updateUIView(_ view: PDFContainerView, context: Context) {
        context.coordinator.page = $page
        if view.pdfView.document !== document { view.pdfView.document = document }
        view.pdfView.highlightedSelections = highlights.isEmpty ? nil : highlights
        if let focus, focus !== context.coordinator.lastFocus {
            context.coordinator.lastFocus = focus
            view.pdfView.go(to: focus)
        }
    }

    static func dismantleUIView(_ view: PDFContainerView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    final class Coordinator: NSObject {
        var page: Binding<Int>
        weak var pdfView: PDFView?
        var lastFocus: PDFSelection?

        init(page: Binding<Int>) { self.page = page }

        @objc func pageChanged() {
            guard let v = pdfView, let p = v.currentPage, let doc = v.document else { return }
            let n = doc.index(for: p) + 1
            if page.wrappedValue != n { page.wrappedValue = n }
        }
    }
}
