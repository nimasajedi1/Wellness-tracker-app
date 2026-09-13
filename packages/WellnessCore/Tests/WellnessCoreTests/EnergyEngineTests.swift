import XCTest
@testable import WellnessCore

final class EnergyEngineTests: XCTestCase {

    // REG-014: 93 kg, 178 cm, age 33, male equation -> exactly 1,882.5 kcal/day.
    func testMifflinStJeorReferenceProfile() {
        let profile = EnergyProfile(weightKg: 93, heightCm: 178, ageYears: 33, equationConstant: .maleEquation)
        XCTAssertEqual(EnergyEngine.restingEstimate(profile: profile), 1882.5, accuracy: 1e-9)
    }

    // REG-011: ratios exactly -0.05, 0, +0.05 are all near; below -0.05 met,
    // above +0.05 outside (weight-loss mode).
    func testBalanceBandBoundaries() {
        XCTAssertEqual(EnergyEngine.balanceStatus(ratio: -0.05, mode: .weightLoss), .near)
        XCTAssertEqual(EnergyEngine.balanceStatus(ratio: 0, mode: .weightLoss), .near)
        XCTAssertEqual(EnergyEngine.balanceStatus(ratio: 0.05, mode: .weightLoss), .near)
        XCTAssertEqual(EnergyEngine.balanceStatus(ratio: -0.0501, mode: .weightLoss), .met)
        XCTAssertEqual(EnergyEngine.balanceStatus(ratio: 0.0501, mode: .weightLoss), .outside)
    }

    func testWeightGainReversesOuterBands() {
        XCTAssertEqual(EnergyEngine.balanceStatus(ratio: 0.1, mode: .weightGain), .met)
        XCTAssertEqual(EnergyEngine.balanceStatus(ratio: -0.1, mode: .weightGain), .outside)
        XCTAssertEqual(EnergyEngine.balanceStatus(ratio: 0, mode: .weightGain), .near)
    }

    // REG-012: intake logged but day incomplete -> provisional/partial, not a
    // silently final deficit.
    func testIncompleteDayIsProvisional() {
        let result = EnergyEngine.evaluateDay(
            intakeKcal: 800,
            intakeCoverageComplete: false,
            restingInput: .manual(1883),
            activeKcal: nil,
            activeConfirmed: false,
            mode: .weightLoss
        )
        XCTAssertEqual(result.status, .partial)
        XCTAssertTrue(result.isProvisional)
        // REG-056: no encouraging deficit message for a partial low intake.
        XCTAssertFalse(result.explanation.lowercased().contains("excellent"))
        XCTAssertFalse(result.explanation.lowercased().contains("deficit"))
    }

    func testCompleteDayGetsFinalBand() {
        let result = EnergyEngine.evaluateDay(
            intakeKcal: 1850,
            intakeCoverageComplete: true,
            restingInput: .formula(EnergyProfile(weightKg: 93, heightCm: 178, ageYears: 33, equationConstant: .maleEquation)),
            activeKcal: 500,
            activeConfirmed: true,
            mode: .weightLoss
        )
        // out = 1882.5 + 500 = 2382.5; ratio = (1850 - 2382.5)/2382.5 ≈ -0.2235 -> met.
        XCTAssertEqual(result.status, .met)
        XCTAssertFalse(result.isProvisional)
        XCTAssertEqual(result.estimatedOutKcal!, 2382.5, accuracy: 1e-9)
        XCTAssertEqual(result.netKcal!, -532.5, accuracy: 1e-9)
    }

    // ENERGY-006: unknown active energy leaves the day provisional even with
    // complete intake — a resting-only figure is not a complete activity total.
    func testUnknownActiveEnergyStaysProvisional() {
        let result = EnergyEngine.evaluateDay(
            intakeKcal: 1850,
            intakeCoverageComplete: true,
            restingInput: .manual(1883),
            activeKcal: nil,
            activeConfirmed: false,
            mode: .weightLoss
        )
        XCTAssertTrue(result.isProvisional)
        XCTAssertEqual(result.status, .partial)
    }

    // REG-013 / ENERGY-005: imported 500 kcal total + 250 kcal workout already
    // included -> active energy stays 500.
    func testNoDoubleCountingWorkoutEnergy() {
        XCTAssertEqual(
            EnergyEngine.resolveActiveEnergy(selectedDailyTotalKcal: 500, workoutComponentKcal: 250, workoutIncludedInTotal: true),
            500
        )
        XCTAssertEqual(
            EnergyEngine.resolveActiveEnergy(selectedDailyTotalKcal: 500, workoutComponentKcal: 250, workoutIncludedInTotal: false),
            750
        )
        // A workout completion flag alone never creates calories.
        XCTAssertNil(EnergyEngine.resolveActiveEnergy(selectedDailyTotalKcal: nil, workoutComponentKcal: nil, workoutIncludedInTotal: false))
    }
}
