#if canImport(WatchConnectivity)
import Foundation
import MatrixKit
import WatchConnectivity

@MainActor
final class MatrixWatchConnectivity: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var isReachable = false

    private weak var model: MatrixDashboardModel?
    private var session: WCSession?

    func activate(model: MatrixDashboardModel) {
        self.model = model
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        session.delegate = self
        self.session = session
        session.activate()
        isReachable = session.isReachable
    }

    func publish(snapshot: MatrixState) {
        guard let session, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? session.updateApplicationContext(["state": data])
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.isReachable = session.isReachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.isReachable = session.isReachable
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor [weak self] in
            guard let self, let model else {
                replyHandler(["error": "The iPhone app is not ready."])
                return
            }

            switch message["action"] as? String {
            case "state":
                guard let snapshot = model.state,
                      let data = try? JSONEncoder().encode(snapshot) else {
                    replyHandler(["error": "No matrix state is available yet."])
                    return
                }
                replyHandler(["state": data])
            case "route":
                guard let output = message["output"] as? Int,
                      let input = message["input"] as? Int else {
                    replyHandler(["error": "Invalid route command."])
                    return
                }
                model.setRoute(output: output, input: input)
                replyHandler(["ok": true])
            case "power":
                guard let output = message["output"] as? Int,
                      let on = message["on"] as? Bool else {
                    replyHandler(["error": "Invalid power command."])
                    return
                }
                model.setOutputPower(output: output, on: on)
                replyHandler(["ok": true])
            default:
                replyHandler(["error": "Unknown watch command."])
            }
        }
    }
}
#endif
