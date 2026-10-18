import Foundation
import XCTest
@testable import MatrixKit

/// Runs the shared cases in docs/protocol-fixtures.json -- the same file the
/// Python suites (tests/test_protocol_fixtures.py) run -- so the Swift and
/// Python clients can't drift apart.
final class ProtocolFixtureTests: XCTestCase {
    private static let fixtures: [String: Any] = {
        // Found relative to this source file, so it works under both
        // `swift test` and xcodebuild without bundling a resource.
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appendingPathComponent("docs/protocol-fixtures.json")
            if let data = try? Data(contentsOf: candidate),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return object
            }
            dir.deleteLastPathComponent()
        }
        fatalError("docs/protocol-fixtures.json not found above \(#filePath)")
    }()

    private typealias Case = [String: Any]

    private func cases(_ key: String) -> [Case] {
        Self.fixtures[key] as? [Case] ?? []
    }

    /// Maps a fixture call onto the Swift API. Arguments the Swift types
    /// can't even represent (e.g. an audio source of 3) count as rejected.
    private func perform(_ call: String, _ args: [String: Any], on client: MatrixClient) async throws {
        func int(_ key: String) -> Int { args[key] as? Int ?? -1 }
        func string(_ key: String) -> String { args[key] as? String ?? "" }

        switch call {
        case "set_route":
            try await client.setRoute(output: int("output"), input: int("input"))
        case "set_output_power":
            try await client.setOutputPower(output: int("output"), on: args["on"] as? Bool ?? false)
        case "rename":
            guard let kind = PortKind(rawValue: string("kind")) else { throw MatrixError("bad kind") }
            try await client.rename(kind, index: int("index"), name: string("name"))
        case "set_edid":
            try await client.setEDID(input: int("input"), preset: int("preset"))
        case "set_audio":
            guard let mode = AudioMode(rawValue: string("mode")),
                  let source = AudioSource(rawValue: int("value")) else { throw MatrixError("bad audio") }
            try await client.setAudio(mode, source: source)
        case "set_network":
            try await client.setNetwork(ip: string("ip"), mask: string("mask"), gateway: string("gw"))
        case "set_credentials":
            try await client.setCredentials(user: string("user"), password: string("password"))
        case "reboot":
            try await client.reboot()
        case "factory_reset":
            try await client.factoryReset()
        default:
            XCTFail("Fixture call \(call) has no Swift mapping")
        }
    }

    func testCommandsProduceExpectedWireStrings() async throws {
        let commands = cases("commands")
        XCTAssertFalse(commands.isEmpty)
        for command in commands {
            let call = command["call"] as! String
            let device = FakeDevice()
            try await perform(call, command["args"] as! [String: Any], on: device.client())
            let sent = device.requests.filter { $0.path != "/login.set" }
            XCTAssertEqual(sent.count, 1, "\(call) \(command["args"]!)")
            XCTAssertEqual(sent.first?.method, "POST", call)
            XCTAssertEqual(sent.first?.path, "/" + (command["page"] as! String), call)
            XCTAssertEqual(sent.first?.body, command["body"] as? String, call)
        }
    }

    func testRejectionsSendNothing() async {
        let rejections = cases("rejections")
        XCTAssertFalse(rejections.isEmpty)
        for rejection in rejections {
            let call = rejection["call"] as! String
            let device = FakeDevice()
            do {
                try await perform(call, rejection["args"] as! [String: Any], on: device.client())
                XCTFail("\(call) \(rejection["args"]!) should have been rejected")
            } catch {}
            XCTAssertEqual(device.commandBodies, [], "\(call) \(rejection["args"]!) sent a command")
        }
    }

    func testStateNormalization() async throws {
        let responses = Self.fixtures["responses"] as! [String: String]
        XCTAssertEqual(responses["video"], realVideo, "fixture video response differs from MatrixClientTests")
        XCTAssertEqual(responses["audio"], realAudio)
        XCTAssertEqual(responses["edid"], realEDID)

        let state = try await FakeDevice().client().state()
        let expected = Self.fixtures["state"] as! [String: Any]
        XCTAssertEqual(state.device.firmware, expected["firmware"] as? String)

        let inputs = (expected["inputs"] as! [[String: Any]]).map {
            "\($0["index"]!)|\($0["name"]!)|\($0["edid_preset"]!)"
        }
        XCTAssertEqual(state.inputs.map { "\($0.index)|\($0.name)|\($0.edidPreset)" }, inputs)

        let outputs = (expected["outputs"] as! [[String: Any]]).map {
            "\($0["index"]!)|\($0["name"]!)|\($0["input_index"]!)|\($0["power"] as! Bool)"
        }
        XCTAssertEqual(state.outputs.map { "\($0.index)|\($0.name)|\($0.inputIndex)|\($0.power)" }, outputs)

        let audio = expected["audio"] as! [String: Int]
        XCTAssertEqual(state.arc.rawValue, audio["arc"])
        XCTAssertEqual(state.extraction.rawValue, audio["extraction"])
    }
}
