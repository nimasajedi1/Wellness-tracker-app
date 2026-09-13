import Foundation

/// Resting-energy equation selection is an explicit user choice, never inferred
/// from a name or photo (ENERGY-002).
public enum RestingEquationConstant: Double, Codable, Sendable {
    case maleEquation = 5
    case femaleEquation = -161
}

public struct EnergyProfile: Codable, Hashable, Sendable {
    public var weightKg: Double
    public var heightCm: Double
    public var ageYears: Double
    public var equationConstant: RestingEquationConstant

    public init(weightKg: Double, heightCm: Double, ageYears: Double, equationConstant: RestingEquationConstant) {
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.ageYears = ageYears
        self.equationConstant = equationConstant
    }
}

public enum RestingEnergyInput: Codable, Hashable, Sendable {
    /// User-entered daily resting estimate in kcal.
    case manual(Double)
    /// Mifflin-St Jeor estimate from a reviewed profile (ENERGY-002, S14).
    case formula(EnergyProfile)
}

public enum BalanceGoalMode: String, Codable, Sendable {
    case weightLoss
    case maintenance
    case weightGain
}

/// Result of the day's energy accounting. All estimate labels are explicit:
/// "estimated resting + logged active energy" is not measured TDEE (ENERGY-001).
public struct EnergyDayResult: Sendable, Equatable {
    public var intakeKcal: Double?
    public var restingKcal: Double?
    public var activeKcal: Double?          // nil = unknown, distinct from 0 (ENERGY-006)
    public var estimatedOutKcal: Double?
    public var netKcal: Double?
    public var balanceRatio: Double?        // (intake - out) / out
    public var status: GoalStatus
    /// True until intake day and activity input are marked complete (ENERGY-007).
    public var isProvisional: Bool
    public var explanation: String
}

public enum EnergyEngine {

    /// Mifflin-St Jeor: 10*kg + 6.25*cm - 5*age + constant (REG-014: the
    /// reference profile yields exactly 1,882.5 kcal/day before display rounding).
    public static func restingEstimate(profile: EnergyProfile) -> Double {
        10 * profile.weightKg + 6.25 * profile.heightCm - 5 * profile.ageYears + profile.equationConstant.rawValue
    }

    public static func restingKcal(from input: RestingEnergyInput) -> Double {
        switch input {
        case .manual(let value): return value
        case .formula(let profile): return restingEstimate(profile: profile)
        }
    }

    /// Owner legacy comparison bands (section 9.4, REG-011):
    /// weight loss — met r < -0.05; near -0.05 <= r <= 0.05; outside r > 0.05.
    /// All three exact boundaries -0.05, 0, +0.05 evaluate near.
    public static func balanceStatus(ratio: Double, mode: BalanceGoalMode, nearBand: Double = 0.05) -> GoalStatus {
        switch mode {
        case .weightLoss:
            if ratio < -nearBand { return .met }
            if ratio <= nearBand { return .near }
            return .outside
        case .weightGain:
            if ratio > nearBand { return .met }
            if ratio >= -nearBand { return .near }
            return .outside
        case .maintenance:
            if abs(ratio) <= nearBand { return .met }
            if abs(ratio) <= nearBand * 2 { return .near }
            return .outside
        }
    }

    /// Full day accounting under the legacy-compatible method (ENERGY-001):
    /// estimatedOut = resting + active, net = intake - estimatedOut.
    /// The result stays provisional/gray until the day is marked complete
    /// (ENERGY-007, REG-012); no reward scales with deficit size (ENERGY-008).
    public static func evaluateDay(
        intakeKcal: Double?,
        intakeCoverageComplete: Bool,
        restingInput: RestingEnergyInput?,
        activeKcal: Double?,
        activeConfirmed: Bool,
        mode: BalanceGoalMode,
        liveProvisionalColoring: Bool = false
    ) -> EnergyDayResult {
        let resting = restingInput.map(restingKcal(from:))

        var out: Double? = nil
        if let resting {
            // Unknown active energy: the resting-only figure is a baseline, not a
            // complete activity total (ENERGY-006). Confirmed zero is valid data.
            out = resting + (activeKcal ?? 0)
        }

        var net: Double? = nil
        var ratio: Double? = nil
        if let intake = intakeKcal, let out, out > 0 {
            net = intake - out
            ratio = (intake - out) / out
        }

        let dayComplete = intakeCoverageComplete && (activeKcal != nil ? activeConfirmed : false)

        var status: GoalStatus = .partial
        var explanation: String
        if intakeKcal == nil {
            status = .unrecorded
            explanation = "No intake recorded yet"
        } else if let ratio {
            let banded = balanceStatus(ratio: ratio, mode: mode)
            if dayComplete {
                status = banded
                explanation = "Day complete: net comparison final"
            } else if liveProvisionalColoring {
                status = banded
                explanation = "Provisional: day not marked complete"
            } else {
                status = .partial
                explanation = "Provisional: complete the day's intake and activity to finalize"
            }
        } else {
            status = .partial
            explanation = "Resting estimate or intake missing"
        }

        return EnergyDayResult(
            intakeKcal: intakeKcal,
            restingKcal: resting,
            activeKcal: activeKcal,
            estimatedOutKcal: out,
            netKcal: net,
            balanceRatio: ratio,
            status: status,
            isProvisional: !dayComplete,
            explanation: explanation
        )
    }

    /// Exclusive active-energy source selection (ENERGY-005, REG-013): when a
    /// workout's reported energy is already part of the selected daily total,
    /// it must not be added again. A workout completion flag alone never
    /// creates calories.
    public static func resolveActiveEnergy(
        selectedDailyTotalKcal: Double?,
        workoutComponentKcal: Double?,
        workoutIncludedInTotal: Bool
    ) -> Double? {
        guard let total = selectedDailyTotalKcal else {
            // No daily total selected; a standalone workout component may serve
            // as the day's active energy if the user chose that source.
            return workoutComponentKcal
        }
        if workoutIncludedInTotal {
            return total
        }
        return total + (workoutComponentKcal ?? 0)
    }
}
