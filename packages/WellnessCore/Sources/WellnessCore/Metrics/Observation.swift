import Foundation

/// Typed observed value. Quantities are numbers plus typed units, never strings
/// containing units (STORE-002).
public enum ObservedValue: Codable, Hashable, Sendable {
    case quantity(Double, UnitOfMeasure)
    case count(Int)
    case durationMinutes(Double)
    case timestamp(Date)
    case interval(DatedInterval)
    case boolean(Bool)
    case checklist([String: Bool])
    case rating(Int)
    case enumeration(String)
    case pairedQuantity(first: Double, second: Double, unit: UnitOfMeasure?)
    case note(String)
}

public enum ObservationSource: String, Codable, Hashable, Sendable {
    case manual
    case foodLedger         // derived from committed meal snapshots
    case manualAdjustment   // auditable absolute-total adjustment (FOOD-020)
    case legacyImport
    case healthKit          // P1
    case chatProposal       // committed through the confirmed chat flow
}

/// One recorded fact. Absence of an Observation means "unrecorded", which is
/// never the same as an observation whose value is zero (GOAL-002, REG-001/002).
public struct Observation: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var metricID: MetricID
    public var value: ObservedValue
    public var observedAt: Date
    public var timeZoneIdentifier: String
    public var logDay: LogDay
    public var source: ObservationSource
    public var externalSampleID: String?
    public var revision: Int
    /// Soft-delete flag so Undo and day reset stay reversible (STORE-005).
    public var isDeleted: Bool

    public init(
        id: UUID = UUID(),
        metricID: MetricID,
        value: ObservedValue,
        observedAt: Date,
        timeZoneIdentifier: String,
        logDay: LogDay,
        source: ObservationSource = .manual,
        externalSampleID: String? = nil,
        revision: Int = 1,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.metricID = metricID
        self.value = value
        self.observedAt = observedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.logDay = logDay
        self.source = source
        self.externalSampleID = externalSampleID
        self.revision = revision
        self.isDeleted = isDeleted
    }
}

/// Aggregated value for one metric on one day, carrying explicit coverage so a
/// known partial total is never presented as a complete day (GOAL-010).
public struct AggregatedMetricValue: Sendable, Equatable {
    public enum Coverage: String, Sendable {
        case none        // no observations at all -> unrecorded
        case partial     // some inputs known, some missing
        case complete
    }
    public var metricID: MetricID
    /// nil when there is no evaluable numeric value (e.g. no observations).
    public var numericValue: Double?
    public var coverage: Coverage
    /// For checklists: done / total counts.
    public var checklistDone: Int?
    public var checklistTotal: Int?
    /// True when any observation exists for the metric on the day.
    public var hasAnyObservation: Bool

    public init(
        metricID: MetricID,
        numericValue: Double?,
        coverage: Coverage,
        checklistDone: Int? = nil,
        checklistTotal: Int? = nil,
        hasAnyObservation: Bool = true
    ) {
        self.metricID = metricID
        self.numericValue = numericValue
        self.coverage = coverage
        self.checklistDone = checklistDone
        self.checklistTotal = checklistTotal
        self.hasAnyObservation = hasAnyObservation
    }

    public static func unrecorded(_ metricID: MetricID) -> AggregatedMetricValue {
        AggregatedMetricValue(metricID: metricID, numericValue: nil, coverage: .none, hasAnyObservation: false)
    }
}

public enum MetricAggregator {
    /// Deterministic aggregation of a day's observations for one metric.
    /// Deleted observations never contribute (STORE-004).
    public static func aggregate(
        metric: MetricDefinition,
        observations: [Observation]
    ) -> AggregatedMetricValue {
        let active = observations.filter { $0.metricID == metric.id && !$0.isDeleted }
        guard !active.isEmpty else { return .unrecorded(metric.id) }

        switch metric.aggregation {
        case .sum:
            var total = 0.0
            var sawNumeric = false
            for obs in active {
                if let value = numericValue(of: obs.value, canonicalUnit: metric.canonicalUnit) {
                    total += value
                    sawNumeric = true
                }
            }
            return AggregatedMetricValue(
                metricID: metric.id,
                numericValue: sawNumeric ? total : nil,
                coverage: sawNumeric ? .complete : .none,
                hasAnyObservation: true
            )
        case .lastObservation:
            let last = active.max(by: { $0.observedAt < $1.observedAt })!
            return AggregatedMetricValue(
                metricID: metric.id,
                numericValue: numericValue(of: last.value, canonicalUnit: metric.canonicalUnit),
                coverage: .complete,
                hasAnyObservation: true
            )
        case .countObservations:
            return AggregatedMetricValue(
                metricID: metric.id,
                numericValue: Double(active.count),
                coverage: .complete,
                hasAnyObservation: true
            )
        case .durationUnion:
            // Union of completed intervals so overlaps are not double counted
            // (category rule for sleep; HEALTH-005 applies the same idea later).
            let intervals: [(Date, Date)] = active.compactMap {
                if case .interval(let interval) = $0.value, let end = interval.end, end >= interval.start {
                    return (interval.start, end)
                }
                return nil
            }
            let openIntervalExists = active.contains {
                if case .interval(let interval) = $0.value { return interval.end == nil }
                return false
            }
            guard !intervals.isEmpty else {
                return AggregatedMetricValue(
                    metricID: metric.id,
                    numericValue: nil,
                    coverage: openIntervalExists ? .partial : .none,
                    hasAnyObservation: true
                )
            }
            let sorted = intervals.sorted { $0.0 < $1.0 }
            var merged: [(Date, Date)] = []
            for interval in sorted {
                if var last = merged.last, interval.0 <= last.1 {
                    last.1 = max(last.1, interval.1)
                    merged[merged.count - 1] = last
                } else {
                    merged.append(interval)
                }
            }
            let minutes = merged.reduce(0.0) { $0 + $1.1.timeIntervalSince($1.0) / 60.0 }
            return AggregatedMetricValue(
                metricID: metric.id,
                numericValue: minutes,
                coverage: openIntervalExists ? .partial : .complete,
                hasAnyObservation: true
            )
        case .checklistCompletion:
            // Merge checklist states; the latest observation wins per item.
            var itemState: [String: Bool] = [:]
            for obs in active.sorted(by: { $0.observedAt < $1.observedAt }) {
                if case .checklist(let items) = obs.value {
                    for (key, done) in items { itemState[key] = done }
                }
            }
            let expected = metric.checklistItems ?? Array(itemState.keys).sorted()
            let total = max(expected.count, itemState.count)
            let done = expected.isEmpty
                ? itemState.values.filter { $0 }.count
                : expected.filter { itemState[$0] == true }.count
            return AggregatedMetricValue(
                metricID: metric.id,
                numericValue: total > 0 ? Double(done) / Double(total) : nil,
                coverage: .complete,
                checklistDone: done,
                checklistTotal: total,
                hasAnyObservation: true
            )
        }
    }

    static func numericValue(of value: ObservedValue, canonicalUnit: UnitOfMeasure?) -> Double? {
        switch value {
        case .quantity(let amount, let unit):
            guard let canonical = canonicalUnit else { return amount }
            if unit == canonical { return amount }
            if let converted = try? UnitConverter.convert(Decimal(amount), from: unit, to: canonical) {
                return NSDecimalNumber(decimal: converted).doubleValue
            }
            return nil
        case .count(let n): return Double(n)
        case .durationMinutes(let m): return m
        case .boolean(let flag): return flag ? 1 : 0
        case .rating(let r): return Double(r)
        case .interval(let interval): return interval.elapsedMinutes
        case .timestamp, .checklist, .enumeration, .pairedQuantity, .note:
            return nil
        }
    }
}
