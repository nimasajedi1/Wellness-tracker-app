import XCTest
@testable import WellnessCore

final class PortionEngineTests: XCTestCase {

    /// Ham label transcription fixture [U01]: 60 kcal, 9 g protein per 56 g serving.
    var ham: FoodVersion {
        FoodVersion(
            foodID: "fixture-ham",
            versionID: "1",
            canonicalName: "Sliced ham (label fixture)",
            basis: .namedServing(name: "1 serving", massG: 56, volumeML: nil),
            nutrients: [
                .energyKcal: .known(60),
                .proteinG: .known(9),
                .fiberG: .unknown(reason: "Not reported by source")
            ],
            evidence: SourceEvidence(sourceID: "U01", evidenceType: .userEnteredLabel)
        )
    }

    func doubleValue(_ value: NutrientValue) -> Double? {
        value.decimalValue.map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    // REG-025: 112 g -> 120 kcal / 18 g protein.
    func testExactMassScaling() throws {
        let scaled = try PortionEngine.scale(food: ham, portion: PortionRequest(.mass(112, .gram)))
        XCTAssertEqual(doubleValue(scaled.value(.energyKcal))!, 120, accuracy: 1e-9)
        XCTAssertEqual(doubleValue(scaled.value(.proteinG))!, 18, accuracy: 1e-9)
    }

    // REG-026: exact 4 oz = 113.3980925 g -> ~121.49795625 kcal / ~18.2247 g
    // protein before display rounding. Never silently equated to two servings.
    func testExactOunceConversion() throws {
        let scaled = try PortionEngine.scale(food: ham, portion: PortionRequest(.mass(4, .ounceMass)))
        XCTAssertEqual(NSDecimalNumber(decimal: scaled.resolvedMassG!).doubleValue, 113.3980925, accuracy: 1e-7)
        XCTAssertEqual(doubleValue(scaled.value(.energyKcal))!, 121.49795625, accuracy: 1e-6)
        XCTAssertEqual(doubleValue(scaled.value(.proteinG))!, 18.22469344, accuracy: 1e-6)
    }

    // FOOD-008: two label servings use exactly twice the serving nutrients.
    func testLabelServings() throws {
        let scaled = try PortionEngine.scale(food: ham, portion: PortionRequest(.servings(2)))
        XCTAssertEqual(doubleValue(scaled.value(.energyKcal))!, 120, accuracy: 1e-9)
        XCTAssertEqual(doubleValue(scaled.value(.proteinG))!, 18, accuracy: 1e-9)
    }

    // Shake fixture [U02]: 130 kcal / 30 g protein / 1 g fiber per container;
    // two containers double every known nutrient.
    func testShakeFixture() throws {
        let shake = FoodVersion(
            foodID: "fixture-shake", versionID: "1", canonicalName: "Protein shake (label fixture)",
            basis: .namedServing(name: "1 container", massG: nil, volumeML: nil),
            nutrients: [.energyKcal: .known(130), .proteinG: .known(30), .fiberG: .known(1)],
            evidence: SourceEvidence(sourceID: "U02", evidenceType: .userEnteredLabel)
        )
        let scaled = try PortionEngine.scale(food: shake, portion: PortionRequest(.servings(2)))
        XCTAssertEqual(doubleValue(scaled.value(.energyKcal))!, 260, accuracy: 1e-9)
        XCTAssertEqual(doubleValue(scaled.value(.proteinG))!, 60, accuracy: 1e-9)
        XCTAssertEqual(doubleValue(scaled.value(.fiberG))!, 2, accuracy: 1e-9)
    }

    // REG-029 / FOOD-002: unknown fiber stays unknown after scaling and makes
    // the summed coverage partial, never zero.
    func testUnknownNutrientStaysUnknown() throws {
        let scaled = try PortionEngine.scale(food: ham, portion: PortionRequest(.mass(112, .gram)))
        XCTAssertFalse(scaled.value(.fiberG).isKnown)

        let beans = FoodVersion(
            foodID: "fixture-beans", versionID: "1", canonicalName: "Beans (synthetic)",
            basis: .per100g,
            nutrients: [.energyKcal: .known(120), .fiberG: .known(5)],
            evidence: SourceEvidence(sourceID: "syn", evidenceType: .syntheticFixture)
        )
        let beansScaled = try PortionEngine.scale(food: beans, portion: PortionRequest(.mass(100, .gram)))
        let totals = PortionEngine.sum([scaled, beansScaled], nutrientIDs: [.energyKcal, .fiberG])
        XCTAssertEqual(NSDecimalNumber(decimal: totals[.fiberG]!.total).doubleValue, 5, accuracy: 1e-9)
        XCTAssertEqual(totals[.fiberG]!.coverage, .partial)
        XCTAssertEqual(totals[.energyKcal]!.coverage, .complete)
    }

    // FOOD-006: volume cannot silently convert to a mass basis.
    func testVolumeToMassRejected() {
        XCTAssertThrowsError(try PortionEngine.scale(food: ham, portion: PortionRequest(.volume(100, .milliliter)))) { error in
            XCTAssertEqual(error as? PortionError, .volumeToMassNeedsDensity)
        }
    }

    // Mass ounce and fluid ounce are different units (FOOD-005).
    func testMassVsFluidOunceDistinct() {
        XCTAssertNotEqual(UnitOfMeasure.ounceMass.dimension, UnitOfMeasure.fluidOunceUS.dimension)
        XCTAssertThrowsError(try UnitConverter.convert(1, from: .fluidOunceUS, to: .gram))
    }

    // REG-021 semantics: "two 100 g kotlets" = 200 g finished dish.
    func testCountWithUnitMass() throws {
        let kotletDish = FoodVersion(
            foodID: "fixture-kotlet", versionID: "1", canonicalName: "Kotlet, comparable dish (synthetic)",
            basis: .per100g,
            nutrients: [.energyKcal: .known(220)],
            evidence: SourceEvidence(sourceID: "syn", evidenceType: .estimate)
        )
        let scaled = try PortionEngine.scale(food: kotletDish, portion: PortionRequest(.countWithUnitMass(count: 2, perItemMassG: 100)))
        XCTAssertEqual(NSDecimalNumber(decimal: scaled.resolvedMassG!).doubleValue, 200, accuracy: 1e-9)
        XCTAssertEqual(doubleValue(scaled.value(.energyKcal))!, 440, accuracy: 1e-9)
    }

    // Meal tray fixture [U03]: 500 kcal / 43 g protein / 7 g fiber per 340 g tray;
    // half the tray under the explicit equal-half assumption.
    func testMealTrayHalf() throws {
        let tray = FoodVersion(
            foodID: "fixture-tray", versionID: "1", canonicalName: "Meal tray (label fixture)",
            basis: .namedServing(name: "1 tray", massG: 340, volumeML: nil),
            nutrients: [.energyKcal: .known(500), .proteinG: .known(43), .fiberG: .known(7)],
            evidence: SourceEvidence(sourceID: "U03", evidenceType: .userEnteredLabel)
        )
        let scaled = try PortionEngine.scale(food: tray, portion: PortionRequest(.servings(Decimal(string: "0.5")!)))
        XCTAssertEqual(doubleValue(scaled.value(.energyKcal))!, 250, accuracy: 1e-9)
        XCTAssertEqual(doubleValue(scaled.value(.proteinG))!, 21.5, accuracy: 1e-9)
        XCTAssertEqual(doubleValue(scaled.value(.fiberG))!, 3.5, accuracy: 1e-9)
    }
}
