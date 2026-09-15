import XCTest
@testable import WellnessCore

/// DEVICE-007 acceptance scenarios that are pure-domain. Extraction accuracy
/// against real images and the on-device model runs are recorded separately
/// (device evaluation); these tests prove commit correctness: accepted values
/// must survive deterministic validation regardless of what produced them.
final class StructuredLabelTests: XCTestCase {

    let createdAt = Date(timeIntervalSince1970: 1_789_500_000)

    /// Clean single-column US label (ham fixture values [U01] extended).
    func cleanDraft() -> StructuredLabelDraft {
        StructuredLabelDraft(
            productName: "Sliced ham",
            servingsPerContainer: 8,
            servingDescription: "2 slices (56g)",
            servingMassG: 56,
            columns: [
                LabelColumn(basis: .perServing, nutrients: [
                    .calories: ExtractedLabelValue(amount: 60, sourceText: "Calories 60", confidence: .high),
                    .totalFat: ExtractedLabelValue(amount: 1, dailyValuePercent: 2, sourceText: "Total Fat 1g 2%", confidence: .high),
                    .sodium: ExtractedLabelValue(amount: 480, dailyValuePercent: 21, sourceText: "Sodium 480mg 21%", confidence: .high),
                    .protein: ExtractedLabelValue(amount: 9, sourceText: "Protein 9g", confidence: .high)
                ])
            ],
            extractionSource: .visionDocument
        )
    }

    // Clean single-column label: validates and commits with a snapshot basis.
    func testCleanLabelValidatesAndCommits() throws {
        let draft = cleanDraft()
        let validated = try LabelDraftValidator.validate(draft: draft, basis: .perServing)
        XCTAssertFalse(validated.hasBlockingIssues)
        XCTAssertEqual(validated.accepted[.calories], 60)
        XCTAssertEqual(validated.accepted[.sodium], 480)

        let food = try LabelDraftValidator.foodVersion(
            from: validated, draft: draft, name: "Sliced ham", market: "US",
            existingFoodID: nil, newVersionID: "1", createdAt: createdAt
        )
        XCTAssertEqual(food.evidence.evidenceType, .userEnteredLabel)
        XCTAssertEqual(food.basis.referenceMassG, 56)
        XCTAssertEqual(food.nutrients[.energyKcal], .known(60))
        // Fiber was never on the label: it is absent/unknown, not zero.
        XCTAssertNil(food.nutrients[.fiberG]?.decimalValue)
    }

    // Per-serving and per-container columns stay distinct until selection.
    func testColumnsStayDistinctUntilSelected() throws {
        var draft = cleanDraft()
        draft.columns.append(LabelColumn(basis: .perContainer, nutrients: [
            .calories: ExtractedLabelValue(amount: 480, sourceText: "Per container: Calories 480"),
            .protein: ExtractedLabelValue(amount: 72, sourceText: "Per container: Protein 72g")
        ]))

        let perServing = try LabelDraftValidator.validate(draft: draft, basis: .perServing)
        let perContainer = try LabelDraftValidator.validate(draft: draft, basis: .perContainer)
        XCTAssertEqual(perServing.accepted[.calories], 60)
        XCTAssertEqual(perContainer.accepted[.calories], 480)
        // No blended column exists; selecting a missing basis fails loudly.
        XCTAssertThrowsError(try LabelDraftValidator.validate(draft: draft, basis: .prepared)) { error in
            XCTAssertEqual(error as? LabelDraftError, .columnNotFound)
        }
    }

    // %DV is never substituted for grams/milligrams.
    func testDailyValueNeverSubstitutesForAbsolute() throws {
        var draft = cleanDraft()
        draft.columns[0].nutrients[.dietaryFiber] = ExtractedLabelValue(
            amount: nil, dailyValuePercent: 14, sourceText: "Dietary Fiber 14%"
        )
        let validated = try LabelDraftValidator.validate(draft: draft, basis: .perServing)
        XCTAssertNil(validated.accepted[.dietaryFiber])
        XCTAssertNotNil(validated.droppedToUnknown[.dietaryFiber])

        let food = try LabelDraftValidator.foodVersion(
            from: validated, draft: draft, name: "Sliced ham", market: "US",
            existingFoodID: nil, newVersionID: "1", createdAt: createdAt
        )
        guard case .unknown = food.nutrients[.fiberG] else {
            return XCTFail("fiber must remain unknown, not derived from %DV")
        }
    }

    // Missing/unsupported nutrients stay unknown; conflicts block until corrected.
    func testMissingAndConflictingFields() throws {
        var draft = cleanDraft()
        draft.columns[0].nutrients[.addedSugars] = ExtractedLabelValue(
            amount: 5, sourceText: "Incl. 5g Added Sugars", conflicting: true
        )
        let validated = try LabelDraftValidator.validate(draft: draft, basis: .perServing)
        XCTAssertNil(validated.accepted[.addedSugars])
        XCTAssertTrue(validated.hasBlockingIssues)
        XCTAssertEqual(validated.droppedToUnknown[.addedSugars], "Conflicting readings")
    }

    // An image that is not a nutrition label is rejected, not committed empty.
    func testNotANutritionLabelRejected() {
        let draft = StructuredLabelDraft(
            productName: "A cat photo",
            columns: [LabelColumn(basis: .perServing)],
            extractionSource: .visionDocument
        )
        XCTAssertThrowsError(try LabelDraftValidator.validate(draft: draft, basis: .perServing)) { error in
            XCTAssertEqual(error as? LabelDraftError, .notANutritionLabel)
        }
    }

    // Impossible readings are dropped as blocking issues (bounds validation).
    func testImplausibleValuesBlocked() throws {
        var draft = cleanDraft()
        draft.columns[0].nutrients[.protein] = ExtractedLabelValue(amount: 8000, sourceText: "Protein 8000g")
        draft.columns[0].nutrients[.transFat] = ExtractedLabelValue(amount: -1, sourceText: "Trans Fat -1g")
        let validated = try LabelDraftValidator.validate(draft: draft, basis: .perServing)
        XCTAssertNil(validated.accepted[.protein])
        XCTAssertNil(validated.accepted[.transFat])
        XCTAssertTrue(validated.hasBlockingIssues)
    }

    // Component arithmetic flags for review but never rewrites printed values.
    func testArithmeticFlagsWithoutRewriting() throws {
        var draft = cleanDraft()
        draft.columns[0].nutrients[.saturatedFat] = ExtractedLabelValue(amount: 12, sourceText: "Sat Fat 12g")
        // total fat is 1 g -> saturated exceeding total is a review flag.
        let validated = try LabelDraftValidator.validate(draft: draft, basis: .perServing)
        XCTAssertEqual(validated.accepted[.saturatedFat], 12)  // kept, not rewritten
        XCTAssertTrue(validated.issues.contains { $0.field == LabelNutrientKey.saturatedFat.rawValue && $0.severity == .review })

        // Calories far from the 4/4/9 estimate: review flag, calories kept.
        var caloriesOff = cleanDraft()
        caloriesOff.columns[0].nutrients[.calories] = ExtractedLabelValue(amount: 900, sourceText: "Calories 900")
        let validatedOff = try LabelDraftValidator.validate(draft: caloriesOff, basis: .perServing)
        XCTAssertEqual(validatedOff.accepted[.calories], 900)
        XCTAssertTrue(validatedOff.issues.contains { $0.field == LabelNutrientKey.calories.rawValue })
    }

    // Correction before commit: a blocked field, corrected in review, commits.
    func testCorrectionBeforeCommit() throws {
        var draft = cleanDraft()
        draft.columns[0].nutrients[.protein] = ExtractedLabelValue(amount: 9000, sourceText: "Protein 9000g (misread)")
        var validated = try LabelDraftValidator.validate(draft: draft, basis: .perServing)
        XCTAssertNil(validated.accepted[.protein])

        // User corrects the field in review; the corrected draft re-validates.
        draft.columns[0].nutrients[.protein] = ExtractedLabelValue(amount: 9, sourceText: "corrected by user", confidence: .high)
        validated = try LabelDraftValidator.validate(draft: draft, basis: .perServing)
        XCTAssertEqual(validated.accepted[.protein], 9)
        XCTAssertFalse(validated.hasBlockingIssues)
    }

    // Updating an existing food creates a NEW version; the old snapshot and
    // any diary entries pointing at it are untouched (FOOD-001, DEVICE-007).
    func testRescanCreatesNewVersionNotOverwrite() throws {
        let draft = cleanDraft()
        let validated = try LabelDraftValidator.validate(draft: draft, basis: .perServing)
        let first = try LabelDraftValidator.foodVersion(
            from: validated, draft: draft, name: "Sliced ham", market: "US",
            existingFoodID: nil, newVersionID: "1", createdAt: createdAt
        )
        let second = try LabelDraftValidator.foodVersion(
            from: validated, draft: draft, name: "Sliced ham", market: "US",
            existingFoodID: first.foodID, newVersionID: "2", createdAt: createdAt.addingTimeInterval(3600)
        )
        XCTAssertEqual(second.foodID, first.foodID)
        XCTAssertNotEqual(second.versionID, first.versionID)
        XCTAssertNotEqual(second.id, first.id)
    }

    // The DEVICE-002 line-parser bridge feeds the same pipeline (fallback path).
    func testLineParserBridge() throws {
        let candidate = LabelTranscriptionParser.parse(lines: [
            "Serving size 56 g", "Calories 60", "Protein 9 g"
        ])
        let draft = StructuredLabelDraft.from(candidate: candidate)
        XCTAssertEqual(draft.extractionSource, .lineParser)
        let validated = try LabelDraftValidator.validate(draft: draft, basis: .perServing)
        XCTAssertEqual(validated.accepted[.calories], 60)
        XCTAssertEqual(validated.accepted[.protein], 9)
    }

    // Deterministic row parsing: absolute + %DV separated, units normalized.
    func testRowParserSeparatesAbsoluteAndDV() {
        let sodium = LabelRowParser.parseNutrientRow("Sodium 480mg 21%")
        XCTAssertEqual(sodium?.key, .sodium)
        XCTAssertEqual(sodium?.value.amount, 480)
        XCTAssertEqual(sodium?.value.dailyValuePercent, 21)

        // %DV-only row: amount stays nil, confidence low.
        let fiber = LabelRowParser.parseNutrientRow("Dietary Fiber 14%")
        XCTAssertEqual(fiber?.key, .dietaryFiber)
        XCTAssertNil(fiber?.value.amount)
        XCTAssertEqual(fiber?.value.dailyValuePercent, 14)
        XCTAssertEqual(fiber?.value.confidence, .low)

        // Saturated fat wins over the shorter "fat" keywords.
        XCTAssertEqual(LabelRowParser.parseNutrientRow("Saturated Fat 2g 10%")?.key, .saturatedFat)
        // Sodium printed in grams normalizes to milligrams.
        XCTAssertEqual(LabelRowParser.parseNutrientRow("Sodium 0.48g")?.value.amount, 480)
    }

    // Bilingual/complex labels: rows the parser cannot understand stay out —
    // nothing is invented for an unmatched line (DEVICE-007 acceptance).
    func testUnsupportedRowsStayOut() {
        XCTAssertNil(LabelRowParser.parseNutrientRow("Grasas totales 10 g"))
        XCTAssertNil(LabelRowParser.parseNutrientRow("Best before 2027-01-01"))
        let draft = LabelRowParser.draft(
            fromRows: ["Grasas totales 10 g", "Protein 9g"],
            freeTextLines: [], barcodes: [], source: .visionDocument
        )
        XCTAssertEqual(draft.columns[0].nutrients.count, 1)
        XCTAssertEqual(draft.columns[0].nutrients[.protein]?.amount, 9)
    }

    // A nutrient read twice with different values is marked conflicting, not
    // silently resolved (partially obscured/blurred label scenario).
    func testDuplicateReadingsBecomeConflicts() {
        let draft = LabelRowParser.draft(
            fromRows: ["Protein 9g", "Protein 19g"],
            freeTextLines: [], barcodes: [], source: .visionDocument
        )
        XCTAssertEqual(draft.columns[0].nutrients[.protein]?.conflicting, true)
        XCTAssertFalse(draft.extractionNotes.isEmpty)
    }

    func testServingRows() {
        let serving = LabelRowParser.parseServingSizeRow("Serving size 2 slices (56g)")
        XCTAssertEqual(serving?.massG, 56)
        XCTAssertEqual(LabelRowParser.parseServingsPerContainer("8 servings per container"), 8)
    }

    // A validated barcode from the document lands as the food's GTIN; an
    // invalid one is discarded rather than "repaired".
    func testBarcodeCarriedOnlyWhenValid() throws {
        var draft = cleanDraft()
        draft.barcodes = ["not-a-code", "036000291452"]
        let validated = try LabelDraftValidator.validate(draft: draft, basis: .perServing)
        let food = try LabelDraftValidator.foodVersion(
            from: validated, draft: draft, name: "Sliced ham", market: "US",
            existingFoodID: nil, newVersionID: "1", createdAt: createdAt
        )
        XCTAssertEqual(food.identifiers["gtin"], "036000291452")
    }
}
