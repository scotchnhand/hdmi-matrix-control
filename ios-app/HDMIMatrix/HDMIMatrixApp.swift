import SwiftUI

@main
struct HDMIMatrixApp: App {
    @State private var settings = ConnectionSettings.forLaunch()
    @State private var store = MatrixStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(store)
                .task(id: settings.revision) {
                    store.connect(using: settings)
                }
        }
    }
}
