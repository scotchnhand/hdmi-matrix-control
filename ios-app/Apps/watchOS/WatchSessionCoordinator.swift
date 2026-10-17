#if canImport(WatchConnectivity)
import Foundation
import MatrixKit
import WatchConnectivity

@MainActor
final class WatchSessionCoordinator: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var state: MatrixState?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isReachable = false

    private var session: WCSession?

    func activate() {
        guard WCSession.isSupported() else {
            errorMessage = "Watch connectivity is unavailable."
            return
        }
        let session = WCSession.default
        session.delegate = self
        self.session = session
        session.activate()
        isReachable = session.isReachable
        if let data = session.receivedApplicationContext["state"] as? Data {
            decode(data)
        }
    }

    func refresh() {
        send(["action": "state"]) { [weak self] response in
            guard let data = response["state"] as? Data else {
                self?.errorMessage = response["error"] as? String
                return
            }
            self?.decode(data)
        }
    }

    func route(output: Int, input: Int) {
        send(["action": "route", "output": output, "input": input]) { [weak self] response in
            if let error = response["error"] as? String { self?.errorMessage = error }
            else { self?.refresh() }
        }
    }

    func setPower(output: Int, on: Bool) {
        send(["action": "power", "output": output, "on": on]) { [weak self] response in
            if let error = response["error"] as? String { self?.errorMessage = error }
            else { self?.refresh() }
        }
    }

    private func send(_ message: [String: Any], reply: @escaping ([String: Any]) -> Void) {
        guard let session, session.isReachable else {
            errorMessage = "Open HDMI Matrix on iPhone first."
            return
        }

        session.sendMessage(message, replyHandler: { response in
            Task { @MainActor in reply(response) }
        }, errorHandler: { error in
            Task { @MainActor [weak self] in self?.errorMessage = error.localizedDescription }
        })
    }

    private func decode(_ data: Data) {
        do {
            state = try JSONDecoder().decode(MatrixState.self, from: data)
            errorMessage = nil
        } catch {
            errorMessage = "The iPhone sent an unreadable state snapshot."
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.isReachable = session.isReachable
            if let error { self?.errorMessage = error.localizedDescription }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.isReachable = session.isReachable }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext["state"] as? Data else { return }
        Task { @MainActor [weak self] in self?.decode(data) }
    }
}
#endif
