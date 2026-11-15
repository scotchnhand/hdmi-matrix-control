import Foundation

// Holiday themes: which holiday (if any) holidays.json says is on for a
// given day and region, and the palette it carries. Pure value types with
// no UI. The web twin is hdmi-matrix-ui/frontend/holidays.js; both run the
// cases in docs/holidays.json, of which Resources/holidays.json is a copy.

/// A calendar day with no time or time zone.
public struct HolidayDate: Equatable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on for the user.
    public init(_ date: Date, calendar: Calendar = .current) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Parses `YYYY-MM-DD`.
    public init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// Whole days since 1970-01-01 (proleptic Gregorian). All holiday math
    /// is done in day numbers so time zones and DST never come into it.
    var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    init(dayNumber: Int) {
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153
        let month = mp < 10 ? mp + 3 : mp - 9
        self.init(
            year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0),
            month: month,
            day: dayOfYear - (153 * mp + 2) / 5 + 1
        )
    }
}

/// One holiday: when it falls, how long its theme shows, and its colors.
public struct Holiday: Decodable, Identifiable, Equatable, Sendable {
    /// When the holiday falls. `type` is `fixed` (month/day), `nth-weekday`
    /// (the n-th `weekday` of `month`, 0 = Sunday) or `offset` (`days`
    /// after the holiday `from`). Unknown types never match.
    public struct Rule: Decodable, Equatable, Sendable {
        public var type: String
        public var month: Int?
        public var day: Int?
        public var weekday: Int?
        public var n: Int?
        public var from: String?
        public var days: Int?
    }

    /// Days around the holiday on which its theme shows.
    public struct Window: Decodable, Equatable, Sendable {
        public var before: Int
        public var after: Int
    }

    /// Hex colors per palette token, for dark and light appearance.
    public struct Palette: Decodable, Equatable, Sendable {
        public var dark: [String: String]
        public var light: [String: String]

        /// `0xRRGGBB` for a token such as `accent`, or nil if it is
        /// missing or not a `#rrggbb` color.
        public func color(_ token: String, dark isDark: Bool) -> UInt32? {
            guard let hex = (isDark ? dark : light)[token],
                  hex.count == 7, hex.hasPrefix("#")
            else { return nil }
            return UInt32(hex.dropFirst(), radix: 16)
        }
    }

    public var id: String
    public var name: String
    /// Regions the holiday is limited to; nil means everywhere.
    public var regions: [String]?
    public var rule: Rule
    public var window: Window
    public var palette: Palette
}

/// The decoded holidays.json.
public struct HolidayCatalog: Decodable, Sendable {
    public var tokens: [String]
    public var regions: [String]
    public var holidays: [Holiday]

    public init(tokens: [String] = [], regions: [String] = [], holidays: [Holiday] = []) {
        self.tokens = tokens
        self.regions = regions
        self.holidays = holidays
    }

    public init(data: Data) throws {
        self = try JSONDecoder().decode(HolidayCatalog.self, from: data)
    }

    /// The catalog shipped with the package. Empty if the resource is
    /// missing or unreadable, which just means no holiday themes.
    public static let bundled: HolidayCatalog = {
        guard let url = Bundle.module.url(forResource: "holidays", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? HolidayCatalog(data: data)
        else { return HolidayCatalog() }
        return catalog
    }()

    public func holiday(id: String) -> Holiday? {
        holidays.first { $0.id == id }
    }

    /// The holiday whose window contains `date` for `region`, or nil.
    /// Earlier entries in the catalog win an overlap.
    public func activeHoliday(on date: HolidayDate, region: String) -> Holiday? {
        activeHoliday(onDay: date.dayNumber, year: date.year, region: region)
    }

    /// The holiday that is on now or comes up next -- the default preview.
    public func upcomingHoliday(from date: HolidayDate, region: String) -> Holiday? {
        let start = date.dayNumber
        for offset in 0...366 {
            let day = start + offset
            if let found = activeHoliday(onDay: day, year: HolidayDate(dayNumber: day).year, region: region) {
                return found
            }
        }
        return nil
    }

    /// `fr-CA` / `en_US` / `zh-Hans-CN` -> `CA` / `US` / `CN`; empty if
    /// the identifier carries no region.
    public static func region(fromLocaleIdentifier identifier: String) -> String {
        let parts = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).dropFirst()
        let region = parts.first { $0.count == 2 && $0.allSatisfy { $0.isASCII && $0.isLetter } }
        return region.map { $0.uppercased() } ?? ""
    }

    private func activeHoliday(onDay dayNumber: Int, year: Int, region: String) -> Holiday? {
        holidays.first { holiday in
            guard holiday.regions?.contains(region) ?? true else { return false }
            // The neighbouring years cover windows that straddle New Year.
            return [year - 1, year, year + 1].contains { candidate in
                guard let day = occurrence(of: holiday, in: candidate) else { return false }
                return dayNumber >= day - holiday.window.before && dayNumber <= day + holiday.window.after
            }
        }
    }

    /// The day number a holiday falls on in `year`, or nil for a rule this
    /// version doesn't understand.
    private func occurrence(of holiday: Holiday, in year: Int, depth: Int = 0) -> Int? {
        let rule = holiday.rule
        switch rule.type {
        case "fixed":
            guard let month = rule.month, let day = rule.day else { return nil }
            return HolidayDate(year: year, month: month, day: day).dayNumber
        case "nth-weekday":
            guard let month = rule.month, let weekday = rule.weekday, let n = rule.n else { return nil }
            let first = HolidayDate(year: year, month: month, day: 1).dayNumber
            let firstWeekday = ((first + 4) % 7 + 7) % 7 // 0 = Sunday; 1970-01-01 was a Thursday
            return first + (weekday - firstWeekday + 7) % 7 + (n - 1) * 7
        case "offset":
            guard depth < 4, let from = rule.from, let days = rule.days,
                  let base = self.holiday(id: from),
                  let baseDay = occurrence(of: base, in: year, depth: depth + 1)
            else { return nil }
            return baseDay + days
        default:
            return nil
        }
    }
}
