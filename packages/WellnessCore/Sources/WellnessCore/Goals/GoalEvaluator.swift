import Foundation

/// Typed goal status (GOAL-002). Gray = unrecorded/partial, green = met,
/// yellow = near, red = outside. A missing observation is never an observed zero.
public enum GoalStatus: String, Codable, Sendable, Comparable {
    case unrecorded
    case partial
    case met
    case near
    case outside
    case notScheduled
    case unscored

    /// Severity order used by worst-status composites: outside > near > met.
    var severity: Int {
        switch self {
        case .outside: return 3
        case .near: return 2
        case .met: return 1
        case .partial, .unrecorded, .notScheduled, .unscored: return 0
        }
    }

    public static func < (lhs: GoalStatus, rhs: GoalStatus) -> Bool {
        lhs.severity < rhs.severity
    }
}

public struct GoalEvaluation: Sendable, Equatable {
    public var goalID: GoalID
    public var status: GoalStatus
    /// Fraction of target achieved; display may cap at 1.0 (GOAL-005) while the
    /// underlying value is preserved here.
    public var progress: Double?
    /// Human-readable reason, e.g. "Steps not recorded yet".
    public var reason: String
    public var contributingValues: [MetricID: Double]

    public init(goalID: GoalID, status: GoalStatus, progress: Double? = nil, reason: String = "", contributingValues: [MetricID: Double] = [:]) {
        self.goalID = goalID
        self.status = status
        self.progress = progress
        self.reason = reason
        self.contributingValues = contributingValues
    }
}

public struct GoalDateContext: Sendable {
    public var logDay: LogDay
    /// Now, from the injected clock (STORE-010).
    public var now: Date
    public var timeZone: TimeZone
    /// True when the evaluated day is before the current day, so schedules with
    /// due windows are considered closed.
    public var isPastDay: Bool

    public init(logDay: LogDay, now: Date, timeZone: TimeZone, isPastDay: Bool) {
        self.logDay = logDay
        self.now = now
        self.timeZone = timeZone
        self.isPastDay = isPastDay
    }
}

/// Pure evaluator (GOAL-001): one function serves Today, Builder preview,
/// History, and tests. No SwiftUI, model, or storage dependencies.
public enum GoalEvaluator {

    public static func evaluate(
        goal: GoalConfiguration,
        value: AggregatedMetricValue?,
        dateContext: GoalDateContext
    ) -> GoalEvaluation {
        guard goal.scoringEnabled, goal.kind != .trendOnly else {
            return GoalEvaluation(goalID: goal.id, status: .unscored, reason: "Tracking only, no target set")
        }

        if !isScheduled(goal: goal, on: dateContext) {
            return GoalEvaluation(goalID: goal.id, status: .notScheduled, reason: "Not scheduled today")
        }

        switch goal.kind {
        case .minimum:
            return evaluateMinimum(goal: goal, value: value)
        case .maximum:
            return evaluateMaximum(goal: goal, value: value)
        case .range, .exact:
            return evaluateRange(goal: goal, value: value)
        case .completion:
            return evaluateCompletion(goal: goal, value: value, dateContext: dateContext)
        case .trendOnly:
            return GoalEvaluation(goalID: goal.id, status: .unscored, reason: "Tracking only")
        case .composite:
            // Composites are evaluated via evaluateComposite with member results.
            return GoalEvaluation(goalID: goal.id, status: .unrecorded, reason: "Composite requires member evaluations")
        }
    }

    // MARK: - Scalar kinds

    /// met: x >= T; near: T-a <= x < T; outside: x < T-a  (section 8.2).
    /// Values above a minimum target remain met (GOAL-004).
    static func evaluateMinimum(goal: GoalConfiguration, value: AggregatedMetricValue?) -> GoalEvaluation {
        guard let aggregate = value, aggregate.hasAnyObservation, let x = aggregate.numericValue else {
            return unrecordedResult(goal: goal, value: value)
        }
        guard let met = goal.bounds.metMinimum else {
            return GoalEvaluation(goalID: goal.id, status: .unscored, reason: "No evaluation threshold configured")
        }
        let near = goal.bounds.nearMinimum ?? met
        let progress = met > 0 ? x / met : nil
        let status: GoalStatus
        if x >= met { status = .met } else if x >= near { status = .near } else { status = .outside }
        return result(goal: goal, status: status, progress: progress, x: x)
    }

    /// met: x <= T; near: T < x <= T+a; outside: x > T+a. A custom maximum never
    /// inherits "above goal stays green" (REG-037).
    static func evaluateMaximum(goal: GoalConfiguration, value: AggregatedMetricValue?) -> GoalEvaluation {
        guard let aggregate = value, aggregate.hasAnyObservation, let x = aggregate.numericValue else {
            return unrecordedResult(goal: goal, value: value)
        }
        guard let met = goal.bounds.metMaximum else {
            return GoalEvaluation(goalID: goal.id, status: .unscored, reason: "No evaluation threshold configured")
        }
        let near = goal.bounds.nearMaximum ?? met
        let progress = met > 0 ? x / met : nil
        let status: GoalStatus
        if x <= met { status = .met } else if x <= near { status = .near } else { status = .outside }
        return result(goal: goal, status: status, progress: progress, x: x)
    }

    /// met: L <= x <= U; near: nearLower <= x < L or U < x <= nearUpper.
    static func evaluateRange(goal: GoalConfiguration, value: AggregatedMetricValue?) -> GoalEvaluation {
        guard let aggregate = value, aggregate.hasAnyObservation, let x = aggregate.numericValue else {
            return unrecordedResult(goal: goal, value: value)
        }
        guard let lower = goal.bounds.metLower, let upper = goal.bounds.metUpper else {
            return GoalEvaluation(goalID: goal.id, status: .unscored, reason: "No evaluation range configured")
        }
        let nearLower = goal.bounds.nearLower ?? lower
        let nearUpper = goal.bounds.nearUpper ?? upper
        let midpoint = (lower + upper) / 2
        let progress = midpoint > 0 ? x / midpoint : nil
        let status: GoalStatus
        if x >= lower && x <= upper {
            status = .met
        } else if (x >= nearLower && x < lower) || (x > upper && x <= nearUpper) {
            status = .near
        } else {
            status = .outside
        }
        return result(goal: goal, status: status, progress: progress, x: x)
    }

    /// Scheduled checklist (owner supplements): met when all scheduled checks
    /// are done, near while partly done, unrecorded before any are recorded,
    /// outside only after the due window closes with missing checks (section 8.3,
    /// REG-009). Never red at breakfast because the evening dose is pending.
    static func evaluateCompletion(
        goal: GoalConfiguration,
        value: AggregatedMetricValue?,
        dateContext: GoalDateContext
    ) -> GoalEvaluation {
        let windowClosed = dueWindowClosed(goal: goal, dateContext: dateContext)
        guard let aggregate = value, aggregate.hasAnyObservation,
              let done = aggregate.checklistDone, let total = aggregate.checklistTotal, total > 0 else {
            if windowClosed {
                // A completely unlogged past day remains incomplete, not failed:
                // absence of records alone is not proof the routine was missed.
                return GoalEvaluation(goalID: goal.id, status: .unrecorded, reason: "No checks recorded")
            }
            return GoalEvaluation(goalID: goal.id, status: .unrecorded, reason: "Not started yet")
        }
        let progress = Double(done) / Double(total)
        if done >= total {
            return GoalEvaluation(goalID: goal.id, status: .met, progress: progress, reason: "All checks complete")
        }
        if windowClosed {
            return GoalEvaluation(goalID: goal.id, status: .outside, progress: progress, reason: "\(total - done) check(s) missed")
        }
        if done > 0 {
            return GoalEvaluation(goalID: goal.id, status: .near, progress: progress, reason: "\(done) of \(total) done")
        }
        return GoalEvaluation(goalID: goal.id, status: .partial, progress: progress, reason: "Recorded but none complete yet")
    }

    // MARK: - Composites

    /// ALL: any missing required input yields partial unless every member is
    /// unrecorded; ANY: one met branch satisfies the group (GOAL-008).
    /// worstStatus: outside > near > met with incomplete coverage shown as
    /// partial (GOAL-006).
    public static func evaluateComposite(
        goal: GoalConfiguration,
        memberEvaluations: [GoalEvaluation]
    ) -> GoalEvaluation {
        guard !memberEvaluations.isEmpty else {
            return GoalEvaluation(goalID: goal.id, status: .unscored, reason: "Empty composite is invalid")
        }
        let rule = goal.compositeRule ?? .allRequired
        // notScheduled and unscored members never drag a group down (GOAL-009).
        let relevant = memberEvaluations.filter { $0.status != .notScheduled && $0.status != .unscored }
        guard !relevant.isEmpty else {
            return GoalEvaluation(goalID: goal.id, status: .notScheduled, reason: "No members scheduled today")
        }
        let allUnrecorded = relevant.allSatisfy { $0.status == .unrecorded }
        if allUnrecorded {
            return GoalEvaluation(goalID: goal.id, status: .unrecorded, reason: "Nothing recorded yet")
        }

        switch rule {
        case .anyRequired:
            if relevant.contains(where: { $0.status == .met }) {
                return GoalEvaluation(goalID: goal.id, status: .met, reason: "At least one branch met")
            }
            if relevant.contains(where: { $0.status == .unrecorded || $0.status == .partial }) {
                return GoalEvaluation(goalID: goal.id, status: .partial, reason: "Waiting on unrecorded branches")
            }
            let worst = relevant.max(by: { $0.status.severity < $1.status.severity })!
            return GoalEvaluation(goalID: goal.id, status: worst.status, reason: "No branch met")
        case .allRequired, .worstStatus:
            let hasMissing = relevant.contains { $0.status == .unrecorded || $0.status == .partial }
            let evaluable = relevant.filter { $0.status.severity > 0 }
            if hasMissing && rule == .allRequired {
                // Missing required input -> partial, with details (GOAL-006/008).
                let missingNames = relevant.filter { $0.status == .unrecorded }.map { $0.goalID.rawValue }
                return GoalEvaluation(
                    goalID: goal.id,
                    status: .partial,
                    reason: missingNames.isEmpty ? "Some inputs incomplete" : "Missing: \(missingNames.joined(separator: ", "))"
                )
            }
            guard let worst = evaluable.max(by: { $0.status.severity < $1.status.severity }) else {
                return GoalEvaluation(goalID: goal.id, status: .partial, reason: "Inputs incomplete")
            }
            if hasMissing && worst.status == .met {
                // Known values fine so far, but coverage incomplete: no definitive met.
                return GoalEvaluation(goalID: goal.id, status: .partial, reason: "On track, some inputs incomplete")
            }
            return GoalEvaluation(goalID: goal.id, status: worst.status, reason: "Worst member: \(worst.goalID.rawValue)")
        case .ownerExercise:
            return GoalEvaluation(goalID: goal.id, status: .unscored, reason: "Use evaluateOwnerExercise")
        }
    }

    /// Owner exercise truth table (GOAL-007, REG-006/007/008).
    /// stepsNearMinimum defaults to the owner's 5,625.
    public static func evaluateOwnerExercise(
        goalID: GoalID,
        workoutDone: Bool?,          // nil = not recorded
        steps: Double?,              // nil = not recorded
        stepsMetMinimum: Double = 7_500,
        stepsNearMinimum: Double = 5_625
    ) -> GoalEvaluation {
        switch (workoutDone, steps) {
        case (nil, nil):
            return GoalEvaluation(goalID: goalID, status: .unrecorded, reason: "Nothing recorded yet")
        case (.some(true), .some(let s)) where s >= stepsMetMinimum:
            return GoalEvaluation(goalID: goalID, status: .met, reason: "Workout done and steps target reached")
        case (.some(true), .some):
            return GoalEvaluation(goalID: goalID, status: .near, reason: "Workout done, steps below target")
        case (.some(true), nil):
            return GoalEvaluation(goalID: goalID, status: .near, reason: "Workout done, steps not recorded")
        case (.some(false), .some(let s)), (nil, .some(let s)):
            if s >= stepsMetMinimum {
                // Workout not done but steps at target: the owner's rule caps at near.
                return GoalEvaluation(goalID: goalID, status: .near, reason: "Steps reached, workout not completed")
            }
            if s >= stepsNearMinimum {
                return GoalEvaluation(goalID: goalID, status: .near, reason: "Steps near target, workout not completed")
            }
            if workoutDone == nil {
                return GoalEvaluation(goalID: goalID, status: .near, reason: "Steps recorded, workout not recorded")
            }
            return GoalEvaluation(goalID: goalID, status: .outside, reason: "Workout not done and steps below range")
        case (.some(false), nil):
            return GoalEvaluation(goalID: goalID, status: .partial, reason: "Workout skipped, steps not recorded")
        default:
            return GoalEvaluation(goalID: goalID, status: .partial, reason: "Inputs incomplete")
        }
    }

    // MARK: - Helpers

    static func isScheduled(goal: GoalConfiguration, on context: GoalDateContext) -> Bool {
        guard !goal.schedule.weekdays.isEmpty else { return true }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = context.timeZone
        let weekday = cal.component(.weekday, from: context.logDay.startOfDay(in: context.timeZone))
        return goal.schedule.weekdays.contains(weekday)
    }

    static func dueWindowClosed(goal: GoalConfiguration, dateContext: GoalDateContext) -> Bool {
        if dateContext.isPastDay { return true }
        guard let dueMinute = goal.schedule.dueMinuteOfDay else {
            // Due at end of day: the window is open for the current day.
            return false
        }
        let dayStart = dateContext.logDay.startOfDay(in: dateContext.timeZone)
        let due = dayStart.addingTimeInterval(TimeInterval(dueMinute * 60))
        return dateContext.now > due
    }

    static func unrecordedResult(goal: GoalConfiguration, value: AggregatedMetricValue?) -> GoalEvaluation {
        if let aggregate = value, aggregate.hasAnyObservation, aggregate.coverage == .partial {
            return GoalEvaluation(goalID: goal.id, status: .partial, reason: "Recorded but incomplete")
        }
        return GoalEvaluation(goalID: goal.id, status: .unrecorded, reason: "Not recorded yet")
    }

    static func result(goal: GoalConfiguration, status: GoalStatus, progress: Double?, x: Double) -> GoalEvaluation {
        var contributing: [MetricID: Double] = [:]
        if let metricID = goal.metricID { contributing[metricID] = x }
        let reasonText: String
        switch status {
        case .met: reasonText = "Within your target"
        case .near: reasonText = "Near target"
        case .outside: reasonText = "Outside your target"
        default: reasonText = ""
        }
        return GoalEvaluation(goalID: goal.id, status: status, progress: progress, reason: reasonText, contributingValues: contributing)
    }
}
