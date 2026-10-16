import Foundation
import MatrixKit
import Observation

/// Owns the current state, polls the device, and runs user actions --
/// the native equivalent of the web app's `app.js`.
@MainActor
@Observable
final class MatrixStore {
    enum Connection: Equatable {
        case connecting
        case connected
        case lost(String)
    }

    static let pollInterval: Duration = .seconds(3)

    private(set) var state: MatrixState?
    private(set) var connection: Connection = .connecting
    /// Number of user actions in flight. Polls stand down while any are
    /// pending, since the actions' own results are fresher.
    private(set) var pendingActions = 0
    var errorMessage: String?
    /// A non-error heads-up, e.g. "the matrix is restarting".
    var notice: String?

    private var service: (any MatrixService)?
    private var pollTask: Task<Void, Never>?
    /// Bumped on every connect, so results from a previous service (still in
    /// flight when the user switched hosts) are dropped instead of applied.
    private var generation = 0
    /// While the device is expected to be offline (rebooting, changing IP),
    /// failed polls show "Connecting…" instead of "Connection lost".
    private var expectOfflineUntil: ContinuousClock.Instant?

    var isBusy: Bool { pendingActions > 0 }

    /// A store already running against the demo matrix, for previews.
    static func preview() -> MatrixStore {
        let store = MatrixStore()
        store.connect(to: MockMatrixClient(latency: .zero))
        return store
    }

    func connect(using settings: ConnectionSettings) {
        connect(to: settings.makeService())
    }

    func connect(to service: any MatrixService) {
        pollTask?.cancel()
        generation += 1
        state = nil
        connection = .connecting
        // expectOfflineUntil deliberately survives a reconnect: after an IP
        // change we reconnect to the new address while the device moves.
        self.service = service
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func refresh() async {
        guard let service, !isBusy else { return }
        let generation = generation
        do {
            let next = try await service.state()
            guard generation == self.generation, !isBusy else { return }
            state = next
            connection = .connected
            expectOfflineUntil = nil
        } catch {
            guard generation == self.generation else { return }
            if let until = expectOfflineUntil, ContinuousClock.now < until {
                connection = .connecting
            } else {
                connection = .lost(error.localizedDescription)
            }
        }
    }

    /// Run a command against the device.
    ///
    /// - Parameters:
    ///   - optimistic: applied to `state` immediately so taps feel instant,
    ///     and rolled back if the command fails.
    ///   - expectOffline: the command takes the device offline (reboot, IP
    ///     change); skip the follow-up read and treat failed polls for this
    ///     long as "Connecting…".
    ///   - onSuccess: runs on the main actor after the command succeeds.
    func perform(
        optimistic: ((inout MatrixState) -> Void)? = nil,
        expectOffline: Duration? = nil,
        onSuccess: (() -> Void)? = nil,
        _ action: @escaping (any MatrixService) async throws -> Void
    ) {
        guard let service else { return }
        let generation = generation
        let snapshot = state
        if let optimistic, state != nil { optimistic(&state!) }

        Task {
            pendingActions += 1
            defer { pendingActions -= 1 }
            do {
                try await action(service)
                guard generation == self.generation else { return }
                onSuccess?()
                if let expectOffline {
                    expectOfflineUntil = .now + expectOffline
                    connection = .connecting
                    return
                }
                // Mirror the web API, where every POST returns fresh state --
                // but only from the last action in flight, so an earlier
                // action's read can't clobber a later optimistic update.
                if pendingActions == 1 {
                    state = try await service.state()
                    connection = .connected
                }
            } catch {
                guard generation == self.generation else { return }
                errorMessage = error.localizedDescription
                if pendingActions == 1 { state = snapshot }
                if (error as? MatrixError)?.isConnectivity ?? true {
                    connection = .lost(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Actions

    func route(output: Int, to input: Int) {
        perform(optimistic: { $0.updateOutput(output) { $0.inputIndex = input } }) {
            try await $0.setRoute(output: output, input: input)
        }
    }

    func setPower(output: Int, on: Bool) {
        perform(optimistic: { $0.updateOutput(output) { $0.power = on } }) {
            try await $0.setOutputPower(output: output, on: on)
        }
    }

    func setAudio(_ mode: AudioMode, _ source: AudioSource) {
        perform(optimistic: { state in
            switch mode {
            case .arc: state.arc = source
            case .extraction: state.extraction = source
            }
        }) {
            try await $0.setAudio(mode, source: source)
        }
    }

    func setEDID(input: Int, preset: Int) {
        // Skip no-ops: the device's web server is fragile, so don't send it
        // commands that change nothing.
        guard state?.input(input)?.edidPreset != preset else { return }
        perform(optimistic: { state in
            if let i = state.inputs.firstIndex(where: { $0.index == input }) {
                state.inputs[i].edidPreset = preset
            }
        }) {
            try await $0.setEDID(input: input, preset: preset)
        }
    }

    func rename(_ kind: PortKind, index: Int, to name: String) {
        perform { try await $0.rename(kind, index: index, name: name) }
    }

    func reboot() {
        perform(expectOffline: .seconds(30), onSuccess: { [weak self] in
            self?.notice = "The matrix is restarting. It'll reconnect in about 15 seconds."
        }) {
            try await $0.reboot()
        }
    }

    func factoryReset() {
        perform(expectOffline: .seconds(30), onSuccess: { [weak self] in
            self?.notice = "The matrix is resetting to factory defaults. If it doesn't reconnect, its IP address may have changed."
        }) {
            try await $0.factoryReset()
        }
    }
}

private extension MatrixState {
    mutating func updateOutput(_ index: Int, _ change: (inout Output) -> Void) {
        if let i = outputs.firstIndex(where: { $0.index == index }) {
            change(&outputs[i])
        }
    }
}
