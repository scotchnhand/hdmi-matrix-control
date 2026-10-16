import Foundation

/// Normalized matrix state -- the same shape `MatrixClient.get_state()`
/// returns in the Python clients (see docs/PROTOCOL.md).
public struct MatrixState: Equatable, Sendable {
    public struct Device: Equatable, Sendable {
        public var ip: String
        public var account: String
        public var firmware: String
        public var userGroup: String
    }

    public struct Input: Equatable, Sendable, Identifiable {
        public var index: Int
        public var name: String
        public var edidPreset: Int
        public var edidDetail: String
        public var id: Int { index }
    }

    public struct Output: Equatable, Sendable, Identifiable {
        public var index: Int
        public var name: String
        /// 1-based input currently routed to this output.
        public var inputIndex: Int
        public var power: Bool
        public var id: Int { index }
    }

    public var device: Device
    public var inputs: [Input]
    public var outputs: [Output]
    public var arc: AudioSource
    public var extraction: AudioSource

    public func input(_ index: Int) -> Input? {
        inputs.first { $0.index == index }
    }
}

/// Which output feeds ARC / audio extraction.
public enum AudioSource: Int, CaseIterable, Sendable, Identifiable {
    case off = 0
    case outA = 1
    case outB = 2

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .off: "Off"
        case .outA: "Out-A"
        case .outB: "Out-B"
        }
    }
}

public enum AudioMode: String, Sendable {
    case arc
    case extraction
}

public enum PortKind: String, Sendable {
    case input = "in"
    case output = "out"
}

/// Fixed firmware list -- not returned by the device.
public let edidPresets: [String] = [
    "Mixer",
    "1920x1200 2CH",
    "1080P 2CH",
    "1080P 6CH",
    "1080P 8CH",
    "4K 420 2CH",
    "4K 420 6CH",
    "4K 420 8CH",
    "4K 444 2CH",
    "4K 444 6CH",
    "4K 444 8CH",
    "4K HDR 10Bit 2CH",
    "4K HDR 10Bit 6CH",
    "4K HDR 10Bit 8CH",
    "Copy Out-A",
    "Copy Out-B",
]

public enum Validation {
    /// Port names: `^[a-zA-Z0-9_]{3,15}$`
    public static func isValidPortName(_ name: String) -> Bool {
        matches(name, min: 3, max: 15)
    }

    /// Credentials: `^[a-zA-Z0-9_]{5,15}$`
    public static func isValidCredential(_ value: String) -> Bool {
        matches(value, min: 5, max: 15)
    }

    public static func isValidIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            !part.isEmpty && part.count <= 3 && part.allSatisfy(\.isASCIIDigit) && Int(part)! <= 255
        }
    }

    private static func matches(_ value: String, min: Int, max: Int) -> Bool {
        (min...max).contains(value.count)
            && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
