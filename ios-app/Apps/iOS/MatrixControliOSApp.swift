import SwiftUI

@main
struct MatrixControliOSApp: App {
    @StateObject private var model = MatrixDashboardModel()
    @StateObject private var watchSession = MatrixWatchConnectivity()

    var body: some Scene {
        WindowGroup {
            MatrixDashboardView(model: model)
                .onAppear {
                    watchSession.activate(model: model)
                    model.stateDidChange = { snapshot in
                        watchSession.publish(snapshot: snapshot)
                    }
                    if model.state == nil { model.connect() }
                }
        }
    }
}
