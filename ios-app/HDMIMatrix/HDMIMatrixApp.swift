import SwiftUI

@main
struct HDMIMatrixApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = ConnectionSettings.forLaunch()
    @State private var appearance = AppearanceSettings.forLaunch()
    @State private var store = MatrixStore()

    var body: some Scene {
        WindowGroup {
            let holidayColors = appearance.holiday.flatMap(HolidayColors.init)
            ContentView()
                .environment(settings)
                .environment(appearance)
                .environment(store)
                .environment(\.holidayColors, holidayColors)
                // nil keeps the asset catalog's accent color.
                .tint(holidayColors?.accent)
                .task(id: settings.revision) {
                    store.connect(using: settings)
                }
                // "Auto" follows the calendar: recheck the day whenever the
                // app comes forward or midnight passes while it's open.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { appearance.refreshDay() }
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)
                ) { _ in
                    appearance.refreshDay()
                }
        }
    }
}
