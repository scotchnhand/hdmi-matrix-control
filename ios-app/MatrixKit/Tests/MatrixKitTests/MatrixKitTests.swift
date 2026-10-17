import XCTest
@testable import MatrixKit

final class MatrixKitTests: XCTestCase {
    func testDecodesWebStateShape() throws {
        let data = #"""
        {
          "device": {"ip":"192.168.1.168","account":"admin","firmware":"V0.0.11","user_group":"0"},
          "inputs": [{"index":1,"name":"Apple TV","edid_preset":2,"edid_detail":"1080p"}],
          "outputs": [{"index":1,"name":"Living Room","input_index":1,"power":true}],
          "audio": {"arc":{"value":0,"label":"Off"},"extraction":{"value":1,"label":"Output 1"}},
          "edid_presets": [{"index":2,"name":"1080p"}]
        }
        """#.data(using: .utf8)!

        let state = try JSONDecoder().decode(MatrixState.self, from: data)

        XCTAssertEqual(state.device.ip, "192.168.1.168")
        XCTAssertEqual(state.inputs.first?.edidPreset, 2)
        XCTAssertEqual(state.outputs.first?.inputIndex, 1)
        XCTAssertTrue(state.outputs.first?.power == true)
    }

    func testAPIClientBuildsRelativeEndpointURL() async throws {
        let url = URL(string: "http://matrix-host:8765")!
        let client = MatrixAPIClient(baseURL: url)
        let baseURL = await client.baseURL
        XCTAssertEqual(baseURL.absoluteString, "http://matrix-host:8765")
    }
}
