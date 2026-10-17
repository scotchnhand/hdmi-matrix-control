import Combine
import Foundation
import MatrixKit

@MainActor
final class MatrixDashboardModel: ObservableObject {
    @Published var baseURLText: String
    @Published private(set) var state: MatrixState?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdatedAt: Date?
    @Published var theme: ThemePreference {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey) }
    }

    /// The iOS target uses this to publish fresh snapshots to Apple Watch.
    var stateDidChange: ((MatrixState) -> Void)?

    private static let baseURLKey = "matrix-control-base-url"
    private static let themeKey = "matrix-control-theme"
    private var client: MatrixAPIClient?

    init() {
        baseURLText = UserDefaults.standard.string(forKey: Self.baseURLKey)
            ?? "http://matrix.local:8765"
        let savedTheme = UserDefaults.standard.string(forKey: Self.themeKey) ?? ThemePreference.system.rawValue
        theme = ThemePreference(rawValue: savedTheme) ?? .system
    }

    var isConnected: Bool { state != nil && errorMessage == nil }

    func connect() {
        let value = baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = normalizedURL(from: value) else {
            errorMessage = MatrixAPIError.invalidBaseURL.localizedDescription
            state = nil
            return
        }

        baseURLText = url.absoluteString
        UserDefaults.standard.set(baseURLText, forKey: Self.baseURLKey)
        client = MatrixAPIClient(baseURL: url)
        refresh()
    }

    func refresh() {
        guard let client else {
            connect()
            return
        }

        isLoading = true
        errorMessage = nil
        Task {
            do {
                let snapshot = try await client.fetchState()
                apply(snapshot)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func setRoute(output: Int, input: Int) {
        perform { client in try await client.route(output: output, input: input) }
    }

    func setOutputPower(output: Int, on: Bool) {
        perform { client in try await client.setOutputPower(output: output, on: on) }
    }

    func setAudio(mode: String, value: Int) {
        perform { client in try await client.setAudio(mode: mode, value: value) }
    }

    func setEDID(input: Int, preset: Int) {
        perform { client in try await client.setEDID(input: input, preset: preset) }
    }

    private func perform(_ action: @escaping (MatrixAPIClient) async throws -> MatrixState) {
        guard let client else {
            connect()
            return
        }

        isLoading = true
        errorMessage = nil
        Task {
            do {
                apply(try await action(client))
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func apply(_ snapshot: MatrixState) {
        state = snapshot
        lastUpdatedAt = Date()
        stateDidChange?(snapshot)
    }

    private func normalizedURL(from value: String) -> URL? {
        let candidate = value.contains("://") ? value : "http://\(value)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }
}
