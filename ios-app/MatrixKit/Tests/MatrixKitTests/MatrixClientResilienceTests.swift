import Foundation
import XCTest
@testable import MatrixKit

/// Wraps `FakeDevice` and fails the next requests with queued `URLError`s,
/// recording the timeout each request carried.
final class FlakyDevice: @unchecked Sendable {
    let device = FakeDevice()
    private let lock = NSLock()
    private var queuedFailures: [URLError.Code] = []
    private(set) var timeouts: [TimeInterval] = []
    private(set) var attempts: [String] = []

    func failNext(_ codes: URLError.Code...) {
        lock.withLock { queuedFailures = codes }
    }

    func handle(_ request: URLRequest) async throws -> String {
        let failure: URLError.Code? = lock.withLock {
            timeouts.append(request.timeoutInterval)
            attempts.append(request.url!.path.trimmingCharacters(in: .decimalDigits))
            return queuedFailures.isEmpty ? nil : queuedFailures.removeFirst()
        }
        if let failure { throw URLError(failure) }
        return try await device.handle(request)
    }

    func client(timeout: TimeInterval = 4, firstContactTimeout: TimeInterval = 2) -> MatrixClient {
        MatrixClient(
            host: "matrix.test",
            timeout: timeout,
            firstContactTimeout: firstContactTimeout,
            transport: { try await self.handle($0) }
        )
    }

    func attemptCount(_ path: String) -> Int {
        lock.withLock { attempts.filter { $0 == path }.count }
    }
}

final class MatrixClientResilienceTests: XCTestCase {
    func testFirstContactUsesShortTimeoutThenNormal() async throws {
        let flaky = FlakyDevice()
        _ = try await flaky.client().state()
        // The login is the first request; everything after it has connected.
        XCTAssertEqual(flaky.timeouts.first, 2)
        XCTAssertEqual(Set(flaky.timeouts.dropFirst()), [4])
    }

    func testFirstContactTimeoutNeverExceedsNormalTimeout() async throws {
        let flaky = FlakyDevice()
        _ = try await flaky.client(timeout: 1, firstContactTimeout: 5).state()
        XCTAssertEqual(Set(flaky.timeouts), [1])
    }

    func testRetriesReadOnceAfterDroppedConnection() async throws {
        let flaky = FlakyDevice()
        let client = flaky.client()
        _ = try await client.state() // connect and log in

        flaky.failNext(.networkConnectionLost)
        let state = try await client.state()

        XCTAssertEqual(state.outputs.count, 2)
        XCTAssertEqual(flaky.attemptCount("/video.get"), 3) // 1 warm-up + failed + retry
    }

    func testGivesUpAfterOneRetry() async throws {
        let flaky = FlakyDevice()
        let client = flaky.client()
        _ = try await client.state()

        flaky.failNext(.networkConnectionLost, .networkConnectionLost)
        do {
            _ = try await client.state()
            XCTFail("expected a connectivity error")
        } catch let error as MatrixError {
            XCTAssertTrue(error.isConnectivity)
            XCTAssertTrue(error.message.contains("dropped the connection"), error.message)
        }
    }

    func testCommandsAreNotRetried() async throws {
        let flaky = FlakyDevice()
        let client = flaky.client()
        _ = try await client.state()

        flaky.failNext(.networkConnectionLost)
        do {
            try await client.setRoute(output: 1, input: 2)
            XCTFail("expected a connectivity error")
        } catch let error as MatrixError {
            XCTAssertTrue(error.isConnectivity)
        }
        XCTAssertEqual(flaky.attemptCount("/video_set"), 1)
    }

    func testTimeoutIsDescribedInPlainLanguage() async {
        let flaky = FlakyDevice()
        flaky.failNext(.timedOut)
        await assertMessage(flaky, contains: "slow to respond")
    }

    func testUnreachableHostPointsToSettings() async {
        let flaky = FlakyDevice()
        flaky.failNext(.cannotConnectToHost)
        await assertMessage(flaky, contains: "Check the address in Settings")
    }

    func testNoWiFiIsDescribedInPlainLanguage() async {
        let flaky = FlakyDevice()
        flaky.failNext(.notConnectedToInternet)
        await assertMessage(flaky, contains: "isn't on Wi-Fi")
    }

    private func assertMessage(
        _ flaky: FlakyDevice, contains fragment: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await flaky.client().state()
            XCTFail("expected a connectivity error", file: file, line: line)
        } catch let error as MatrixError {
            XCTAssertTrue(error.isConnectivity, file: file, line: line)
            XCTAssertTrue(error.message.contains(fragment), error.message, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }
}
