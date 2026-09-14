import Foundation

/// Pure mapping layer for imported health samples (HEALTH-003..005). The
/// HealthKit service in the app target converts HKSamples into these transport
/// values; everything here is deterministic and Linux-testable.

/// Which source feeds a metric. Exclusive per metric per day: manual and
/// imported values are never summed together (HEALTH-003, ENERGY-005).
public enum MetricSourcePolicy: String, Codable, Sendable {
    case manual
    case healthKit

    /// The observation sources this policy admits into aggregation.
    public func admits(_ source: ObservationSource) -> Bool {
        switch self {
        case .manual:
            return source != .healthKit
        case .healthKit:
            return source == .healthKit
        }
    }
}

/// A daily quantity total already aggregated by the health store's own
/// deduplicating statistics (overlapping iPhone/watch samples are the store's
/// responsibility to reconcile; we never re-sum raw overlapping samples).
public struct ImportedDailyQuantity: Sendable, Equatable {
    public var metricID: MetricID
    public var day: LogDay
    public var value: Double
    public var unit: UnitOfMeasure
    /// True when the day being imported is already over in the user's zone.
    public var coversFullDay: Bool

    public init(metricID: MetricID, day: LogDay, value: Double, unit: UnitOfMeasure, coversFullDay: Bool) {
        self.metricID = metricID
        self.day = day
        self.value = value
        self.unit = unit
        self.coversFullDay = coversFullDay
    }
}

/// One sleep interval from the health store; only actually-asleep stages are
/// passed in (in-bed time is excluded by the service, HEALTH-005).
public struct ImportedSleepInterval: Sendable, Equatable {
    public var sampleID: String
    public var start: Date
    public var end: Date
    public init(sampleID: String, start: Date, end: Date) {
        self.sampleID = sampleID
        self.start = start
        self.end = end
    }
}

public enum HealthImportMapper {

    /// Stable external ID for a daily-total import: reimporting the same day
    /// replaces the previous import instead of adding to it (HEALTH-003).
    public static func dailySampleID(metricID: MetricID, day: LogDay) -> String {
        "healthkit:daily:\(metricID.rawValue):\(day.isoString)"
    }

    public static func observation(
        from quantity: ImportedDailyQuantity,
        timeZone: TimeZone,
        importedAt: Date
    ) -> Observation {
        Observation(
            metricID: quantity.metricID,
            value: .quantity(quantity.value, quantity.unit),
            observedAt: importedAt,
            timeZoneIdentifier: timeZone.identifier,
            logDay: quantity.day,
            source: .healthKit,
            externalSampleID: dailySampleID(metricID: quantity.metricID, day: quantity.day)
        )
    }

    /// Sleep intervals become individual observations keyed by the store's
    /// sample UUID so updates and deletions are idempotent (HEALTH-003).
    /// Overlap handling stays in the durationUnion aggregation (HEALTH-005).
    public static func sleepObservations(
        metricID: MetricID,
        intervals: [ImportedSleepInterval],
        day: LogDay,
        timeZone: TimeZone,
        importedAt: Date
    ) -> [Observation] {
        intervals
            .filter { $0.end > $0.start }
            .map { interval in
                Observation(
                    metricID: metricID,
                    value: .interval(DatedInterval(start: interval.start, end: interval.end, timeZoneIdentifier: timeZone.identifier)),
                    observedAt: importedAt,
                    timeZoneIdentifier: timeZone.identifier,
                    logDay: day,
                    source: .healthKit,
                    externalSampleID: "healthkit:sleep:\(interval.sampleID)"
                )
            }
    }
}

/// Well-known metric IDs for imported energy components used by the HealthKit
/// energy method (ENERGY-003). They are internal inputs to the energy engine
/// and are not user-facing dashboard cards.
public enum HealthMetrics {
    public static let restingEnergy: MetricID = "health.restingEnergy"
    public static let activeEnergy: MetricID = "health.activeEnergy"
    public static let bodyMass: MetricID = "body.weight"
}
