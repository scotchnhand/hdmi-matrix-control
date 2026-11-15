import Foundation
import XCTest
@testable import MatrixKit

/// Runs the shared cases in docs/holidays.json -- the same file the web
/// suite (hdmi-matrix-ui/frontend-tests/holidays.test.js) runs -- so the
/// Swift and JavaScript holiday logic can't drift apart.
final class HolidayFixtureTests: XCTestCase {
    private static let sourceData: Data = {
        // Found relative to this source file, like ProtocolFixtureTests.
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if let data = try? Data(contentsOf: dir.appendingPathComponent("docs/holidays.json")) {
                return data
            }
            dir.deleteLastPathComponent()
        }
        fatalError("docs/holidays.json not found above \(#filePath)")
    }()

    private static let catalog = try! HolidayCatalog(data: sourceData)

    private static let cases: [String: [[String: Any]]] = {
        let root = try! JSONSerialization.jsonObject(with: sourceData) as! [String: Any]
        return root["cases"] as! [String: [[String: Any]]]
    }()

    private func cases(_ key: String) -> [[String: Any]] {
        Self.cases[key] ?? []
    }

    func testBundledCatalogMatchesDocs() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "holidays", withExtension: "json"))
        XCTAssertEqual(try Data(contentsOf: url), Self.sourceData, "Resources/holidays.json is out of date")
        XCTAssertEqual(HolidayCatalog.bundled.holidays, Self.catalog.holidays)
        XCTAssertFalse(HolidayCatalog.bundled.holidays.isEmpty)
    }

    func testActiveHolidayCases() throws {
        let active = cases("active")
        XCTAssertFalse(active.isEmpty)
        for c in active {
            let iso = c["date"] as! String
            let region = c["region"] as! String
            let date = try XCTUnwrap(HolidayDate(iso: iso))
            XCTAssertEqual(
                Self.catalog.activeHoliday(on: date, region: region)?.id,
                c["expect"] as? String,
                "\(iso) \(region)"
            )
        }
    }

    func testUpcomingHolidayCases() throws {
        let upcoming = cases("upcoming")
        XCTAssertFalse(upcoming.isEmpty)
        for c in upcoming {
            let iso = c["date"] as! String
            let region = c["region"] as! String
            let date = try XCTUnwrap(HolidayDate(iso: iso))
            XCTAssertEqual(
                Self.catalog.upcomingHoliday(from: date, region: region)?.id,
                c["expect"] as? String,
                "\(iso) \(region)"
            )
        }
    }

    func testLocaleRegionCases() {
        let locales = cases("locale_regions")
        XCTAssertFalse(locales.isEmpty)
        for c in locales {
            let locale = c["locale"] as! String
            XCTAssertEqual(HolidayCatalog.region(fromLocaleIdentifier: locale), c["expect"] as? String, locale)
        }
        XCTAssertEqual(HolidayCatalog.region(fromLocaleIdentifier: "en"), "")
    }

    func testEveryPaletteTokenIsAColor() {
        for holiday in Self.catalog.holidays {
            for token in Self.catalog.tokens {
                XCTAssertNotNil(holiday.palette.color(token, dark: true), "\(holiday.id) dark \(token)")
                XCTAssertNotNil(holiday.palette.color(token, dark: false), "\(holiday.id) light \(token)")
            }
        }
        let palette = Holiday.Palette(dark: ["accent": "#ff9a3c", "bad": "orange"], light: [:])
        XCTAssertEqual(palette.color("accent", dark: true), 0xFF9A3C)
        XCTAssertNil(palette.color("bad", dark: true))
        XCTAssertNil(palette.color("accent", dark: false))
    }

    func testDayNumbersRoundTripAndMatchFoundation() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        for iso in ["1970-01-01", "2000-02-29", "2026-11-26", "2027-01-01", "2028-02-29", "2030-12-31"] {
            let date = HolidayDate(iso: iso)!
            XCTAssertEqual(HolidayDate(dayNumber: date.dayNumber), date, iso)
            let foundation = utc.date(from: DateComponents(year: date.year, month: date.month, day: date.day))!
            XCTAssertEqual(date.dayNumber, Int(foundation.timeIntervalSince1970 / 86_400), iso)
            XCTAssertEqual(HolidayDate(foundation, calendar: utc), date, iso)
        }
        XCTAssertNil(HolidayDate(iso: "2026-11"))
    }

    func testUnknownOrCircularRulesNeverMatch() throws {
        let json = """
        {"tokens": [], "regions": [], "holidays": [
          {"id": "odd", "name": "Odd", "rule": {"type": "lunar"},
           "window": {"before": 400, "after": 400}, "palette": {"dark": {}, "light": {}}},
          {"id": "loop", "name": "Loop", "rule": {"type": "offset", "from": "loop", "days": 1},
           "window": {"before": 400, "after": 400}, "palette": {"dark": {}, "light": {}}}
        ]}
        """
        let catalog = try HolidayCatalog(data: Data(json.utf8))
        XCTAssertNil(catalog.activeHoliday(on: HolidayDate(year: 2026, month: 1, day: 1), region: "US"))
    }
}
