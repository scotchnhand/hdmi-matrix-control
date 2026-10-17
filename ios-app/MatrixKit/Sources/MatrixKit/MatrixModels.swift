import Foundation

public struct MatrixDevice: Codable, Equatable, Sendable {
    public let ip: String
    public let account: String
    public let firmware: String
    public let userGroup: String

    public init(ip: String, account: String, firmware: String, userGroup: String) {
        self.ip = ip
        self.account = account
        self.firmware = firmware
        self.userGroup = userGroup
    }

    private enum CodingKeys: String, CodingKey {
        case ip, account, firmware
        case userGroup = "user_group"
    }
}

public struct MatrixInput: Codable, Equatable, Identifiable, Sendable {
    public let index: Int
    public let name: String
    public let edidPreset: Int
    public let edidDetail: String

    public var id: Int { index }

    public init(index: Int, name: String, edidPreset: Int, edidDetail: String) {
        self.index = index
        self.name = name
        self.edidPreset = edidPreset
        self.edidDetail = edidDetail
    }

    private enum CodingKeys: String, CodingKey {
        case index, name
        case edidPreset = "edid_preset"
        case edidDetail = "edid_detail"
    }
}

public struct MatrixOutput: Codable, Equatable, Identifiable, Sendable {
    public let index: Int
    public let name: String
    public let inputIndex: Int
    public let power: Bool

    public var id: Int { index }

    public init(index: Int, name: String, inputIndex: Int, power: Bool) {
        self.index = index
        self.name = name
        self.inputIndex = inputIndex
        self.power = power
    }

    private enum CodingKeys: String, CodingKey {
        case index, name, power
        case inputIndex = "input_index"
    }
}

public struct MatrixAudioRoute: Codable, Equatable, Sendable {
    public let value: Int
    public let label: String

    public init(value: Int, label: String) {
        self.value = value
        self.label = label
    }
}

public struct MatrixAudio: Codable, Equatable, Sendable {
    public let arc: MatrixAudioRoute
    public let extraction: MatrixAudioRoute

    public init(arc: MatrixAudioRoute, extraction: MatrixAudioRoute) {
        self.arc = arc
        self.extraction = extraction
    }
}

public struct MatrixEDIDPreset: Codable, Equatable, Identifiable, Sendable {
    public let index: Int
    public let name: String

    public var id: Int { index }

    public init(index: Int, name: String) {
        self.index = index
        self.name = name
    }
}

public struct MatrixState: Codable, Equatable, Sendable {
    public let device: MatrixDevice
    public let inputs: [MatrixInput]
    public let outputs: [MatrixOutput]
    public let audio: MatrixAudio
    public let edidPresets: [MatrixEDIDPreset]

    public init(
        device: MatrixDevice,
        inputs: [MatrixInput],
        outputs: [MatrixOutput],
        audio: MatrixAudio,
        edidPresets: [MatrixEDIDPreset]
    ) {
        self.device = device
        self.inputs = inputs
        self.outputs = outputs
        self.audio = audio
        self.edidPresets = edidPresets
    }

    private enum CodingKeys: String, CodingKey {
        case device, inputs, outputs, audio
        case edidPresets = "edid_presets"
    }
}
