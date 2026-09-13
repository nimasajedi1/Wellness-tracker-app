import Foundation

/// Well-known metric IDs used by the owner template. Templates are views over
/// these canonical IDs (BUILD-013); other templates may reference the same IDs.
public enum OwnerMetrics {
    public static let sleep: MetricID = "sleep.interval"
    public static let fasting: MetricID = "fasting.interval"
    public static let protein: MetricID = "nutrition.protein"
    public static let fiber: MetricID = "nutrition.fiber"
    public static let calories: MetricID = "nutrition.energy"
    public static let water: MetricID = "hydration.water"
    public static let steps: MetricID = "activity.steps"
    public static let workoutDone: MetricID = "activity.workoutDone"
    public static let activeEnergy: MetricID = "activity.activeEnergy"
    public static let supplements: MetricID = "routines.supplements"
}

public enum OwnerGoals {
    public static let sleep: GoalID = "goal.sleep"
    public static let fasting: GoalID = "goal.fasting"
    public static let protein: GoalID = "goal.protein"
    public static let fiber: GoalID = "goal.fiber"
    public static let calories: GoalID = "goal.calories"
    public static let water: GoalID = "goal.water"
    public static let steps: GoalID = "goal.steps"
    public static let exercise: GoalID = "goal.exercise"
    public static let nutritionGroup: GoalID = "goal.nutritionGroup"
    public static let supplements: GoalID = "goal.supplements"
    public static let calorieBalance: GoalID = "goal.calorieBalance"
}

/// The owner's template with the exact defaults of PRD section 8.3. These are
/// the owner's previously selected preferences, seed values requiring
/// confirmation for anyone else — not general health recommendations.
public enum OwnerTemplate {

    public static func configuration(effectiveFrom: LogDay) -> TrackerConfiguration {
        TrackerConfiguration(
            templateID: "owner",
            version: 1,
            name: "Owner",
            effectiveFrom: effectiveFrom,
            metrics: metrics(),
            goals: goals(),
            layout: layout()
        )
    }

    public static func metrics() -> [MetricDefinition] {
        [
            MetricDefinition(
                id: OwnerMetrics.sleep, name: "Sleep", category: "sleepRecovery",
                valueType: .interval, canonicalUnit: .minute,
                aggregation: .durationUnion,
                input: MetricInputConfig(kind: .intervalEditor)
            ),
            MetricDefinition(
                id: OwnerMetrics.fasting, name: "Fasting", category: "mealTiming",
                valueType: .interval, canonicalUnit: .minute,
                aggregation: .durationUnion,
                input: MetricInputConfig(kind: .intervalEditor)
            ),
            MetricDefinition(
                id: OwnerMetrics.protein, name: "Protein", category: "nutrition",
                valueType: .quantity, canonicalUnit: .gram,
                aggregation: .sum,
                input: MetricInputConfig(kind: .counter, step: 10)   // UI-006
            ),
            MetricDefinition(
                id: OwnerMetrics.fiber, name: "Fiber", category: "nutrition",
                valueType: .quantity, canonicalUnit: .gram,
                aggregation: .sum,
                input: MetricInputConfig(kind: .counter, step: 5)
            ),
            MetricDefinition(
                id: OwnerMetrics.calories, name: "Calories", category: "nutrition",
                valueType: .quantity, canonicalUnit: .kilocalorie,
                aggregation: .sum,
                input: MetricInputConfig(kind: .counter, step: 100)
            ),
            MetricDefinition(
                id: OwnerMetrics.water, name: "Water", category: "hydration",
                valueType: .quantity, canonicalUnit: .milliliter, displayUnit: .liter,
                aggregation: .sum,
                input: MetricInputConfig(kind: .counter, step: 250)
            ),
            MetricDefinition(
                id: OwnerMetrics.steps, name: "Steps", category: "movementFitness",
                valueType: .countValue, canonicalUnit: .step,
                aggregation: .sum,
                input: MetricInputConfig(kind: .counter, step: 500)
            ),
            MetricDefinition(
                id: OwnerMetrics.workoutDone, name: "Workout", category: "movementFitness",
                valueType: .boolean,
                aggregation: .lastObservation,
                input: MetricInputConfig(kind: .toggle)
            ),
            MetricDefinition(
                id: OwnerMetrics.activeEnergy, name: "Active energy", category: "movementFitness",
                valueType: .quantity, canonicalUnit: .kilocalorie,
                aggregation: .sum,
                input: MetricInputConfig(kind: .counter, step: 50)
            ),
            MetricDefinition(
                id: OwnerMetrics.supplements, name: "Supplements", category: "routines",
                valueType: .checklist,
                aggregation: .checklistCompletion,
                input: MetricInputConfig(kind: .checklist),
                checklistItems: ["AM", "PM"]   // UI-007: "Supplements", never "pills"
            )
        ]
    }

    public static func goals() -> [GoalConfiguration] {
        [
            // Sleep: display 8 h; met >= 456 min, near 360..<456, outside < 360.
            GoalConfiguration(
                id: OwnerGoals.sleep, metricID: OwnerMetrics.sleep,
                kind: .minimum,
                displayTarget: DisplayTarget(exact: 480, unit: .minute),
                bounds: EvaluationBounds(metMinimum: 456, nearMinimum: 360)
            ),
            // Fasting: optional; met 912-1,008; near 720..<912 or >1,008..1,200.
            // No reward for fasting longer (section 8.3, SAFE-003).
            GoalConfiguration(
                id: OwnerGoals.fasting, metricID: OwnerMetrics.fasting,
                kind: .range,
                displayTarget: DisplayTarget(exact: 960, unit: .minute),
                bounds: EvaluationBounds(metLower: 912, metUpper: 1008, nearLower: 720, nearUpper: 1200),
                missingPolicy: .ignoreIfOptional
            ),
            // Protein: display 140-150 g; met >= 130 exactly (legacy 5% band
            // deliberately removed), near 97.5..<130.
            GoalConfiguration(
                id: OwnerGoals.protein, metricID: OwnerMetrics.protein,
                kind: .minimum,
                displayTarget: DisplayTarget(lower: 140, upper: 150, unit: .gram),
                bounds: EvaluationBounds(metMinimum: 130, nearMinimum: 97.5)
            ),
            // Fiber: display 35 g; met >= 33.25 (explicit retained tolerance).
            GoalConfiguration(
                id: OwnerGoals.fiber, metricID: OwnerMetrics.fiber,
                kind: .minimum,
                displayTarget: DisplayTarget(exact: 35, unit: .gram),
                bounds: EvaluationBounds(metMinimum: 33.25, nearMinimum: 26.25)
            ),
            // Calories: display 2,000-2,200; met 1,895-2,305; near 1,475..<1,895
            // or >2,305..2,725 (legacy midpoint-based tolerance, editable).
            GoalConfiguration(
                id: OwnerGoals.calories, metricID: OwnerMetrics.calories,
                kind: .range,
                displayTarget: DisplayTarget(lower: 2000, upper: 2200, unit: .kilocalorie),
                bounds: EvaluationBounds(metLower: 1895, metUpper: 2305, nearLower: 1475, nearUpper: 2725)
            ),
            // Water: display 2-2.5 L; met >= 2,000 mL exactly (legacy tolerance
            // deliberately removed), near 1,500..<2,000.
            GoalConfiguration(
                id: OwnerGoals.water, metricID: OwnerMetrics.water,
                kind: .minimum,
                displayTarget: DisplayTarget(lower: 2000, upper: 2500, unit: .milliliter),
                bounds: EvaluationBounds(metMinimum: 2000, nearMinimum: 1500)
            ),
            // Steps: display 7,500-10,000; individual goal met >= 7,500.
            GoalConfiguration(
                id: OwnerGoals.steps, metricID: OwnerMetrics.steps,
                kind: .minimum,
                displayTarget: DisplayTarget(lower: 7500, upper: 10000, unit: .step),
                bounds: EvaluationBounds(metMinimum: 7500, nearMinimum: 5625)
            ),
            // Exercise group: owner truth table (GOAL-007), evaluated via
            // GoalEvaluator.evaluateOwnerExercise.
            GoalConfiguration(
                id: OwnerGoals.exercise, metricID: nil,
                kind: .composite,
                memberGoalIDs: [OwnerGoals.steps],
                compositeRule: .ownerExercise
            ),
            // Nutrition group: worst evaluable status of required members (GOAL-006).
            GoalConfiguration(
                id: OwnerGoals.nutritionGroup, metricID: nil,
                kind: .composite,
                memberGoalIDs: [OwnerGoals.protein, OwnerGoals.fiber, OwnerGoals.calories],
                compositeRule: .worstStatus
            ),
            // Supplements: scheduled completion; due end of day (section 8.3).
            GoalConfiguration(
                id: OwnerGoals.supplements, metricID: OwnerMetrics.supplements,
                kind: .completion
            ),
            // Calorie balance: legacy weight-loss band, provisional by default
            // (ENERGY-007); evaluated by EnergyEngine, configured here for layout.
            GoalConfiguration(
                id: OwnerGoals.calorieBalance, metricID: nil,
                kind: .composite,
                memberGoalIDs: [OwnerGoals.calories],
                compositeRule: .worstStatus
            )
        ]
    }

    /// Owner layout: seven indicators; calorie balance always full-width in its
    /// own final row (UI-005, REG-010).
    public static func layout() -> [LayoutCard] {
        [
            LayoutCard(cardID: "card.sleepFasting", title: "Sleep & fasting",
                       metricIDs: [OwnerMetrics.sleep, OwnerMetrics.fasting],
                       goalIDs: [OwnerGoals.sleep, OwnerGoals.fasting],
                       width: .half, order: 0),
            LayoutCard(cardID: "card.nutrition", title: "Nutrition",
                       metricIDs: [OwnerMetrics.protein, OwnerMetrics.fiber, OwnerMetrics.calories],
                       goalIDs: [OwnerGoals.nutritionGroup],
                       width: .half, order: 1),
            LayoutCard(cardID: "card.hydration", title: "Hydration",
                       metricIDs: [OwnerMetrics.water],
                       goalIDs: [OwnerGoals.water],
                       width: .half, order: 2),
            LayoutCard(cardID: "card.activity", title: "Activity",
                       metricIDs: [OwnerMetrics.steps, OwnerMetrics.workoutDone, OwnerMetrics.activeEnergy],
                       goalIDs: [OwnerGoals.exercise],
                       width: .half, order: 3),
            LayoutCard(cardID: "card.supplements", title: "Supplements",
                       metricIDs: [OwnerMetrics.supplements],
                       goalIDs: [OwnerGoals.supplements],
                       width: .full, order: 4),
            LayoutCard(cardID: "card.calorieBalance", title: "Calorie balance",
                       metricIDs: [OwnerMetrics.calories, OwnerMetrics.activeEnergy],
                       goalIDs: [OwnerGoals.calorieBalance],
                       width: .full, order: 5)
        ]
    }

    /// Other starter templates (BUILD-001). Configurable preferences, not
    /// prescriptions; all reference the same canonical metric IDs.
    public static func minimalDay(effectiveFrom: LogDay) -> TrackerConfiguration {
        var config = configuration(effectiveFrom: effectiveFrom)
        config.templateID = "minimalDay"
        config.name = "Minimal day"
        config.hiddenMetricIDs = [OwnerMetrics.fasting, OwnerMetrics.activeEnergy, OwnerMetrics.supplements]
        config.layout = config.layout.filter { !["card.supplements", "card.calorieBalance"].contains($0.cardID) }
        return config
    }

    public static func blank(effectiveFrom: LogDay) -> TrackerConfiguration {
        TrackerConfiguration(
            templateID: "blank", version: 1, name: "Blank",
            effectiveFrom: effectiveFrom, metrics: [], goals: [], layout: []
        )
    }
}
