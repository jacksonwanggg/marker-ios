import Foundation

enum APIError: LocalizedError, Equatable {
    case notSignedIn
    case sessionExpired
    case http(Int, String)
    case duplicate(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "You're not signed in."
        case .sessionExpired: "Your UNSW sign-in has ended. Sign in again."
        case .http(let code, let msg): msg.isEmpty ? "Formatif returned \(code)." : msg
        case .duplicate: "Formatif rejected this comment: it is identical to your last one."
        case .badResponse(let msg): msg
        }
    }
}

enum RequestBody: Sendable {
    case none
    case json(Data)
    case multipart(Multipart)
}

actor FormatifClient {
    static let host = "formatif.cse.unsw.edu.au"
    static let api = URL(string: "https://formatif.cse.unsw.edu.au/api")!

    private let session: URLSession
    private let persist: Bool
    private(set) var credentials: Credentials?
    private var refreshing: Task<Credentials, Error>?

    init(credentials: Credentials?, session: URLSession? = nil, persist: Bool = true) {
        self.session = session ?? Self.makeSession()
        self.persist = persist
        self.credentials = credentials
    }

    static func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        // we send the refresh cookie ourselves from the Keychain
        cfg.httpCookieAcceptPolicy = .never
        cfg.httpShouldSetCookies = false
        cfg.httpCookieStorage = nil
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 60
        return URLSession(configuration: cfg, delegate: StayOnFormatif(), delegateQueue: nil)
    }

    static func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var comps = URLComponents(url: api, resolvingAgainstBaseURL: false)!
        comps.path = "/api/" + (path.hasPrefix("/") ? String(path.dropFirst()) : path)
        if !query.isEmpty { comps.queryItems = query }
        return comps.url!
    }

    // MARK: requests

    func send(_ method: String, _ path: String, query: [URLQueryItem] = [], body: RequestBody = .none) async throws -> (Data, HTTPURLResponse) {
        guard let creds = credentials else { throw APIError.notSignedIn }
        let (data, resp) = try await request(method, path, query, body, creds)
        if resp.statusCode == 419 || resp.statusCode == 401 {
            let fresh = try await refreshShared(failedToken: creds.authToken)
            let (d2, r2) = try await request(method, path, query, body, fresh)
            try Self.check(d2, r2)
            return (d2, r2)
        }
        try Self.check(data, resp)
        return (data, resp)
    }

    func get<T: Decodable & Sendable>(_ type: T.Type, _ path: String, query: [URLQueryItem] = []) async throws -> T {
        let (data, _) = try await send("GET", path, query: query)
        do {
            return try JSON.decoder().decode(T.self, from: data)
        } catch {
            throw APIError.badResponse("Couldn't read Formatif's reply for \(path).")
        }
    }

    func list<T: Decodable & Sendable>(_ type: T.Type, _ path: String, query: [URLQueryItem] = []) async throws -> [T] {
        let result = try await get(LossyList<T>.self, path, query: query)
        #if DEBUG
        if result.skipped > 0 { print("Marker: skipped \(result.skipped) unreadable \(T.self) item(s) from \(path)") }
        #endif
        return result.items
    }

    func download(_ path: String, query: [URLQueryItem] = []) async throws -> DownloadedFile {
        let (data, resp) = try await send("GET", path, query: query)
        let name = Self.filename(from: resp) ?? URL(fileURLWithPath: path).lastPathComponent
        return DownloadedFile(data: data, filename: name, mimeType: resp.mimeType)
    }

    private func request(_ method: String, _ path: String, _ query: [URLQueryItem], _ body: RequestBody,
                         _ creds: Credentials) async throws -> (Data, HTTPURLResponse) {
        #if DEBUG
        if Self.qaReadOnly, let reason = Self.qaBlockReason(method, path) {
            throw APIError.http(0, "Blocked in QA read-only mode: \(reason).")
        }
        #endif
        var req = URLRequest(url: Self.url(path, query: query))
        req.httpMethod = method
        req.setValue(creds.authToken, forHTTPHeaderField: "auth-token")
        req.setValue(creds.username, forHTTPHeaderField: "username")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        switch body {
        case .none:
            break
        case .json(let d):
            req.httpBody = d
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        case .multipart(let m):
            req.httpBody = m.encoded()
            req.setValue(m.contentType, forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse("No response from Formatif.") }
        return (data, http)
    }

    static func check(_ data: Data, _ resp: HTTPURLResponse) throws {
        guard resp.statusCode >= 300 else { return }
        let msg = errorMessage(data)
        if resp.statusCode == 403, msg.lowercased().contains("duplicate") { throw APIError.duplicate(msg) }
        if resp.statusCode == 419 || resp.statusCode == 401 {
            throw APIError.http(resp.statusCode, msg.isEmpty ? "Formatif didn't accept your sign-in." : msg)
        }
        throw APIError.http(resp.statusCode, msg)
    }

    static func errorMessage(_ data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let e = obj["error"] as? String { return e }
            if let e = obj["message"] as? String { return e }
        }
        let text = String(decoding: data.prefix(300), as: UTF8.self)
        return text.contains("<html") ? "" : text
    }

    #if DEBUG
    static var qaReadOnly: Bool { ProcessInfo.processInfo.environment["MARKER_QA_READONLY"] == "1" }

    static func qaBlockReason(_ method: String, _ path: String) -> String? {
        if method != "GET" { return "\(method) requests are writes" }
        let p = path.hasSuffix("/") ? String(path.dropLast()) : path
        if p.hasSuffix("/comments") || p.contains("/comments/") { return "reading comments marks them read" }
        if p.hasSuffix("/submission") || p.hasSuffix("/submission_files") || p.hasSuffix("/submission_details") {
            return "opening a submission counts in marking analytics"
        }
        return nil
    }
    #endif

    // MARK: token refresh

    private func refreshShared(failedToken: String) async throws -> Credentials {
        // another request already refreshed
        if let c = credentials, c.authToken != failedToken { return c }
        if let t = refreshing { return try await t.value }
        let task = Task { try await self.doRefresh() }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    func doRefresh() async throws -> Credentials {
        guard var c = credentials, let rt = c.refreshToken else {
            expire()
            throw APIError.sessionExpired
        }
        var req = URLRequest(url: Self.url("auth/access-token"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("username=\(c.username); refresh_token=\(rt)", forHTTPHeaderField: "Cookie")
        req.httpBody = Data("{}".utf8)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse("No response from Formatif.") }
        if (400..<500).contains(http.statusCode) {
            expire()
            throw APIError.sessionExpired
        }
        guard (200..<300).contains(http.statusCode),
              let auth = try? JSON.decoder().decode(AuthResponse.self, from: data) else {
            throw APIError.http(http.statusCode, Self.errorMessage(data))
        }
        c.authToken = auth.authToken
        c.tokenIssuedAt = .now
        if let cookie = Self.cookie("refresh_token", in: http) {
            c.refreshToken = cookie.value
            if let exp = cookie.expires { c.refreshExpiry = exp }
        }
        credentials = c
        if persist { Keychain.saveCredentials(c) }
        return c
    }

    func refreshIfStale() async {
        guard let c = credentials, Date.now.timeIntervalSince(c.tokenIssuedAt) > 50 * 60 else { return }
        _ = try? await refreshShared(failedToken: c.authToken)
    }

    private func expire() {
        credentials = nil
        if persist { Keychain.deleteCredentials() }
    }

    func signOut() async {
        if let c = credentials {
            _ = try? await request("DELETE", "auth", [URLQueryItem(name: "remember", value: "false")], .none, c)
        }
        expire()
    }

    // MARK: sign-in

    // not cached, the SAML request changes each time
    static func signInURL() async throws -> URL {
        var req = URLRequest(url: url("auth/method"))
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await makeSession().data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse("No response from Formatif.") }
        try check(data, http)
        guard let m = try? JSON.decoder().decode(AuthMethod.self, from: data),
              let s = m.redirectTo, let u = URL(string: s) else {
            throw APIError.badResponse("Formatif didn't return a sign-in page.")
        }
        return u
    }

    static func exchange(oneTimeToken: String, username: String) async throws -> Credentials {
        var req = URLRequest(url: url("auth"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["auth_token": oneTimeToken, "username": username, "remember": true])
        let (data, resp) = try await makeSession().data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse("No response from Formatif.") }
        try check(data, http)
        guard let auth = try? JSON.decoder().decode(AuthResponse.self, from: data) else {
            throw APIError.badResponse("Couldn't read Formatif's sign-in reply.")
        }
        let cookie = cookie("refresh_token", in: http)
        let now = Date.now
        let creds = Credentials(
            username: auth.user?.username ?? username,
            authToken: auth.authToken,
            refreshToken: cookie?.value,
            userID: auth.user?.id,
            firstName: auth.user?.firstName,
            lastName: auth.user?.lastName,
            signedInAt: now,
            refreshExpiry: cookie?.expires ?? now.addingTimeInterval(7 * 86_400),
            tokenIssuedAt: now)
        Keychain.saveCredentials(creds)
        return creds
    }

    static func cookie(_ name: String, in resp: HTTPURLResponse) -> (value: String, expires: Date?)? {
        var fields: [String: String] = [:]
        for (k, v) in resp.allHeaderFields {
            if let k = k as? String, let v = v as? String { fields[k] = v }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: resp.url ?? api)
        if let c = cookies.first(where: { $0.name == name }) { return (c.value, c.expiresDate) }
        if let raw = resp.value(forHTTPHeaderField: "Set-Cookie"), let r = raw.range(of: "\(name)=") {
            let value = raw[r.upperBound...].prefix { $0 != ";" && $0 != "," }
            if !value.isEmpty { return (String(value), nil) }
        }
        return nil
    }

    static func filename(from resp: HTTPURLResponse) -> String? {
        guard let cd = resp.value(forHTTPHeaderField: "Content-Disposition"),
              let r = cd.range(of: "filename=") else { return nil }
        let name = cd[r.upperBound...].split(separator: ";").first.map(String.init) ?? ""
        let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        return trimmed.isEmpty ? nil : trimmed
    }
}

// URLSession copies the auth-token header onto redirects, so never follow one off Formatif
final class StayOnFormatif: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        request.url?.scheme == "https" && request.url?.host == FormatifClient.host ? request : nil
    }
}
