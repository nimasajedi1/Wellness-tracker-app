import Foundation

/// P1 energy methods (ENERGY-003/004) alongside the legacy-compatible mode.
/// Selection is exclusive: sources are never blindly summed (ENERGY-005).
public enum ExpenditureMethod: Codable, Hashable, Sendable {
    /// ENERGY-001: estimated resting (manual or Mifflin-St Jeor) + logged active.
    case restingPlusActive(RestingEnergyInput)
    /// ENERGY-003: HealthKit resting/basal + active samples for the same
    /// interval. The formula estimate is never added on top of HealthKit
    /// resting energy.
    case healthKitDaily
    /// ENERGY-004: a manually supplied fixed daily expenditure. Logged active
    /// calories are displayed but only added when the user explicitly defines
    /// them as additional to the fixed total.
    case fixedDailyTotal(kcal: Double, activeIsAdditional: Bool)
}

/// Inputs a day can provide; nil always means unknown, never zero (ENERGY-006).
public struct ExpenditureInputs: Sendable, Equatable {
    /// Manually logged (or reconciled imported) daily active energy.
    public var loggedActiveKcal: Double?
    /// HealthKit resting/basal energy total for the day.
    public var healthKitRestingKcal: Double?
    /// HealthKit active energy total for the day.
    public var healthKitActiveKcal: Double?
    /// Whether the HealthKit samples cover the full day. Partial-day data must
    /// not be presented as a completed day's expenditure (ENERGY-003).
    public var healthKitCoversFullDay: Bool

    public init(
        loggedActiveKcal: Double? = nil,
        healthKitRestingKcal: Double? = nil,
        healthKitActiveKcal: Double? = nil,
        healthKitCoversFullDay: Bool = false
    ) {
        self.loggedActiveKcal = loggedActiveKcal
        self.healthKitRestingKcal = healthKitRestingKcal
        self.healthKitActiveKcal = healthKitActiveKcal
        self.healthKitCoversFullDay = healthKitCoversFullDay
    }
}

public struct ExpenditureEstimate: Sendable, Equatable {
    public var outKcal: Double?
    /// Honest label for the method (SAFE-002): never "measured TDEE".
    public var methodLabel: String
    /// The active component the method actually counted (for display).
    public var countedActiveKcal: Double?
    /// True when the method's own inputs are complete enough to finalize.
    public var inputsComplete: Bool
}

extension EnergyEngine {

    /// Estimated total out under the selected exclusive method.
    public static func estimatedOut(method: ExpenditureMethod, inputs: ExpenditureInputs) -> ExpenditureEstimate {
        switch method {
        case .restingPlusActive(let restingInput):
            let resting = restingKcal(from: restingInput)
            return ExpenditureEstimate(
                outKcal: resting + (inputs.loggedActiveKcal ?? 0),
                methodLabel: "Estimated resting + logged active energy",
                countedActiveKcal: inputs.loggedActiveKcal,
                inputsComplete: inputs.loggedActiveKcal != nil
            )
        case .healthKitDaily:
            // ENERGY-003: HealthKit resting is used as-is; no formula estimate is
            // added to it, and a missing resting total means no out figure.
            guard let resting = inputs.healthKitRestingKcal else {
                return ExpenditureEstimate(
                    outKcal: nil,
                    methodLabel: "Health data (resting + active samples)",
                    countedActiveKcal: inputs.healthKitActiveKcal,
                    inputsComplete: false
                )
            }
            return ExpenditureEstimate(
                outKcal: resting + (inputs.healthKitActiveKcal ?? 0),
                methodLabel: "Health data (resting + active samples)",
                countedActiveKcal: inputs.healthKitActiveKcal,
                inputsComplete: inputs.healthKitCoversFullDay && inputs.healthKitActiveKcal != nil
            )
        case .fixedDailyTotal(let kcal, let activeIsAdditional):
            // ENERGY-004: active calories are displayed but not added unless the
            // method explicitly defines them as additional.
            let counted = activeIsAdditional ? inputs.loggedActiveKcal : nil
            return ExpenditureEstimate(
                outKcal: kcal + (counted ?? 0),
                methodLabel: activeIsAdditional
                    ? "Fixed daily total + logged active energy"
                    : "Fixed daily total (active shown, not added)",
                countedActiveKcal: counted,
                inputsComplete: true
            )
        }
    }

    /// Generalized day evaluation over any exclusive method. Semantics match
    /// `evaluateDay(intakeKcal:...)`: provisional/gray until the intake day and
    /// the method's inputs are complete (ENERGY-007, REG-012), no reward scaling
    /// with deficit size (ENERGY-008).
    public static func evaluateDay(
        intakeKcal: Double?,
        intakeCoverageComplete: Bool,
        method: ExpenditureMethod,
        inputs: ExpenditureInputs,
        dayMarkedComplete: Bool,
        mode: BalanceGoalMode,
        liveProvisionalColoring: Bool = false
    ) -> EnergyDayResult {
        let estimate = estimatedOut(method: method, inputs: inputs)

        var net: Double? = nil
        var ratio: Double? = nil
        if let intake = intakeKcal, let out = estimate.outKcal, out > 0 {
            net = intake - out
            ratio = (intake - out) / out
        }

        let dayComplete = intakeCoverageComplete && dayMarkedComplete && estimate.inputsComplete

        var status: GoalStatus = .partial
        var explanation: String
        if intakeKcal == nil {
            status = .unrecorded
            explanation = "No intake recorded yet"
        } else if let ratio {
            let banded = balanceStatus(ratio: ratio, mode: mode)
            if dayComplete {
                status = banded
                explanation = "Day complete: net comparison final (\(estimate.methodLabel))"
            } else if liveProvisionalColoring {
                status = banded
                explanation = "Provisional: day not marked complete"
            } else {
                status = .partial
                explanation = "Provisional: complete the day's intake and activity to finalize"
            }
        } else {
            status = .partial
            explanation = "Missing inputs for \(estimate.methodLabel)"
        }

        // Resting figure only meaningful in the legacy method's display.
        var resting: Double? = nil
        if case .restingPlusActive(let input) = method { resting = restingKcal(from: input) }
        if case .healthKitDaily = method { resting = inputs.healthKitRestingKcal }

        return EnergyDayResult(
            intakeKcal: intakeKcal,
            restingKcal: resting,
            activeKcal: estimate.countedActiveKcal,
            estimatedOutKcal: estimate.outKcal,
            netKcal: net,
            balanceRatio: ratio,
            status: status,
            isProvisional: !dayComplete,
            explanation: explanation
        )
    }
}
