import Foundation

public struct GoalID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

public enum GoalKind: String, Codable, Sendable {
    case minimum
    case maximum
    case range
    case exact
    case completion
    case trendOnly
    case composite
}

public enum GoalPeriod: String, Codable, Sendable {
    case day
    case week
}

public enum MissingPolicy: String, Codable, Sendable {
    case incomplete       // missing data -> unrecorded/partial, never outside
    case ignoreIfOptional // optional metric; missing data leaves group unaffected
}

/// What the user sees, deliberately separate from the evaluation thresholds
/// (section 8.1: display protein 140-150 g, evaluate green at >= 130 g).
public struct DisplayTarget: Codable, Hashable, Sendable {
    public var lower: Double?
    public var upper: Double?
    public var exact: Double?
    public var unit: UnitOfMeasure?
    public init(lower: Double? = nil, upper: Double? = nil, exact: Double? = nil, unit: UnitOfMeasure? = nil) {
        self.lower = lower
        self.upper = upper
        self.exact = exact
        self.unit = unit
    }
}

/// Explicit numeric evaluation thresholds. All inclusivity is fixed by the
/// standard formulas in GoalEvaluator; no hidden extra tolerance is applied on
/// top of these values (GOAL-003).
public struct EvaluationBounds: Codable, Hashable, Sendable {
    /// minimum kind: met at value >= metMinimum.
    public var metMinimum: Double?
    /// minimum kind: near at value >= nearMinimum (and < metMinimum).
    public var nearMinimum: Double?
    /// maximum kind: met at value <= metMaximum.
    public var metMaximum: Double?
    /// maximum kind: near at value <= nearMaximum (and > metMaximum).
    public var nearMaximum: Double?
    /// range kind: met inside [metLower, metUpper].
    public var metLower: Double?
    public var metUpper: Double?
    /// range kind: near inside [nearLower, metLower) or (metUpper, nearUpper].
    public var nearLower: Double?
    public var nearUpper: Double?

    public init(
        metMinimum: Double? = nil, nearMinimum: Double? = nil,
        metMaximum: Double? = nil, nearMaximum: Double? = nil,
        metLower: Double? = nil, metUpper: Double? = nil,
        nearLower: Double? = nil, nearUpper: Double? = nil
    ) {
        self.metMinimum = metMinimum
        self.nearMinimum = nearMinimum
        self.metMaximum = metMaximum
        self.nearMaximum = nearMaximum
        self.metLower = metLower
        self.metUpper = metUpper
        self.nearLower = nearLower
        self.nearUpper = nearUpper
    }
}

public enum CompositeRule: String, Codable, Sendable {
    case allRequired
    case anyRequired
    /// Owner's custom workout + steps combination (GOAL-007).
    case ownerExercise
    /// Worst evaluable status wins: outside > near > met (GOAL-006).
    case worstStatus
}

public struct GoalSchedule: Codable, Hashable, Sendable {
    /// 1 = Sunday ... 7 = Saturday (Calendar weekday numbering). Empty = daily.
    public var weekdays: [Int]
    /// Minutes after midnight when the goal becomes due; nil = end of day.
    public var dueMinuteOfDay: Int?
    public init(weekdays: [Int] = [], dueMinuteOfDay: Int? = nil) {
        self.weekdays = weekdays
        self.dueMinuteOfDay = dueMinuteOfDay
    }
}

public struct GoalConfiguration: Codable, Hashable, Sendable, Identifiable {
    public var id: GoalID
    public var metricID: MetricID?
    public var configVersion: Int
    public var kind: GoalKind
    public var period: GoalPeriod
    public var displayTarget: DisplayTarget?
    public var bounds: EvaluationBounds
    public var missingPolicy: MissingPolicy
    public var schedule: GoalSchedule
    /// Whether this goal produces red/green judgments at all (BUILD-015).
    public var scoringEnabled: Bool
    /// Composite members, evaluated by `compositeRule`.
    public var memberGoalIDs: [GoalID]
    public var compositeRule: CompositeRule?

    public init(
        id: GoalID,
        metricID: MetricID?,
        configVersion: Int = 1,
        kind: GoalKind,
        period: GoalPeriod = .day,
        displayTarget: DisplayTarget? = nil,
        bounds: EvaluationBounds = EvaluationBounds(),
        missingPolicy: MissingPolicy = .incomplete,
        schedule: GoalSchedule = GoalSchedule(),
        scoringEnabled: Bool = true,
        memberGoalIDs: [GoalID] = [],
        compositeRule: CompositeRule? = nil
    ) {
        self.id = id
        self.metricID = metricID
        self.configVersion = configVersion
        self.kind = kind
        self.period = period
        self.displayTarget = displayTarget
        self.bounds = bounds
        self.missingPolicy = missingPolicy
        self.schedule = schedule
        self.scoringEnabled = scoringEnabled
        self.memberGoalIDs = memberGoalIDs
        self.compositeRule = compositeRule
    }
}
