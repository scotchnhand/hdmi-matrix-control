import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MatrixAPIError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int, String)
    case invalidBaseURL

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The control service returned an invalid response."
        case let .httpStatus(status, message):
            return message.isEmpty ? "The control service returned HTTP \(status)." : message
        case .invalidBaseURL:
            return "Enter a valid HTTP or HTTPS control-service URL."
        }
    }
}

/// Actor-isolated client for the existing local web-app API.
public actor MatrixAPIClient {
    public let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func fetchState() async throws -> MatrixState {
        try await request(path: "api/state", method: "GET")
    }

    public func route(output: Int, input: Int) async throws -> MatrixState {
        try await request(path: "api/route", method: "POST", payload: [
            "output": output,
            "input": input,
        ])
    }

    public func setOutputPower(output: Int, on: Bool) async throws -> MatrixState {
        try await request(path: "api/output-power", method: "POST", payload: [
            "output": output,
            "on": on,
        ])
    }

    public func setAudio(mode: String, value: Int) async throws -> MatrixState {
        try await request(path: "api/audio", method: "POST", payload: [
            "mode": mode,
            "value": value,
        ])
    }

    public func setEDID(input: Int, preset: Int) async throws -> MatrixState {
        try await request(path: "api/edid", method: "POST", payload: [
            "input": input,
            "preset": preset,
        ])
    }

    private func request(path: String, method: String, payload: [String: Any]? = nil) async throws -> MatrixState {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MatrixAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorBody.self, from: data).error) ?? ""
            throw MatrixAPIError.httpStatus(httpResponse.statusCode, message)
        }

        return try decoder.decode(MatrixState.self, from: data)
    }

    private struct APIErrorBody: Decodable {
        let error: String
    }
}
