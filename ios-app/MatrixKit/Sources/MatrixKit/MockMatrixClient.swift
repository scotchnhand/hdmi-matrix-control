import Foundation

/// In-memory stand-in for `MatrixClient` -- the Swift port of
/// `mock_client.py`. Powers demo mode and SwiftUI previews.
public actor MockMatrixClient: MatrixService {
    private var inputs: [Int: String] = [:]
    private var outputs: [Int: String] = [:]
    private var routes: [Int: Int] = [:]
    private var power: [Int: Bool] = [:]
    private var edid: [Int: Int] = [:]
    private var arc = AudioSource.off
    private var extraction = AudioSource.outA
    private let latency: Duration

    public init(latency: Duration = .milliseconds(150)) {
        self.latency = latency
        inputs = [1: "Windows", 2: "MacBook", 3: "AppleTv", 4: "MacMini"]
        outputs = [1: "Left", 2: "Right"]
        routes = [1: 3, 2: 3]
        power = [1: true, 2: true]
        edid = [1: 15, 2: 1, 3: 2, 4: 15]
    }

    private func simulateLatency() async {
        try? await Task.sleep(for: latency)
    }

    private func reset() {
        inputs = [1: "Windows", 2: "MacBook", 3: "AppleTv", 4: "MacMini"]
        outputs = [1: "Left", 2: "Right"]
        routes = [1: 3, 2: 3]
        power = [1: true, 2: true]
        edid = [1: 15, 2: 1, 3: 2, 4: 15]
        arc = .off
        extraction = .outA
    }

    public func state() async throws -> MatrixState {
        await simulateLatency()
        return MatrixState(
            device: .init(ip: "192.168.17.238", account: "admin", firmware: "V0.0.11 (demo)", userGroup: "0"),
            inputs: (1...4).map { i in
                .init(index: i, name: inputs[i]!, edidPreset: edid[i]!, edidDetail: edidPresets[edid[i]!])
            },
            outputs: (1...2).map { i in
                .init(index: i, name: outputs[i]!, inputIndex: routes[i]!, power: power[i]!)
            },
            arc: arc,
            extraction: extraction
        )
    }

    public func setRoute(output: Int, input: Int) async throws {
        try validateRoute(output: output, input: input)
        await simulateLatency()
        routes[output] = input
    }

    public func setOutputPower(output: Int, on: Bool) async throws {
        guard (1...2).contains(output) else { throw MatrixError("output must be 1 or 2") }
        await simulateLatency()
        power[output] = on
    }

    public func rename(_ kind: PortKind, index: Int, name: String) async throws {
        try validateName(name)
        await simulateLatency()
        switch kind {
        case .input: inputs[index] = name
        case .output: outputs[index] = name
        }
    }

    public func setEDID(input: Int, preset: Int) async throws {
        try validateEDID(input: input, preset: preset)
        await simulateLatency()
        edid[input] = preset
    }

    public func setAudio(_ mode: AudioMode, source: AudioSource) async throws {
        await simulateLatency()
        switch mode {
        case .arc: arc = source
        case .extraction: extraction = source
        }
    }

    public func setNetwork(ip: String, mask: String, gateway: String) async throws {
        try validateNetwork(ip: ip, mask: mask, gateway: gateway)
        await simulateLatency()
    }

    public func setCredentials(user: String, password: String) async throws {
        try validateCredentials(user: user, password: password)
        await simulateLatency()
    }

    public func reboot() async throws {
        await simulateLatency()
    }

    public func factoryReset() async throws {
        await simulateLatency()
        reset()
    }
}
