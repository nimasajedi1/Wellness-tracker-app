import Foundation

/// Stable identity for a tracked quantity. Templates are views over metric IDs;
/// switching templates never duplicates the underlying fact stream (BUILD-013).
public struct MetricID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var description: String { rawValue }
}

/// Typed value kinds allowed for custom fields (BUILD-010). No free-form
/// formulas, scripts, or SQL are ever evaluated.
public enum MetricValueType: String, Codable, Sendable, CaseIterable {
    case quantity        // numeric amount with a unit (protein g, caffeine mg)
    case countValue      // discrete count (steps, stretch breaks)
    case duration        // minutes
    case timestamp       // single point in time
    case interval        // start/end pair
    case boolean         // yes/no (workout done)
    case checklist       // named checklist items (supplements AM/PM)
    case rating          // bounded subjective scale
    case enumeration     // one of a fixed set of labels
    case pairedQuantity  // structured pair (e.g. blood pressure)
    case note            // free text, never scored
}

public enum MetricAggregation: String, Codable, Sendable, CaseIterable {
    case sum
    case lastObservation
    case countObservations
    case durationUnion
    case checklistCompletion
}

/// Named derived calculations (BUILD-011). This closed registry is the only
/// computation surface the builder exposes; arbitrary expressions are forbidden.
public enum DerivedCalculation: String, Codable, Sendable, CaseIterable {
    case sum
    case lastObservation
    case intervalDuration
    case checklistCompletion
    case ratio
    case difference
    case restingPlusActiveEnergy
    case netEnergy
}

public enum MetricInputKind: String, Codable, Sendable {
    case counter      // +/- with a configurable step
    case number       // direct numeric entry
    case toggle
    case checklist
    case intervalEditor
    case ratingScale
    case textNote
}

public struct MetricInputConfig: Codable, Hashable, Sendable {
    public var kind: MetricInputKind
    public var step: Double?
    public init(kind: MetricInputKind, step: Double? = nil) {
        self.kind = kind
        self.step = step
    }
}

/// Registry entry describing one tracked field (BUILD-014): adding sodium or
/// caffeine is a new registry row, not a schema migration.
public struct MetricDefinition: Codable, Hashable, Sendable, Identifiable {
    public var id: MetricID
    public var name: String
    public var category: String
    public var valueType: MetricValueType
    public var canonicalUnit: UnitOfMeasure?
    public var displayUnit: UnitOfMeasure?
    public var aggregation: MetricAggregation
    public var input: MetricInputConfig
    /// Checklist item labels when valueType == .checklist.
    public var checklistItems: [String]?
    /// Metric IDs a derived field reads from (BUILD-009). Cycles are rejected
    /// at configuration-validation time.
    public var dependencies: [MetricID]
    public var derived: DerivedCalculation?
    public var isArchived: Bool
    public var personalNote: String?

    public init(
        id: MetricID,
        name: String,
        category: String,
        valueType: MetricValueType,
        canonicalUnit: UnitOfMeasure? = nil,
        displayUnit: UnitOfMeasure? = nil,
        aggregation: MetricAggregation = .sum,
        input: MetricInputConfig = MetricInputConfig(kind: .number),
        checklistItems: [String]? = nil,
        dependencies: [MetricID] = [],
        derived: DerivedCalculation? = nil,
        isArchived: Bool = false,
        personalNote: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.valueType = valueType
        self.canonicalUnit = canonicalUnit
        self.displayUnit = displayUnit
        self.aggregation = aggregation
        self.input = input
        self.checklistItems = checklistItems
        self.dependencies = dependencies
        self.derived = derived
        self.isArchived = isArchived
        self.personalNote = personalNote
    }
}
