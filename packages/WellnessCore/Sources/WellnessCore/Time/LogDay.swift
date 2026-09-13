import Foundation

/// A calendar day the user has chosen to attribute records to (STORE-006).
/// Stored independently of the event timestamp so that later travel or time-zone
/// changes never move historical records between days (REG-017).
public struct LogDay: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(isoString: String) {
        let parts = isoString.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public init(date: Date, timeZone: TimeZone, calendar: Calendar = Calendar(identifier: .gregorian)) {
        var cal = calendar
        cal.timeZone = timeZone
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        self.init(year: comps.year ?? 1970, month: comps.month ?? 1, day: comps.day ?? 1)
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { isoString }

    public func startOfDay(in timeZone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    public func adding(days: Int, timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> LogDay {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let start = startOfDay(in: timeZone)
        let shifted = cal.date(byAdding: .day, value: days, to: start) ?? start
        return LogDay(date: shifted, timeZone: timeZone, calendar: cal)
    }

    public static func < (lhs: LogDay, rhs: LogDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// Injected clock so day boundaries and schedules never depend on a Date()
/// captured at app launch (STORE-010).
public protocol DateProviding: Sendable {
    func now() -> Date
    var timeZone: TimeZone { get }
}

public struct SystemDateProvider: DateProviding {
    public init() {}
    public func now() -> Date { Date() }
    public var timeZone: TimeZone { TimeZone.current }
}

public struct FixedDateProvider: DateProviding {
    public let fixedNow: Date
    public let timeZone: TimeZone
    public init(now: Date, timeZone: TimeZone) {
        self.fixedNow = now
        self.timeZone = timeZone
    }
    public func now() -> Date { fixedNow }
}

/// A dated interval such as sleep or fasting (STORE-007, STORE-008).
/// Endpoints are real timestamps, so elapsed time is wall-clock correct across
/// midnight and daylight-saving transitions (REG-015, REG-016).
public struct DatedInterval: Codable, Hashable, Sendable {
    public var start: Date
    /// nil means the interval is still open: incomplete, not zero (STORE-007).
    public var end: Date?
    /// Time zone in effect when the interval was recorded, kept for display.
    public var timeZoneIdentifier: String

    public init(start: Date, end: Date?, timeZoneIdentifier: String) {
        self.start = start
        self.end = end
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public var isComplete: Bool { end != nil }

    /// Elapsed minutes between the actual instants. Never wrapped modulo 24 h.
    /// A negative result (end before start) is invalid and reported as nil so
    /// the editor can ask for a date correction (STORE-008).
    public var elapsedMinutes: Double? {
        guard let end else { return nil }
        let seconds = end.timeIntervalSince(start)
        guard seconds >= 0 else { return nil }
        return seconds / 60.0
    }
}
