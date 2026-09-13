import XCTest
@testable import WellnessCore

final class GoalEvaluatorTests: XCTestCase {

    let day = LogDay(year: 2026, month: 9, day: 13)
    lazy var context = GoalDateContext(
        logDay: day,
        now: day.startOfDay(in: .utcTest).addingTimeInterval(12 * 3600),
        timeZone: .utcTest,
        isPastDay: false
    )

    func aggregated(_ metricID: MetricID, _ value: Double?) -> AggregatedMetricValue {
        guard let value else { return .unrecorded(metricID) }
        return AggregatedMetricValue(metricID: metricID, numericValue: value, coverage: .complete)
    }

    func ownerGoal(_ id: GoalID) -> GoalConfiguration {
        OwnerTemplate.goals().first { $0.id == id }!
    }

    // REG-001: fresh day, no observation -> unrecorded, never a confirmed zero.
    func testFreshDayIsUnrecorded() {
        let result = GoalEvaluator.evaluate(goal: ownerGoal(OwnerGoals.water), value: nil, dateContext: context)
        XCTAssertEqual(result.status, .unrecorded)
    }

    // REG-002: explicit zero water is known data and evaluated.
    func testExplicitZeroIsEvaluated() {
        let result = GoalEvaluator.evaluate(goal: ownerGoal(OwnerGoals.water), value: aggregated(OwnerMetrics.water, 0), dateContext: context)
        XCTAssertEqual(result.status, .outside)
    }

    // REG-003: water 1.9 L near, 2.0 met, 3.0 met — no hidden 5% tolerance.
    func testWaterExactBoundaries() {
        let goal = ownerGoal(OwnerGoals.water)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated(OwnerMetrics.water, 1900), dateContext: context).status, .near)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated(OwnerMetrics.water, 2000), dateContext: context).status, .met)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated(OwnerMetrics.water, 3000), dateContext: context).status, .met)
    }

    // REG-004: protein 129 near, 130 met, 170 met; display 140-150 does not
    // alter the explicit 130 threshold.
    func testProteinExactBoundaries() {
        let goal = ownerGoal(OwnerGoals.protein)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated(OwnerMetrics.protein, 129), dateContext: context).status, .near)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated(OwnerMetrics.protein, 130), dateContext: context).status, .met)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated(OwnerMetrics.protein, 170), dateContext: context).status, .met)
        XCTAssertEqual(goal.displayTarget?.lower, 140)
        XCTAssertEqual(goal.displayTarget?.upper, 150)
    }

    // REG-005: fiber 33.24 near, 33.25 met (explicitly retained tolerance).
    func testFiberBoundaries() {
        let goal = ownerGoal(OwnerGoals.fiber)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated(OwnerMetrics.fiber, 33.24), dateContext: context).status, .near)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated(OwnerMetrics.fiber, 33.25), dateContext: context).status, .met)
    }

    // Owner calorie range band boundaries.
    func testCalorieRangeBoundaries() {
        let goal = ownerGoal(OwnerGoals.calories)
        let cases: [(Double, GoalStatus)] = [
            (1894.99, .near), (1895, .met), (2305, .met), (2305.01, .near),
            (1474.99, .outside), (1475, .near), (2725, .near), (2725.01, .outside)
        ]
        for (value, expected) in cases {
            XCTAssertEqual(
                GoalEvaluator.evaluate(goal: goal, value: aggregated(OwnerMetrics.calories, value), dateContext: context).status,
                expected, "calories \(value)"
            )
        }
    }

    // Sleep boundaries: met >= 456 min, near 360..<456, outside < 360.
    func testSleepBoundaries() {
        let goal = ownerGoal(OwnerGoals.sleep)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated(OwnerMetrics.sleep, 455.9), dateContext: context).status, .near)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated(OwnerMetrics.sleep, 456), dateContext: context).status, .met)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated(OwnerMetrics.sleep, 359.9), dateContext: context).status, .outside)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated(OwnerMetrics.sleep, 600), dateContext: context).status, .met)
    }

    // Fasting: no reward for fasting longer — above 1,200 is outside.
    func testFastingRangeNoOvershootReward() {
        let goal = ownerGoal(OwnerGoals.fasting)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated(OwnerMetrics.fasting, 960), dateContext: context).status, .met)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated(OwnerMetrics.fasting, 1100), dateContext: context).status, .near)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated(OwnerMetrics.fasting, 1300), dateContext: context).status, .outside)
    }

    // REG-006/007/008 + GOAL-007 truth table.
    func testOwnerExerciseTruthTable() {
        XCTAssertEqual(GoalEvaluator.evaluateOwnerExercise(goalID: OwnerGoals.exercise, workoutDone: nil, steps: nil).status, .unrecorded)
        XCTAssertEqual(GoalEvaluator.evaluateOwnerExercise(goalID: OwnerGoals.exercise, workoutDone: true, steps: 7500).status, .met)
        XCTAssertEqual(GoalEvaluator.evaluateOwnerExercise(goalID: OwnerGoals.exercise, workoutDone: true, steps: 7499).status, .near)
    }

    // REG-006: 12,000 steps + workout done -> met (overshoot not a failure).
    func testExerciseOvershootStaysMet() {
        XCTAssertEqual(GoalEvaluator.evaluateOwnerExercise(goalID: OwnerGoals.exercise, workoutDone: true, steps: 12000).status, .met)
    }

    // REG-007: 8,000 steps, workout not completed -> near.
    func testStepsWithoutWorkoutIsNear() {
        XCTAssertEqual(GoalEvaluator.evaluateOwnerExercise(goalID: OwnerGoals.exercise, workoutDone: false, steps: 8000).status, .near)
    }

    // REG-008: workout done, no steps -> near with missing-steps explanation.
    func testWorkoutWithoutStepsIsNearWithReason() {
        let result = GoalEvaluator.evaluateOwnerExercise(goalID: OwnerGoals.exercise, workoutDone: true, steps: nil)
        XCTAssertEqual(result.status, .near)
        XCTAssertTrue(result.reason.lowercased().contains("steps"))
    }

    func testExerciseOutsideRow() {
        XCTAssertEqual(GoalEvaluator.evaluateOwnerExercise(goalID: OwnerGoals.exercise, workoutDone: false, steps: 5000).status, .outside)
        XCTAssertEqual(GoalEvaluator.evaluateOwnerExercise(goalID: OwnerGoals.exercise, workoutDone: false, steps: 5625).status, .near)
    }

    // REG-009: new morning, PM not due -> no red failure.
    func testSupplementsNotRedBeforeDue() {
        let goal = ownerGoal(OwnerGoals.supplements)
        let value = AggregatedMetricValue(
            metricID: OwnerMetrics.supplements, numericValue: 0.5, coverage: .complete,
            checklistDone: 1, checklistTotal: 2
        )
        let result = GoalEvaluator.evaluate(goal: goal, value: value, dateContext: context)
        XCTAssertEqual(result.status, .near)

        // After the window closes (past day), missing checks become outside.
        let pastContext = GoalDateContext(logDay: day, now: context.now, timeZone: .utcTest, isPastDay: true)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: value, dateContext: pastContext).status, .outside)

        // A completely unlogged past day stays incomplete, not failed.
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: nil, dateContext: pastContext).status, .unrecorded)
    }

    // REG-037: a custom maximum never inherits minimum-goal overshoot behavior.
    func testCustomMaximumGoal() {
        let goal = GoalConfiguration(
            id: "goal.caffeine", metricID: "custom.caffeine",
            kind: .maximum,
            bounds: EvaluationBounds(metMaximum: 300, nearMaximum: 360)
        )
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated("custom.caffeine", 300), dateContext: context).status, .met)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated("custom.caffeine", 301), dateContext: context).status, .near)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated("custom.caffeine", 400), dateContext: context).status, .outside)
    }

    // REG-038: trend-only field has no red/green outcome.
    func testTrendOnlyIsUnscored() {
        let goal = GoalConfiguration(id: "goal.weight", metricID: "body.weight", kind: .trendOnly)
        XCTAssertEqual(GoalEvaluator.evaluate(goal: goal, value: aggregated("body.weight", 93), dateContext: context).status, .unscored)
    }

    // GOAL-006: nutrition group worst-status with incomplete coverage -> partial.
    func testCompositeWorstStatus() {
        let members = [
            GoalEvaluation(goalID: OwnerGoals.protein, status: .met),
            GoalEvaluation(goalID: OwnerGoals.fiber, status: .near),
            GoalEvaluation(goalID: OwnerGoals.calories, status: .met)
        ]
        let group = GoalConfiguration(
            id: OwnerGoals.nutritionGroup, metricID: nil, kind: .composite,
            memberGoalIDs: [OwnerGoals.protein, OwnerGoals.fiber, OwnerGoals.calories],
            compositeRule: .worstStatus
        )
        XCTAssertEqual(GoalEvaluator.evaluateComposite(goal: group, memberEvaluations: members).status, .near)

        let withMissing = members + [GoalEvaluation(goalID: "goal.sodium", status: .unrecorded)]
        let result = GoalEvaluator.evaluateComposite(goal: group, memberEvaluations: withMissing)
        XCTAssertEqual(result.status, .near) // worst evaluable wins; near is not upgraded

        // All-met with a missing member cannot claim definitive met.
        let metWithMissing = [
            GoalEvaluation(goalID: OwnerGoals.protein, status: .met),
            GoalEvaluation(goalID: "goal.sodium", status: .unrecorded)
        ]
        XCTAssertEqual(GoalEvaluator.evaluateComposite(goal: group, memberEvaluations: metWithMissing).status, .partial)
    }

    // GOAL-008: ANY composite met by one branch; empty composite invalid.
    func testAnyCompositeAndEmpty() {
        let group = GoalConfiguration(
            id: "goal.any", metricID: nil, kind: .composite,
            memberGoalIDs: ["goal.a", "goal.b"], compositeRule: .anyRequired
        )
        let members = [
            GoalEvaluation(goalID: "goal.a", status: .outside),
            GoalEvaluation(goalID: "goal.b", status: .met)
        ]
        XCTAssertEqual(GoalEvaluator.evaluateComposite(goal: group, memberEvaluations: members).status, .met)
        XCTAssertEqual(GoalEvaluator.evaluateComposite(goal: group, memberEvaluations: []).status, .unscored)
    }
}

extension TimeZone {
    static let utcTest = TimeZone(identifier: "UTC")!
}
