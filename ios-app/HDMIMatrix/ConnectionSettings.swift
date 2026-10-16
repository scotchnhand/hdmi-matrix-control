import Foundation
import MatrixKit
import Observation
import Security

/// Where the matrix is and how to log in. Host/username/demo flag live in
/// UserDefaults; the password lives in the Keychain.
@Observable
final class ConnectionSettings {
    private enum Key {
        static let host = "matrixHost"
        static let username = "matrixUsername"
        static let demoMode = "demoMode"
        static let keychainAccount = "matrixPassword"
    }

    private let defaults: UserDefaults

    private(set) var host: String
    private(set) var username: String
    private(set) var password: String
    private(set) var demoMode: Bool
    /// Bumped on every save so the app reconnects.
    private(set) var revision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        host = defaults.string(forKey: Key.host) ?? "matrix.local"
        username = defaults.string(forKey: Key.username) ?? "admin"
        password = Keychain.read(Key.keychainAccount) ?? "admin"
        // Default to demo mode until the user has configured a real host,
        // so the first launch shows something useful.
        demoMode = defaults.object(forKey: Key.demoMode) as? Bool ?? true
    }

    /// UI tests launch with `-ui-testing`: always the demo matrix, with
    /// throwaway settings so runs are repeatable and never touch real ones.
    static func forLaunch() -> ConnectionSettings {
        guard CommandLine.arguments.contains("-ui-testing") else { return ConnectionSettings() }
        let suite = "HDMIMatrix.UITests"
        UserDefaults().removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: Key.demoMode)
        return ConnectionSettings(defaults: defaults)
    }

    func save(host: String, username: String, password: String, demoMode: Bool) {
        self.host = MatrixClient.normalizeHost(host) ?? host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.username = username
        self.password = password
        self.demoMode = demoMode
        defaults.set(self.host, forKey: Key.host)
        defaults.set(username, forKey: Key.username)
        defaults.set(demoMode, forKey: Key.demoMode)
        Keychain.write(password, account: Key.keychainAccount)
        revision += 1
    }

    func makeService() -> any MatrixService {
        demoMode
            ? MockMatrixClient()
            : MatrixClient(host: host, username: username, password: password)
    }
}

private enum Keychain {
    private static let service = "HDMIMatrix"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func write(_ value: String, account: String) {
        SecItemDelete(query(account) as CFDictionary)
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}
