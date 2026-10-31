import Combine
import Foundation

/// Syncs the board with the Best Planner server (the web version and other devices signed
/// in to the same account). Works alongside iCloud Drive: the server keeps a version number,
/// and both sides merge with the same three-way merge (Shared/Merge.swift), so edits made
/// on the web and on this Mac at the same time are both kept.
@MainActor
final class CloudSync: ObservableObject {
    static let shared = CloudSync()
    static let server = URL(string: "https://best-planner.orgevery.workers.dev")!
    /// The web version, for opening in the browser.
    static var webURL: URL { server }

    enum Status: Equatable {
        case off, syncing, synced(Date), failed(String)
    }

    @Published private(set) var email: String? = UserDefaults.standard.string(forKey: "cloudEmail")
    @Published private(set) var status: Status = .off

    private var token: String? {
        didSet {
            if let token { try? Data(token.utf8).write(to: Self.tokenURL, options: .atomic) }
            else { try? FileManager.default.removeItem(at: Self.tokenURL) }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.tokenURL.path)
        }
    }
    /// The server's version of the board that `base` is.
    private var version: Int {
        get { UserDefaults.standard.integer(forKey: "cloudVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "cloudVersion") }
    }
    /// The board as last sent to / received from the server: the base for merging. Kept on
    /// disk so web edits made while the app was closed merge properly at the next launch.
    private var base: Board?
    private var timer: Timer?
    private var changes: AnyCancellable?
    private var running = false
    private var again = false

    // The sign-in token isn't kept in the Keychain: the app is signed ad hoc, so every
    // update would make macOS ask for permission to read it again.
    private static var tokenURL: URL { PlannerStorage.localDirectory.appendingPathComponent(".cloud-session") }
    private static var baseURL: URL { PlannerStorage.localDirectory.appendingPathComponent("cloud-base.json") }

    var isSignedIn: Bool { token != nil }

    private init() {
        token = (try? Data(contentsOf: Self.tokenURL)).flatMap { String(data: $0, encoding: .utf8) }
        base = (try? Data(contentsOf: Self.baseURL)).flatMap { try? Self.decoder.decode(Board.self, from: $0) }
    }

    /// Called at launch: syncs now, every 15 seconds, and shortly after each change.
    func start() {
        guard token != nil else { status = .off; return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncSoon() }
        }
        changes = BoardStore.shared.$board
            .dropFirst()
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncSoon() }
        syncSoon()
    }

    func syncSoon() { Task { await sync() } }

    // MARK: Account

    enum AccountError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    func signIn(email: String, password: String, invite: String?, signUp: Bool) async throws {
        var body: [String: String] = ["email": email, "password": password]
        if let invite { body["invite"] = invite }
        let (status, json) = try await request("POST", signUp ? "/api/signup" : "/api/login", body: try JSONSerialization.data(withJSONObject: body))
        guard status == 200, let token = json["token"] as? String else {
            let messages = [
                "wrong": L("密码不对，还可以再试 \((json["left"] as? Int) ?? 1) 次"),
                "no_account": L("没有这个账号，请检查拼写，或先注册"), "locked": L("密码错误次数太多，请 15 分钟后再试"),
                "email_taken": L("这个账号已经被注册了"), "email": L("账号格式不对：用邮箱，或 3–32 位字母、数字、. _ -"),
                "password_short": L("密码至少 8 位"), "invite": L("邀请码不对"),
            ]
            throw AccountError.message(messages[json["error"] as? String ?? ""] ?? L("出错了，请稍后再试"))
        }
        self.token = token
        self.email = json["email"] as? String ?? email
        UserDefaults.standard.set(self.email, forKey: "cloudEmail")
        // A new account (or this Mac's first sign-in): start from scratch; the first sync
        // merges this Mac's board with whatever the server has.
        version = 0
        setBase(nil)
        start()
    }

    func signOut() {
        if token != nil { Task { _ = try? await request("POST", "/api/logout") } }
        token = nil
        email = nil
        UserDefaults.standard.removeObject(forKey: "cloudEmail")
        version = 0
        setBase(nil)
        timer?.invalidate()
        changes = nil
        status = .off
    }

    // MARK: Sync

    func sync() async {
        guard token != nil else { return }
        guard !running else { again = true; return }
        running = true
        if case .synced = status {} else { status = .syncing }
        defer {
            running = false
            if again { again = false; syncSoon() }
        }
        let store = BoardStore.shared
        do {
            let (code, json) = try await request("GET", "/api/board?known=\(version)")
            guard code == 200 else { throw failure(code, json) }
            if json["unchanged"] as? Bool != true {
                try absorb(json)
            }
            // Send what changed here (merging again if someone else saved meanwhile).
            for _ in 0..<5 {
                let current = store.board
                if let base, current == base { break }
                let body = try JSONSerialization.data(withJSONObject: [
                    "baseVersion": version,
                    "board": try JSONSerialization.jsonObject(with: Self.encoder.encode(current)),
                ])
                let (code, json) = try await request("PUT", "/api/board", body: body)
                if code == 200, let v = json["version"] as? Int {
                    version = v
                    setBase(current)
                } else if code == 409 {
                    try absorb(json)
                } else {
                    throw failure(code, json)
                }
            }
            status = .synced(Date())
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// A newer board from the server: merge it into this Mac's.
    private func absorb(_ json: [String: Any]) throws {
        let v = json["version"] as? Int ?? 0
        guard let raw = json["board"], !(raw is NSNull) else {
            // Nothing on the server yet: this Mac's board gets uploaded.
            version = v
            setBase(nil)
            return
        }
        let theirs = try Self.decoder.decode(Board.self, from: JSONSerialization.data(withJSONObject: raw))
        let store = BoardStore.shared
        let start: Board
        if let base {
            start = base
        } else {
            // First sync of this Mac: keep tasks from both sides; this Mac's settings win.
            var b = theirs
            b.tasks = []; b.trash = []; b.contacts = []
            start = b
        }
        let merged = Board.merge(base: start, mine: store.board, theirs: theirs)
        version = v
        setBase(theirs)
        store.applyCloud(merged)
    }

    private func setBase(_ board: Board?) {
        base = board
        if let board, let data = try? Self.encoder.encode(board) {
            try? data.write(to: Self.baseURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: Self.baseURL)
        }
    }

    private func failure(_ code: Int, _ json: [String: Any]) -> Error {
        if code == 401 {
            signOut()
            return AccountError.message(L("登录已过期，请重新登录"))
        }
        return AccountError.message(L("服务器出错（\(code)）"))
    }

    private func request(_ method: String, _ path: String, body: Data? = nil) async throws -> (Int, [String: Any]) {
        var req = URLRequest(url: URL(string: path, relativeTo: Self.server)!)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = body
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw AccountError.message(L("连不上服务器，请检查网络"))
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, json)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
