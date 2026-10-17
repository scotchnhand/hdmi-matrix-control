import SwiftUI

@main
struct MatrixControlMacApp: App {
    @StateObject private var model = MatrixDashboardModel()

    var body: some Scene {
        WindowGroup("HDMI Matrix") {
            MatrixDashboardView(model: model)
                .frame(minWidth: 620, minHeight: 720)
                .onAppear { if model.state == nil { model.connect() } }
        }
    }
}
