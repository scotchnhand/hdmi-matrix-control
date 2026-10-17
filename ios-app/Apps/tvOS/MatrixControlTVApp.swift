import SwiftUI

@main
struct MatrixControlTVApp: App {
    @StateObject private var model = MatrixDashboardModel()

    var body: some Scene {
        WindowGroup {
            MatrixDashboardView(model: model)
                .onAppear { if model.state == nil { model.connect() } }
        }
    }
}
