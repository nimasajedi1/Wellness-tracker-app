import XCTest
@testable import WellnessCore

final class RecipeAndLedgerTests: XCTestCase {

    let day = LogDay(year: 2026, month: 9, day: 13)
    let now = Date(timeIntervalSince1970: 1_789_300_000)

    /// Synthetic 1,200 kcal batch built from one ingredient.
    var syntheticBatch: RecipeVersion {
        let ingredient = FoodVersion(
            foodID: "syn-base", versionID: "1", canonicalName: "Synthetic base",
            basis: .per100g,
            nutrients: [.energyKcal: .known(100)],
            evidence: SourceEvidence(sourceID: "syn", evidenceType: .syntheticFixture)
        )
        return RecipeVersion(
            recipeID: "syn-recipe", versionID: "1", name: "Synthetic batch",
            ingredients: [.init(food: ingredient, portion: PortionRequest(.mass(1200, .gram)))],
            finishedBatchMassG: 1000,
            equalPortionCount: 12
        )
    }

    // REG-030 + FOOD-017 acceptance: 200 g from a 1,000 g finished batch of a
    // 1,200 kcal recipe -> 240 kcal; 3 of 12 equal portions -> 300 kcal.
    func testRecipePortionMath() throws {
        let weighed = try RecipeEngine.weighedPortionNutrients(recipe: syntheticBatch, portionMassG: 200, nutrientIDs: [.energyKcal])
        XCTAssertEqual(NSDecimalNumber(decimal: weighed[.energyKcal]!.total).doubleValue, 240, accuracy: 1e-9)

        let counted = try RecipeEngine.countPortionNutrients(recipe: syntheticBatch, portionsEaten: 3, nutrientIDs: [.energyKcal])
        XCTAssertEqual(NSDecimalNumber(decimal: counted[.energyKcal]!.total).doubleValue, 300, accuracy: 1e-9)
    }

    // FOOD-016: changing cooked yield changes per-gram density, not batch calories.
    func testYieldChangesDensityNotBatchCalories() throws {
        var recipe = syntheticBatch
        recipe.finishedBatchMassG = 800
        let batch = try RecipeEngine.batchNutrients(recipe: recipe, nutrientIDs: [.energyKcal])
        XCTAssertEqual(NSDecimalNumber(decimal: batch[.energyKcal]!.total).doubleValue, 1200, accuracy: 1e-9)
        let portion = try RecipeEngine.weighedPortionNutrients(recipe: recipe, portionMassG: 200, nutrientIDs: [.energyKcal])
        XCTAssertEqual(NSDecimalNumber(decimal: portion[.energyKcal]!.total).doubleValue, 300, accuracy: 1e-9)
    }

    func snapshot(kcal: Double, protein: Double? = nil) -> MealItemSnapshot {
        var nutrients: [NutrientID: NutrientValue] = [.energyKcal: .known(Decimal(kcal))]
        if let protein { nutrients[.proteinG] = .known(Decimal(protein)) }
        return MealItemSnapshot(
            foodID: "f", foodVersionID: "1", displayName: "Test food",
            portionDescription: "1 serving", nutrients: nutrients, evidenceType: .userEnteredLabel
        )
    }

    // REG-031: double-confirming the same preview creates one entry.
    func testIdempotentCommit() throws {
        var ledger = MealLedger()
        let mutation = UUID()
        try ledger.commitMeal(logDay: day, items: [snapshot(kcal: 300)], mutationID: mutation, at: now)
        try ledger.commitMeal(logDay: day, items: [snapshot(kcal: 300)], mutationID: mutation, at: now)
        XCTAssertEqual(ledger.entriesForDay(day).count, 1)
    }

    // REG-032: "another one" with a new mutation ID is a distinct entry.
    func testNewMutationIDCreatesSecondEntry() throws {
        var ledger = MealLedger()
        try ledger.commitMeal(logDay: day, items: [snapshot(kcal: 300)], mutationID: UUID(), at: now)
        try ledger.commitMeal(logDay: day, items: [snapshot(kcal: 300)], mutationID: UUID(), at: now)
        XCTAssertEqual(ledger.entriesForDay(day).count, 2)
    }

    // REG-024 / CHAT-003: revision replaces items atomically — one dinner, not two.
    func testAtomicRevision() throws {
        var ledger = MealLedger()
        let entry = try ledger.commitMeal(
            logDay: day,
            items: [snapshot(kcal: 200), snapshot(kcal: 150)], // lentils + beans
            mutationID: UUID(), at: now
        )
        try ledger.reviseMeal(
            entryID: entry.id, expectedRevision: 1,
            newItems: [snapshot(kcal: 120)], // just 100 g beans
            mutationID: UUID(), note: "No lentils, 100 g beans", at: now
        )
        let totals = ledger.dayNutrientTotals(logDay: day, nutrientIDs: [.energyKcal])
        XCTAssertEqual(NSDecimalNumber(decimal: totals[.energyKcal]!.total).doubleValue, 120, accuracy: 1e-9)
        XCTAssertEqual(ledger.entriesForDay(day).count, 1)
    }

    // CHAT-017: stale expected revision is rejected, not overwritten.
    func testOptimisticConcurrency() throws {
        var ledger = MealLedger()
        let entry = try ledger.commitMeal(logDay: day, items: [snapshot(kcal: 200)], mutationID: UUID(), at: now)
        try ledger.reviseMeal(entryID: entry.id, expectedRevision: 1, newItems: [snapshot(kcal: 250)], mutationID: UUID(), at: now)
        XCTAssertThrowsError(
            try ledger.reviseMeal(entryID: entry.id, expectedRevision: 1, newItems: [snapshot(kcal: 100)], mutationID: UUID(), at: now)
        ) { error in
            guard case LedgerError.revisionConflict(let expected, let actual) = error else {
                return XCTFail("wrong error \(error)")
            }
            XCTAssertEqual(expected, 1)
            XCTAssertEqual(actual, 2)
        }
    }

    // REG-034 / UI-012: undo restores the prior revision once, no duplicate food.
    func testUndoRestoresPreviousRevision() throws {
        var ledger = MealLedger()
        let entry = try ledger.commitMeal(logDay: day, items: [snapshot(kcal: 200)], mutationID: UUID(), at: now)
        try ledger.reviseMeal(entryID: entry.id, expectedRevision: 1, newItems: [snapshot(kcal: 500)], mutationID: UUID(), at: now)
        try ledger.undoLastRevision(entryID: entry.id, mutationID: UUID(), at: now)
        let totals = ledger.dayNutrientTotals(logDay: day, nutrientIDs: [.energyKcal])
        XCTAssertEqual(NSDecimalNumber(decimal: totals[.energyKcal]!.total).doubleValue, 200, accuracy: 1e-9)
        XCTAssertEqual(ledger.entriesForDay(day).count, 1)
    }

    // REG-033 / FOOD-020: protein 100 -> set 120 creates +20 adjustment; adding
    // a 30 g food makes 150; removing it returns to 120; adjustment visible.
    func testAbsoluteTotalEdit() throws {
        var ledger = MealLedger()
        try ledger.commitMeal(logDay: day, items: [snapshot(kcal: 400, protein: 100)], mutationID: UUID(), at: now)

        let current = ledger.dayNutrientTotals(logDay: day, nutrientIDs: [.proteinG])[.proteinG]!.total
        XCTAssertEqual(NSDecimalNumber(decimal: current).doubleValue, 100, accuracy: 1e-9)

        let adjustment = ledger.applyAbsoluteTotalEdit(
            logDay: day, nutrientID: .proteinG,
            targetTotal: 120, currentDerivedTotal: current,
            mutationID: UUID(), at: now
        )
        XCTAssertEqual(NSDecimalNumber(decimal: adjustment!.deltaValue).doubleValue, 20, accuracy: 1e-9)

        let foodEntry = try ledger.commitMeal(logDay: day, items: [snapshot(kcal: 150, protein: 30)], mutationID: UUID(), at: now)
        var totals = ledger.dayNutrientTotals(logDay: day, nutrientIDs: [.proteinG])
        XCTAssertEqual(NSDecimalNumber(decimal: totals[.proteinG]!.total).doubleValue, 150, accuracy: 1e-9)

        try ledger.removeMeal(entryID: foodEntry.id, mutationID: UUID(), at: now)
        totals = ledger.dayNutrientTotals(logDay: day, nutrientIDs: [.proteinG])
        XCTAssertEqual(NSDecimalNumber(decimal: totals[.proteinG]!.total).doubleValue, 120, accuracy: 1e-9)

        XCTAssertTrue(ledger.receipts.contains { $0.commandType == .manualAdjustment })
    }

    // REG-054: resetting one day affects only that day and is receipted.
    func testDayResetScopedToOneDay() throws {
        var ledger = MealLedger()
        let otherDay = LogDay(year: 2026, month: 9, day: 12)
        try ledger.commitMeal(logDay: day, items: [snapshot(kcal: 300)], mutationID: UUID(), at: now)
        try ledger.commitMeal(logDay: otherDay, items: [snapshot(kcal: 400)], mutationID: UUID(), at: now)

        ledger.resetDay(day, mutationID: UUID(), at: now)

        let todayTotals = ledger.dayNutrientTotals(logDay: day, nutrientIDs: [.energyKcal])
        XCTAssertFalse(todayTotals[.energyKcal]!.hasData)
        let otherTotals = ledger.dayNutrientTotals(logDay: otherDay, nutrientIDs: [.energyKcal])
        XCTAssertEqual(NSDecimalNumber(decimal: otherTotals[.energyKcal]!.total).doubleValue, 400, accuracy: 1e-9)
        XCTAssertTrue(ledger.receipts.contains { $0.commandType == .dayReset })
    }
}
