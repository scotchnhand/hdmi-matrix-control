import Foundation

/// Talks to the matrix's embedded HTTP server directly -- the Swift port of
/// `matrix_client.py`. See docs/PROTOCOL.md for the wire format.
///
/// A native app has no CORS problem, so unlike the web app this needs no
/// proxy backend: the phone talks straight to the device on the LAN.
public actor MatrixClient: MatrixService {
    /// Sends a request and returns the response body as text. Injectable so
    /// tests can run without a device.
    public typealias Transport = @Sendable (URLRequest) async throws -> String

    public let host: String
    private let username: String
    private let password: String
    private let transport: Transport
    private let timeout: TimeInterval
    private let firstContactTimeout: TimeInterval
    private var loggedIn = false
    /// True once any request has succeeded. Until then a wrong address is
    /// the likelier problem than a slow device, so we fail fast.
    private var hasConnected = false
    private var tail: Task<Void, Never>?

    /// Reduce whatever the user typed to a bare host (and optional port):
    /// `http://192.168.1.168/` and ` matrix.local ` both work. Returns nil
    /// when nothing host-like is left.
    public static func normalizeHost(_ raw: String) -> String? {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = host.range(of: "://") {
            host = String(host[range.upperBound...])
        }
        if let slash = host.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            host = String(host[..<slash])
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-:[]_"))
        guard !host.isEmpty, host.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return host
    }

    public init(
        host: String,
        username: String = "admin",
        password: String = "admin",
        timeout: TimeInterval = 4,
        firstContactTimeout: TimeInterval = 2,
        transport: Transport? = nil
    ) {
        self.host = Self.normalizeHost(host) ?? host
        self.username = username
        self.password = password
        self.timeout = timeout
        self.firstContactTimeout = min(firstContactTimeout, timeout)
        self.transport = transport ?? Self.urlSessionTransport(timeout: timeout)
    }

    // MARK: - Transport

    private static func urlSessionTransport(timeout: TimeInterval) -> Transport {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        return { request in
            let (data, _) = try await session.data(for: request)
            return String(decoding: data, as: UTF8.self)
        }
    }

    private static func timestamp() -> String {
        String(Int64(Date().timeIntervalSince1970 * 1000))
    }

    private func request(_ method: String, _ path: String, body: String? = nil) async throws -> String {
        guard let url = URL(string: "http://\(host)/\(path)\(Self.timestamp())") else {
            throw MatrixError("Invalid matrix host: \(host)", isConnectivity: true)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = hasConnected ? timeout : firstContactTimeout
        if let body {
            req.httpBody = Data(body.utf8)
            req.setValue("charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.setValue("yes", forHTTPHeaderField: "ISAJAX")
        }
        do {
            do {
                let text = try await transport(req)
                hasConnected = true
                return text
            } catch let error as URLError where hasConnected && method == "GET" && Self.isTransient(error) {
                // The device may have closed an idle keep-alive connection
                // behind our back. Reads are idempotent, so retry once.
                return try await transport(req)
            }
        } catch let error as MatrixError {
            throw error
        } catch {
            throw MatrixError(Self.describe(error, host: host), isConnectivity: true)
        }
    }

    private static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost: true
        default: false
        }
    }

    /// A plain-language explanation instead of the raw URLSession text.
    private static func describe(_ error: Error, host: String) -> String {
        guard let code = (error as? URLError)?.code else {
            return "Could not reach matrix at \(host): \(error.localizedDescription)"
        }
        switch code {
        case .timedOut:
            return "The matrix at \(host) is slow to respond. It may be busy; it will keep retrying."
        case .networkConnectionLost:
            return "The matrix at \(host) dropped the connection. It will keep retrying."
        case .cannotConnectToHost, .cannotFindHost:
            return "Can't find a matrix at \(host). Check the address in Settings."
        case .notConnectedToInternet:
            return "This device isn't on Wi-Fi. Connect to the same network as the matrix."
        default:
            return "Could not reach matrix at \(host): \(error.localizedDescription)"
        }
    }

    /// The device's embedded server can lock up under concurrent requests,
    /// so every call goes through this single queue. (Actor isolation alone
    /// isn't enough: actors are re-entrant across `await`.)
    private func serialized<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> {
            await previous?.value
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }

    // MARK: - Auth

    private func login() async throws {
        let id = Data(username.utf8).base64EncodedString()
        let psd = Data(password.utf8).base64EncodedString()
        let text = try await request("POST", "login.set", body: "#login id=\(id) psd=\(psd)")
        let data = try JSONP.parse(text, callback: "settingsLoginCallback")
        if (Int(data["status"] ?? "0") ?? 0) >= 6 {
            throw MatrixError(data["str"].flatMap { $0.isEmpty ? nil : $0 } ?? "Login failed")
        }
        loggedIn = true
    }

    private func ensureLogin() async throws {
        if !loggedIn { try await login() }
    }

    private func setLoggedOut() { loggedIn = false }

    // MARK: - State

    private func get(_ page: String, callback: String) async throws -> [String: String] {
        try await ensureLogin()
        let text = try await request("GET", "\(page).get")
        do {
            return try JSONP.parse(text, callback: callback)
        } catch {
            // A malformed response usually means the device rebooted and
            // forgot us -- log in again and retry once.
            loggedIn = false
            try await login()
            return try JSONP.parse(try await request("GET", "\(page).get"), callback: callback)
        }
    }

    public func state() async throws -> MatrixState {
        try await serialized {
            let video = try await self.get("video", callback: "VideoCallback")
            let audio = try await self.get("audio", callback: "AudioCallback")
            let edid = try await self.get("edid", callback: "EdidCallback")
            return MatrixState(video: video, audio: audio, edid: edid)
        }
    }

    // MARK: - Commands

    private func command(_ page: String, _ body: String) async throws {
        try await serialized {
            try await self.ensureLogin()
            _ = try await self.request("POST", page, body: body)
        }
    }

    public func setRoute(output: Int, input: Int) async throws {
        try validateRoute(output: output, input: input)
        try await command("video_set", "#video_d out\(output) matrix=\(input - 1)")
    }

    public func setOutputPower(output: Int, on: Bool) async throws {
        guard (1...2).contains(output) else { throw MatrixError("output must be 1 or 2") }
        try await command("video_set", "#video_d out\(output) onoff=\(on ? 1 : 0)")
    }

    public func rename(_ kind: PortKind, index: Int, name: String) async throws {
        try validateName(name)
        try await command("video_set", "#port \(kind.rawValue)\(index) name=\(name)")
    }

    public func setEDID(input: Int, preset: Int) async throws {
        try validateEDID(input: input, preset: preset)
        try await command("edid_set", "#edid_d in\(input) data=\(preset)")
    }

    public func setAudio(_ mode: AudioMode, source: AudioSource) async throws {
        // Field is `ext` on read but `dec` on write.
        let key = mode == .arc ? "arc" : "dec"
        try await command("audio_set", "#audio_d \(key)=\(source.rawValue)")
    }

    public func setNetwork(ip: String, mask: String, gateway: String) async throws {
        try validateNetwork(ip: ip, mask: mask, gateway: gateway)
        try await command("ip.set", "#ip ip=\(ip) mask=\(mask) gw=\(gateway)")
    }

    public func setCredentials(user: String, password: String) async throws {
        try validateCredentials(user: user, password: password)
        try await command("system_set", "#register0 id=\(user) psd=\(password)")
    }

    public func reboot() async throws {
        try await command("system_set", "#power start=1")
        setLoggedOut() // device drops state across reboot
    }

    public func factoryReset() async throws {
        try await command("system_set", "#factory0")
        setLoggedOut()
    }
}
