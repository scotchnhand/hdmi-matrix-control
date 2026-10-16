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
    private(set) var isBusy = false
    var errorMessage: String?

    private var service: (any MatrixService)?
    private var pollTask: Task<Void, Never>?

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
        state = nil
        connection = .connecting
        self.service = service
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func refresh() async {
        // Don't race a user action -- its result is the fresher state.
        guard let service, !isBusy else { return }
        do {
            let next = try await service.state()
            guard !isBusy else { return }
            state = next
            connection = .connected
        } catch {
            connection = .lost(error.localizedDescription)
        }
    }

    /// Run a command, then re-read state (mirroring the web API, where every
    /// POST returns the fresh state).
    func perform(_ action: @escaping (any MatrixService) async throws -> Void) {
        guard let service else { return }
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                try await action(service)
                state = try await service.state()
                connection = .connected
            } catch {
                errorMessage = error.localizedDescription
                if !(error is MatrixError) || state == nil {
                    connection = .lost(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Optimistic helpers for snappy taps

    func route(output: Int, to input: Int) {
        updateOutput(output) { $0.inputIndex = input }
        perform { try await $0.setRoute(output: output, input: input) }
    }

    func setPower(output: Int, on: Bool) {
        updateOutput(output) { $0.power = on }
        perform { try await $0.setOutputPower(output: output, on: on) }
    }

    func setAudio(_ mode: AudioMode, _ source: AudioSource) {
        switch mode {
        case .arc: state?.arc = source
        case .extraction: state?.extraction = source
        }
        perform { try await $0.setAudio(mode, source: source) }
    }

    func setEDID(input: Int, preset: Int) {
        if let i = state?.inputs.firstIndex(where: { $0.index == input }) {
            state?.inputs[i].edidPreset = preset
        }
        perform { try await $0.setEDID(input: input, preset: preset) }
    }

    func rename(_ kind: PortKind, index: Int, to name: String) {
        perform { try await $0.rename(kind, index: index, name: name) }
    }

    private func updateOutput(_ index: Int, _ change: (inout MatrixState.Output) -> Void) {
        if let i = state?.outputs.firstIndex(where: { $0.index == index }) {
            change(&state!.outputs[i])
        }
    }
}
