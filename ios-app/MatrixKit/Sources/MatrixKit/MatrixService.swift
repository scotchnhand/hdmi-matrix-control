import Foundation

public struct MatrixError: LocalizedError, Equatable, Sendable {
    public var message: String
    /// True when the device couldn't be reached at all (as opposed to it
    /// rejecting a request, or input failing validation).
    public var isConnectivity: Bool

    public init(_ message: String, isConnectivity: Bool = false) {
        self.message = message
        self.isConnectivity = isConnectivity
    }

    public var errorDescription: String? { message }
}

/// Everything the UI can ask of a matrix. Implemented by `MatrixClient`
/// (the real device) and `MockMatrixClient` (demo mode / previews).
public protocol MatrixService: Sendable {
    func state() async throws -> MatrixState
    func setRoute(output: Int, input: Int) async throws
    func setOutputPower(output: Int, on: Bool) async throws
    func rename(_ kind: PortKind, index: Int, name: String) async throws
    func setEDID(input: Int, preset: Int) async throws
    func setAudio(_ mode: AudioMode, source: AudioSource) async throws
    func setNetwork(ip: String, mask: String, gateway: String) async throws
    func setCredentials(user: String, password: String) async throws
    func reboot() async throws
    func factoryReset() async throws
}

extension MatrixService {
    func validateRoute(output: Int, input: Int) throws {
        guard (1...2).contains(output) else { throw MatrixError("output must be 1 or 2") }
        guard (1...4).contains(input) else { throw MatrixError("input must be 1-4") }
    }

    func validateName(_ name: String) throws {
        guard Validation.isValidPortName(name) else {
            throw MatrixError("Name must be 3-15 letters, numbers, or underscores")
        }
    }

    func validateEDID(input: Int, preset: Int) throws {
        guard (1...4).contains(input) else { throw MatrixError("input must be 1-4") }
        guard edidPresets.indices.contains(preset) else {
            throw MatrixError("preset must be 0-\(edidPresets.count - 1)")
        }
    }

    func validateCredentials(user: String, password: String) throws {
        guard Validation.isValidCredential(user), Validation.isValidCredential(password) else {
            throw MatrixError("Username/password must be 5-15 letters, numbers, or underscores")
        }
    }

    func validateNetwork(ip: String, mask: String, gateway: String) throws {
        guard [ip, mask, gateway].allSatisfy(Validation.isValidIPv4) else {
            throw MatrixError("IP, mask, and gateway must be dotted IPv4 addresses")
        }
    }
}
