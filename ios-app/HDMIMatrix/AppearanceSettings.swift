import Foundation
import MatrixKit
import Observation

/// The opt-in holiday theme: whether it's on, for which region, and which
/// holiday that works out to today. Stored in UserDefaults; off by default.
@Observable
final class AppearanceSettings {
    enum Mode: String, CaseIterable, Identifiable {
        /// Never themed.
        case off
        /// Themed on a holiday's dates.
        case auto
        /// Always themed, to preview a holiday.
        case always

        var id: Self { self }

        var label: String {
            switch self {
            case .off: "Off"
            case .auto: "Auto"
            case .always: "Always"
            }
        }
    }

    /// The `region` value meaning "use the device's region".
    static let automaticRegion = "auto"

    private enum Key {
        static let mode = "holidayThemeMode"
        static let region = "holidayThemeRegion"
        static let preview = "holidayThemePreview"
    }

    let catalog: HolidayCatalog
    private let defaults: UserDefaults
    private let locale: Locale

    var mode: Mode {
        didSet { defaults.set(mode.rawValue, forKey: Key.mode) }
    }

    /// `automaticRegion`, or one of the catalog's regions. US and Canadian
    /// Thanksgiving fall on different dates, so the region matters.
    var region: String {
        didSet { defaults.set(region, forKey: Key.region) }
    }

    /// The holiday `always` shows; empty until the user picks one, which
    /// means whichever is on now or comes up next.
    var previewID: String {
        didSet { defaults.set(previewID, forKey: Key.preview) }
    }

    private(set) var today: HolidayDate

    init(
        defaults: UserDefaults = .standard,
        catalog: HolidayCatalog = .bundled,
        locale: Locale = .current,
        now: Date = .now
    ) {
        self.defaults = defaults
        self.catalog = catalog
        self.locale = locale
        mode = defaults.string(forKey: Key.mode).flatMap(Mode.init) ?? .off
        let storedRegion = defaults.string(forKey: Key.region) ?? Self.automaticRegion
        region = catalog.regions.contains(storedRegion) ? storedRegion : Self.automaticRegion
        previewID = defaults.string(forKey: Key.preview) ?? ""
        today = HolidayDate(now)
    }

    /// UI tests launch with `-ui-testing`: throwaway settings, so runs are
    /// repeatable and never touch real ones.
    static func forLaunch() -> AppearanceSettings {
        guard CommandLine.arguments.contains("-ui-testing") else { return AppearanceSettings() }
        let suite = "HDMIMatrix.UITests.Appearance"
        UserDefaults().removePersistentDomain(forName: suite)
        return AppearanceSettings(defaults: UserDefaults(suiteName: suite)!)
    }

    /// The region holidays are resolved for.
    var resolvedRegion: String {
        region == Self.automaticRegion ? (locale.region?.identifier ?? "") : region
    }

    /// The holiday whose theme is showing, if any.
    var holiday: Holiday? {
        switch mode {
        case .off: nil
        case .auto: catalog.activeHoliday(on: today, region: resolvedRegion)
        case .always: catalog.holiday(id: previewID) ?? upcomingHoliday ?? catalog.holidays.first
        }
    }

    /// The holiday that is on now or comes up next.
    var upcomingHoliday: Holiday? {
        catalog.upcomingHoliday(from: today, region: resolvedRegion)
    }

    /// Call when the app comes forward or the day changes, so `auto`
    /// follows the calendar.
    func refreshDay(now: Date = .now) {
        let day = HolidayDate(now)
        if day != today { today = day }
    }
}
