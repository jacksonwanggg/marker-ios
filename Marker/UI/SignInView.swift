import SwiftUI
import WebKit

struct MarkerLogo: View {
    var size: CGFloat = 64
    var body: some View {
        Canvas { ctx, s in
            let k = s.width / 64
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: s), cornerRadius: 16 * k), with: .color(Palette.acc))
            var p = Path()
            p.move(to: CGPoint(x: 17 * k, y: 43 * k))
            p.addLine(to: CGPoint(x: 29 * k, y: 21 * k))
            p.addLine(to: CGPoint(x: 37 * k, y: 35 * k))
            p.addLine(to: CGPoint(x: 47 * k, y: 21 * k))
            ctx.stroke(p, with: .color(Palette.accOn), style: StrokeStyle(lineWidth: 5 * k, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct SSOPage: Identifiable {
    let id = UUID()
    let url: URL
}

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var page: SSOPage?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 28) {
                MarkerLogo()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Marker").font(.markerLargeTitle)
                    Text("Mark Formatif tasks from your phone.")
                        .font(.body)
                        .foregroundStyle(Palette.fg2)
                }
            }
            Spacer()
            VStack(spacing: 10) {
                if let msg = error ?? model.signOutReason {
                    Text(msg).font(.footnote).foregroundStyle(Palette.err).frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    Task { await startSSO() }
                } label: {
                    HStack {
                        if busy { ProgressView().tint(Palette.accOn) }
                        Text("Sign in with UNSW").font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .disabled(busy)

                Button {
                    Task { await model.enterDemo() }
                } label: {
                    Text("Try the demo").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(busy)

                Text("You sign in on Microsoft's page inside the app, so Marker never sees your password.")
                    .font(.footnote)
                    .foregroundStyle(Palette.fg2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .background(Palette.bg)
        .sheet(item: $page) { p in
            SSOSheet(url: p.url) { token, username in
                page = nil
                Task { await finish(token: token, username: username) }
            }
        }
    }

    private func startSSO() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            page = SSOPage(url: try await FormatifClient.signInURL())
        } catch {
            self.error = model.message(error)
        }
    }

    private func finish(token: String, username: String) async {
        busy = true
        defer { busy = false }
        do {
            try await model.signIn(oneTimeToken: token, username: username)
        } catch {
            self.error = model.message(error)
        }
    }
}

struct SSOSheet: View {
    let url: URL
    let onToken: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var host = "login.microsoftonline.com"
    @State private var loading = true

    var body: some View {
        NavigationStack {
            SSOWebView(url: url, host: $host, loading: $loading, onToken: onToken)
                .ignoresSafeArea(edges: .bottom)
                .overlay { if loading { ProgressView() } }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .principal) {
                        Label(host, systemImage: "lock.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.footnote)
                            .foregroundStyle(Palette.fg2)
                    }
                }
        }
    }
}

struct SSOWebView: UIViewRepresentable {
    let url: URL
    @Binding var host: String
    @Binding var loading: Bool
    let onToken: (String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        // keep Microsoft's cookies so "stay signed in" works next time
        cfg.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: cfg)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: SSOWebView
        private var done = false

        init(_ parent: SSOWebView) { self.parent = parent }

        nonisolated static func token(from url: URL) -> (String, String)? {
            guard url.host == FormatifClient.host else { return nil }
            var items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            // the one-time token can also come after the # route
            if let frag = url.fragment, let q = frag.split(separator: "?", maxSplits: 1).last,
               let extra = URLComponents(string: "x://y?\(q)")?.queryItems {
                items += extra
            }
            guard let token = items.first(where: { $0.name == "authToken" })?.value,
                  let user = items.first(where: { $0.name == "username" })?.value else { return nil }
            return (token, user)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }
            if let (token, user) = Self.token(from: url) {
                if !done {
                    done = true
                    parent.onToken(token, user)
                }
                return .cancel
            }
            if let h = url.host { parent.host = h }
            return .allow
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.loading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.loading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.loading = false
        }
    }
}
