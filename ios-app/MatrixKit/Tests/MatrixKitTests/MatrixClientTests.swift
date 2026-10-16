import Foundation
import XCTest
@testable import MatrixKit

// Real responses captured from the device -- kept verbatim (trailing comma
// and all) and identical to the Python suite's fixtures.
let realVideo = """
VideoCallback({"o1":"2",            "o2":"2",            "s1":"1",            "s2":"1",            "group":"0",            "account":"admin",            "ip":"192.168.17.238",            "port":"001011",            "in1":"Windows",\t\t\t      "in2":"MacBook",\t\t\t      "in3":"AppleTv",\t\t\t      "in4":"MacMini",\t\t\t      "out1":"Left",\t\t\t      "out2":"Right",\t\t\t      "ver":"V0.0.11",            });
"""
let realAudio = #"AudioCallback({"arc":"0",            "ext":"1",            });"#
let realEDID = """
EdidCallback({"i1":"15",            "i2":"1",            "i3":"2",            "i4":"15",            "e1":"1920x1080P@60 LPCM:2.0",            "e2":"1920x1200P@60 LPCM:2.0",            "e3":"1920x1080P@60 LPCM:2.0",            "port":"001011",            });
"""
let loginOK = #"settingsLoginCallback({"status":"0","str":"",});"#
let loginFail = #"settingsLoginCallback({"status":"6","str":"Invalid user or password",});"#

/// Records requests and answers from a canned route table.
final class FakeDevice: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [(method: String, path: String, body: String?)] = []
    private(set) var urls: [URL] = []
    var login = loginOK

    func handle(_ request: URLRequest) async throws -> String {
        let path = request.url!.path.trimmingCharacters(in: .decimalDigits)
        let body = request.httpBody.map { String(decoding: $0, as: UTF8.self) }
        lock.withLock {
            requests.append((request.httpMethod ?? "GET", path, body))
            urls.append(request.url!)
        }
        switch path {
        case "/login.set": return login
        case "/video.get": return realVideo
        case "/audio.get": return realAudio
        case "/edid.get": return realEDID
        default: return ""
        }
    }

    var commandBodies: [String] {
        lock.withLock { requests.filter { $0.path != "/login.set" }.compactMap(\.body) }
    }

    func client() -> MatrixClient {
        MatrixClient(host: "matrix.test", transport: { try await self.handle($0) })
    }
}

final class JSONPTests: XCTestCase {
    func testParsesRealVideo() throws {
        let data = try JSONP.parse(realVideo, callback: "VideoCallback")
        XCTAssertEqual(data["o1"], "2")
        XCTAssertEqual(data["in3"], "AppleTv")
        XCTAssertEqual(data["ver"], "V0.0.11")
    }

    func testParsesRealAudio() throws {
        XCTAssertEqual(try JSONP.parse(realAudio, callback: "AudioCallback"), ["arc": "0", "ext": "1"])
    }

    func testParsesWithoutTrailingComma() throws {
        let data = try JSONP.parse(#"AudioCallback({"arc":"1","ext":"2"});"#, callback: "AudioCallback")
        XCTAssertEqual(data, ["arc": "1", "ext": "2"])
    }

    func testRejectsWrongCallback() {
        XCTAssertThrowsError(try JSONP.parse(realVideo, callback: "WrongCallback"))
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try JSONP.parse("<html>not json</html>", callback: "VideoCallback"))
    }
}

final class MatrixClientTests: XCTestCase {
    func testStateIsNormalized() async throws {
        let state = try await FakeDevice().client().state()
        XCTAssertEqual(state.inputs.map(\.name), ["Windows", "MacBook", "AppleTv", "MacMini"])
        XCTAssertEqual(state.outputs.map(\.name), ["Left", "Right"])
        XCTAssertEqual(state.outputs[0].inputIndex, 3) // o1 = "2", 0-indexed
        XCTAssertTrue(state.outputs[0].power)
        XCTAssertEqual(state.inputs[1].edidPreset, 1)
        XCTAssertEqual(state.inputs[1].edidDetail, "1920x1200P@60 LPCM:2.0")
        XCTAssertEqual(state.arc, .off)
        XCTAssertEqual(state.extraction, .outA)
        XCTAssertEqual(state.device.firmware, "V0.0.11")
    }

    func testLogsInOnceWithBase64Credentials() async throws {
        let device = FakeDevice()
        let client = device.client()
        _ = try await client.state()
        _ = try await client.state()
        let logins = device.requests.filter { $0.path == "/login.set" }
        XCTAssertEqual(logins.count, 1)
        XCTAssertEqual(logins.first?.body, "#login id=YWRtaW4= psd=YWRtaW4=")
    }

    func testLoginFailureSurfacesDeviceMessage() async {
        let device = FakeDevice()
        device.login = loginFail
        do {
            _ = try await device.client().state()
            XCTFail("expected login failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Invalid user or password")
        }
    }

    func testCommandBodiesMatchProtocol() async throws {
        let device = FakeDevice()
        let client = device.client()
        try await client.setRoute(output: 1, input: 3)
        try await client.setOutputPower(output: 2, on: false)
        try await client.rename(.input, index: 2, name: "PS5")
        try await client.setEDID(input: 4, preset: 13)
        try await client.setAudio(.arc, source: .outB)
        try await client.setAudio(.extraction, source: .outA)
        try await client.reboot()
        XCTAssertEqual(device.commandBodies, [
            "#video_d out1 matrix=2",
            "#video_d out2 onoff=0",
            "#port in2 name=PS5",
            "#edid_d in4 data=13",
            "#audio_d arc=2",
            "#audio_d dec=1",
            "#power start=1",
        ])
    }

    func testValidationRejectsBeforeSending() async {
        let device = FakeDevice()
        let client = device.client()
        await XCTAssertThrowsAsync(try await client.setRoute(output: 3, input: 1))
        await XCTAssertThrowsAsync(try await client.setRoute(output: 1, input: 5))
        await XCTAssertThrowsAsync(try await client.rename(.output, index: 1, name: "no spaces"))
        await XCTAssertThrowsAsync(try await client.setEDID(input: 1, preset: 16))
        await XCTAssertThrowsAsync(try await client.setCredentials(user: "abc", password: "abcdef"))
        await XCTAssertThrowsAsync(try await client.setNetwork(ip: "300.1.1.1", mask: "255.255.255.0", gateway: "1.1.1.1"))
        XCTAssertTrue(device.requests.isEmpty)
    }

    func testConcurrentCallsAreSerialized() async throws {
        let device = FakeDevice()
        let client = device.client()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { _ = try await client.state() }
            }
            try await group.waitForAll()
        }
        // Each state() is video, audio, edid in order; serialization means
        // the triples never interleave.
        let paths = device.requests.map(\.path).filter { $0 != "/login.set" }
        XCTAssertEqual(paths, Array(repeating: ["/video.get", "/audio.get", "/edid.get"], count: 5).flatMap { $0 })
    }
}

final class HostTests: XCTestCase {
    func testNormalizesPastedURLs() {
        XCTAssertEqual(MatrixClient.normalizeHost("http://192.168.1.168/"), "192.168.1.168")
        XCTAssertEqual(MatrixClient.normalizeHost("  matrix.local "), "matrix.local")
        XCTAssertEqual(MatrixClient.normalizeHost("https://matrix.local:8080/index.html?x=1"), "matrix.local:8080")
        XCTAssertNil(MatrixClient.normalizeHost("   "))
        XCTAssertNil(MatrixClient.normalizeHost("my matrix"))
    }

    func testClientUsesNormalizedHost() async throws {
        let device = FakeDevice()
        let client = MatrixClient(host: "http://matrix.test/", transport: { try await device.handle($0) })
        _ = try await client.state()
        XCTAssertEqual(device.urls.first?.host, "matrix.test")
    }

    func testUnreachableDeviceIsConnectivityError() async {
        struct Offline: Error {}
        let client = MatrixClient(host: "matrix.test", transport: { _ in throw Offline() })
        do {
            _ = try await client.state()
            XCTFail("expected failure")
        } catch let error as MatrixError {
            XCTAssertTrue(error.isConnectivity)
        } catch {
            XCTFail("expected MatrixError, got \(error)")
        }
    }

    func testValidationErrorIsNotConnectivity() async {
        do {
            try await FakeDevice().client().setRoute(output: 9, input: 1)
            XCTFail("expected failure")
        } catch let error as MatrixError {
            XCTAssertFalse(error.isConnectivity)
        } catch {
            XCTFail("expected MatrixError")
        }
    }
}

final class ValidationTests: XCTestCase {
    func testPortNames() {
        XCTAssertTrue(Validation.isValidPortName("AppleTv"))
        XCTAssertTrue(Validation.isValidPortName("PS5"))
        XCTAssertFalse(Validation.isValidPortName("TV"))
        XCTAssertFalse(Validation.isValidPortName("Apple TV"))
        XCTAssertFalse(Validation.isValidPortName("Ünicode"))
        XCTAssertFalse(Validation.isValidPortName(String(repeating: "a", count: 16)))
    }

    func testIPv4() {
        XCTAssertTrue(Validation.isValidIPv4("192.168.1.168"))
        XCTAssertFalse(Validation.isValidIPv4("192.168.1"))
        XCTAssertFalse(Validation.isValidIPv4("192.168.1.256"))
        XCTAssertFalse(Validation.isValidIPv4("a.b.c.d"))
    }
}

final class MockMatrixClientTests: XCTestCase {
    func testMockRoundTrip() async throws {
        let mock = MockMatrixClient(latency: .zero)
        try await mock.setRoute(output: 2, input: 1)
        try await mock.rename(.output, index: 1, name: "Projector")
        var state = try await mock.state()
        XCTAssertEqual(state.outputs[1].inputIndex, 1)
        XCTAssertEqual(state.outputs[0].name, "Projector")
        try await mock.factoryReset()
        state = try await mock.state()
        XCTAssertEqual(state.outputs[0].name, "Left")
    }
}

func XCTAssertThrowsAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected an error", file: file, line: line)
    } catch {}
}
