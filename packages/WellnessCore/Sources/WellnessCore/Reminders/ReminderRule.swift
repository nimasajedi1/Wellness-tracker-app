import Foundation

/// User-configured local reminder (DEVICE-004): explicit times, weekday
/// schedule, quiet hours, and neutral wording. Reminders are never inferred
/// from data (no medication schedules) and never treated as evidence that a
/// task was completed.
public struct QuietHours: Codable, Hashable, Sendable {
    /// Minutes after midnight; the window may cross midnight (e.g. 22:00-07:00).
    public var startMinute: Int
    public var endMinute: Int

    public init(startMinute: Int, endMinute: Int) {
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public func contains(minuteOfDay: Int) -> Bool {
        if startMinute == endMinute { return false }
        if startMinute < endMinute {
            return minuteOfDay >= startMinute && minuteOfDay < endMinute
        }
        // Crosses midnight.
        return minuteOfDay >= startMinute || minuteOfDay < endMinute
    }
}

public struct ReminderRule: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Neutral title chosen by the user; no shaming defaults.
    public var title: String
    public var metricID: MetricID?
    public var hour: Int
    public var minute: Int
    /// 1 = Sunday ... 7 = Saturday. Empty = every day.
    public var weekdays: [Int]
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        metricID: MetricID? = nil,
        hour: Int,
        minute: Int,
        weekdays: [Int] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.metricID = metricID
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.isEnabled = isEnabled
    }

    public var minuteOfDay: Int { hour * 60 + minute }

    /// Delivery time after applying quiet hours: a reminder inside the quiet
    /// window shifts to the window's end rather than firing silently or being
    /// dropped without explanation.
    public func effectiveMinuteOfDay(quietHours: QuietHours?) -> Int {
        guard let quietHours, quietHours.contains(minuteOfDay: minuteOfDay) else {
            return minuteOfDay
        }
        return quietHours.endMinute % (24 * 60)
    }

    /// Next fire date strictly after `after` in the user's current time zone
    /// (time-zone policy: reminders follow the clock the user lives in;
    /// stored history is unaffected, STORE-006).
    public func nextFireDate(after: Date, timeZone: TimeZone, quietHours: QuietHours? = nil) -> Date? {
        guard isEnabled else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let effective = effectiveMinuteOfDay(quietHours: quietHours)

        var day = cal.startOfDay(for: after)
        for _ in 0..<15 {  // bounded search over two weeks of weekdays
            let weekday = cal.component(.weekday, from: day)
            if weekdays.isEmpty || weekdays.contains(weekday) {
                if let candidate = cal.date(byAdding: .minute, value: effective, to: day),
                   candidate > after {
                    return candidate
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
        }
        return nil
    }
}
