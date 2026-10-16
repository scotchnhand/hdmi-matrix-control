import Foundation

/// Parses the firmware's JSONP-ish responses, e.g.
/// `VideoCallback({"o1":"2", ... ,});` -- note the trailing comma before
/// `}`, which the firmware emits on every endpoint.
enum JSONP {
    static func parse(_ text: String, callback: String) throws -> [String: String] {
        var inner = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "\(callback)("
        guard inner.hasPrefix(prefix) else {
            throw MatrixError("Unexpected response from matrix: \(inner.prefix(160))")
        }
        inner.removeFirst(prefix.count)
        if inner.hasSuffix(");") {
            inner.removeLast(2)
        } else if inner.hasSuffix(")") {
            inner.removeLast()
        }
        inner = inner.replacingOccurrences(of: #",\s*\}"#, with: "}", options: .regularExpression)

        guard let data = inner.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw MatrixError("Could not parse matrix response: \(text.prefix(160))")
        }
        // Every value the firmware sends is a string, but be lenient.
        return object.mapValues { value in
            (value as? String) ?? "\(value)"
        }
    }
}

extension MatrixState {
    /// Aggregate the three raw state endpoints into one normalized state,
    /// mirroring `MatrixClient.get_state()` in the Python clients.
    init(video: [String: String], audio: [String: String], edid: [String: String]) {
        func int(_ dict: [String: String], _ key: String) -> Int {
            Int(dict[key] ?? "") ?? 0
        }

        device = Device(
            ip: video["ip"] ?? "",
            account: video["account"] ?? "",
            firmware: video["ver"] ?? "",
            userGroup: video["group"] ?? "0"
        )

        inputs = (1...4).map { i in
            let preset = int(edid, "i\(i)")
            return Input(
                index: i,
                name: video["in\(i)"] ?? "Input \(i)",
                edidPreset: preset,
                edidDetail: edid["e\(preset + 1)"] ?? ""
            )
        }

        outputs = (1...2).map { i in
            Output(
                index: i,
                name: video["out\(i)"] ?? "Output \(i)",
                inputIndex: int(video, "o\(i)") + 1, // device is 0-indexed
                power: video["s\(i)"] == "1"
            )
        }

        arc = AudioSource(rawValue: int(audio, "arc")) ?? .off
        extraction = AudioSource(rawValue: int(audio, "ext")) ?? .off
    }
}
