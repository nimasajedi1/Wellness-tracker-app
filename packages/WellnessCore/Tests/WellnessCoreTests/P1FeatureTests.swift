import XCTest
@testable import WellnessCore

final class ExpenditureMethodTests: XCTestCase {

    // ENERGY-004: fixed daily total — active shown but not added by default.
    func testFixedTotalDoesNotAddActiveByDefault() {
        let estimate = EnergyEngine.estimatedOut(
            method: .fixedDailyTotal(kcal: 2400, activeIsAdditional: false),
            inputs: ExpenditureInputs(loggedActiveKcal: 500)
        )
        XCTAssertEqual(estimate.outKcal!, 2400, accuracy: 1e-9)
        XCTAssertNil(estimate.countedActiveKcal)

        let additive = EnergyEngine.estimatedOut(
            method: .fixedDailyTotal(kcal: 2400, activeIsAdditional: true),
            inputs: ExpenditureInputs(loggedActiveKcal: 500)
        )
        XCTAssertEqual(additive.outKcal!, 2900, accuracy: 1e-9)
    }

    // ENERGY-003: the formula estimate is never added to HealthKit resting
    // energy, and a missing resting total yields no out figure.
    func testHealthKitMethodUsesSamplesOnly() {
        let estimate = EnergyEngine.estimatedOut(
            method: .healthKitDaily,
            inputs: ExpenditureInputs(
                loggedActiveKcal: 999,   // manual figure must be ignored here
                healthKitRestingKcal: 1700,
                healthKitActiveKcal: 450,
                healthKitCoversFullDay: true
            )
        )
        XCTAssertEqual(estimate.outKcal!, 2150, accuracy: 1e-9)
        XCTAssertTrue(estimate.inputsComplete)

        let missingResting = EnergyEngine.estimatedOut(
            method: .healthKitDaily,
            inputs: ExpenditureInputs(healthKitActiveKcal: 450)
        )
        XCTAssertNil(missingResting.outKcal)
        XCTAssertFalse(missingResting.inputsComplete)
    }

    // ENERGY-003: partial-day HealthKit data is never a completed day.
    func testPartialHealthKitDayStaysProvisional() {
        let result = EnergyEngine.evaluateDay(
            intakeKcal: 1200,
            intakeCoverageComplete: true,
            method: .healthKitDaily,
            inputs: ExpenditureInputs(
                healthKitRestingKcal: 900,
                healthKitActiveKcal: 200,
                healthKitCoversFullDay: false
            ),
            dayMarkedComplete: true,
            mode: .weightLoss
        )
        XCTAssertTrue(result.isProvisional)
        XCTAssertEqual(result.status, .partial)
    }

    // The generalized evaluation matches the legacy method's numbers.
    func testGeneralizedLegacyMethodMatches() {
        let result = EnergyEngine.evaluateDay(
            intakeKcal: 1850,
            intakeCoverageComplete: true,
            method: .restingPlusActive(.formula(EnergyProfile(weightKg: 93, heightCm: 178, ageYears: 33, equationConstant: .maleEquation))),
            inputs: ExpenditureInputs(loggedActiveKcal: 500),
            dayMarkedComplete: true,
            mode: .weightLoss
        )
        XCTAssertEqual(result.estimatedOutKcal!, 2382.5, accuracy: 1e-9)
        XCTAssertEqual(result.status, .met)
        XCTAssertFalse(result.isProvisional)
    }
}

final class HealthImportTests: XCTestCase {

    let day = LogDay(year: 2026, month: 9, day: 14)
    let zone = TimeZone(identifier: "UTC")!
    let importedAt = Date(timeIntervalSince1970: 1_789_400_000)

    // HEALTH-003: reimporting the same day's total replaces, not adds — the
    // external sample ID is stable per metric/day.
    func testDailyImportIsIdempotentByStableID() {
        let first = HealthImportMapper.observation(
            from: ImportedDailyQuantity(metricID: OwnerMetrics.steps, day: day, value: 8000, unit: .step, coversFullDay: false),
            timeZone: zone, importedAt: importedAt
        )
        let second = HealthImportMapper.observation(
            from: ImportedDailyQuantity(metricID: OwnerMetrics.steps, day: day, value: 9500, unit: .step, coversFullDay: true),
            timeZone: zone, importedAt: importedAt.addingTimeInterval(3600)
        )
        XCTAssertEqual(first.externalSampleID, second.externalSampleID)
        XCTAssertEqual(first.source, .healthKit)
    }

    // Source policy is exclusive: manual excludes imported and vice versa.
    func testSourcePolicyExclusivity() {
        XCTAssertTrue(MetricSourcePolicy.manual.admits(.manual))
        XCTAssertFalse(MetricSourcePolicy.manual.admits(.healthKit))
        XCTAssertTrue(MetricSourcePolicy.healthKit.admits(.healthKit))
        XCTAssertFalse(MetricSourcePolicy.healthKit.admits(.manual))
        // Ledger-derived and adjustment records ride the manual policy.
        XCTAssertTrue(MetricSourcePolicy.manual.admits(.manualAdjustment))
    }

    // HEALTH-005: overlapping imported sleep intervals union via aggregation,
    // never summing in-bed plus stage plus manual as independent sleep.
    func testImportedSleepOverlapUnions() {
        let base = importedAt
        let observations = HealthImportMapper.sleepObservations(
            metricID: OwnerMetrics.sleep,
            intervals: [
                ImportedSleepInterval(sampleID: "a", start: base, end: base.addingTimeInterval(3600)),
                ImportedSleepInterval(sampleID: "b", start: base.addingTimeInterval(1800), end: base.addingTimeInterval(5400))
            ],
            day: day, timeZone: zone, importedAt: importedAt
        )
        let metric = OwnerTemplate.metrics().first { $0.id == OwnerMetrics.sleep }!
        let aggregate = MetricAggregator.aggregate(metric: metric, observations: observations)
        XCTAssertEqual(aggregate.numericValue!, 90, accuracy: 1e-9)
    }

    func testInvalidSleepIntervalDropped() {
        let observations = HealthImportMapper.sleepObservations(
            metricID: OwnerMetrics.sleep,
            intervals: [ImportedSleepInterval(sampleID: "x", start: importedAt, end: importedAt.addingTimeInterval(-10))],
            day: day, timeZone: zone, importedAt: importedAt
        )
        XCTAssertTrue(observations.isEmpty)
    }
}

final class ReminderRuleTests: XCTestCase {

    let zone = TimeZone(identifier: "UTC")!

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testNextFireSkipsToConfiguredWeekday() {
        // 2026-09-14 is a Monday (weekday 2). Rule fires Wednesdays (4) at 09:00.
        let rule = ReminderRule(title: "Stretch", hour: 9, minute: 0, weekdays: [4])
        let next = rule.nextFireDate(after: date(2026, 9, 14, 12, 0), timeZone: zone)
        XCTAssertEqual(next, date(2026, 9, 16, 9, 0))
    }

    func testSameDayLaterTimeFiresToday() {
        let rule = ReminderRule(title: "Water", hour: 15, minute: 30)
        let next = rule.nextFireDate(after: date(2026, 9, 14, 12, 0), timeZone: zone)
        XCTAssertEqual(next, date(2026, 9, 14, 15, 30))
    }

    // DEVICE-004: quiet hours shift delivery to the window's end.
    func testQuietHoursShiftAcrossMidnightWindow() {
        let quiet = QuietHours(startMinute: 22 * 60, endMinute: 7 * 60)
        XCTAssertTrue(quiet.contains(minuteOfDay: 23 * 60))
        XCTAssertTrue(quiet.contains(minuteOfDay: 6 * 60))
        XCTAssertFalse(quiet.contains(minuteOfDay: 12 * 60))

        let rule = ReminderRule(title: "Supplements", hour: 23, minute: 0)
        XCTAssertEqual(rule.effectiveMinuteOfDay(quietHours: quiet), 7 * 60)
        let next = rule.nextFireDate(after: date(2026, 9, 14, 8, 0), timeZone: zone, quietHours: quiet)
        // 23:00 shifts to 07:00; 07:00 already passed today, so tomorrow 07:00.
        XCTAssertEqual(next, date(2026, 9, 15, 7, 0))
    }

    func testDisabledRuleNeverFires() {
        let rule = ReminderRule(title: "Off", hour: 9, minute: 0, isEnabled: false)
        XCTAssertNil(rule.nextFireDate(after: date(2026, 9, 14, 8, 0), timeZone: zone))
    }
}

final class LabelTranscriptionTests: XCTestCase {

    // Ham label fixture [U01] as OCR-ish lines.
    func testParsesHamLabelLines() {
        let candidate = LabelTranscriptionParser.parse(lines: [
            "Nutrition Facts",
            "Serving size 56 g",
            "Calories 60",
            "Total Fat 1g",
            "Protein 9 g",
            "Sodium 480 mg"
        ])
        XCTAssertEqual(candidate.servingMassG?.value, 56)
        XCTAssertEqual(candidate.energyKcal?.value, 60)
        XCTAssertEqual(candidate.proteinG?.value, 9)
        XCTAssertEqual(candidate.fatG?.value, 1)
        XCTAssertEqual(candidate.sodiumMg?.value, 480)
        // Absent fields stay absent — never zero (FOOD-002).
        XCTAssertNil(candidate.fiberG)
    }

    func testNumberBeforeKeywordForm() {
        let candidate = LabelTranscriptionParser.parse(lines: ["9 g protein", "60 calories"])
        XCTAssertEqual(candidate.proteinG?.value, 9)
        XCTAssertEqual(candidate.energyKcal?.value, 60)
    }

    func testFoodVersionRequiresReviewedContent() {
        let empty = ParsedLabelCandidate()
        XCTAssertNil(LabelTranscriptionParser.foodVersion(name: "Thing", confirmed: empty, market: "US", createdAt: Date()))

        var confirmed = ParsedLabelCandidate()
        confirmed.servingMassG = ParsedLabelField(value: 56, sourceText: "Serving size 56 g")
        confirmed.energyKcal = ParsedLabelField(value: 60, sourceText: "Calories 60")
        let food = LabelTranscriptionParser.foodVersion(name: "My ham", confirmed: confirmed, market: "US", createdAt: Date())
        XCTAssertNotNil(food)
        XCTAssertEqual(food?.evidence.evidenceType, .userEnteredLabel)
        XCTAssertEqual(food?.basis.referenceMassG, 56)
        // A reported zero is stored as known zero, not unknown.
        var zeroFiber = confirmed
        zeroFiber.fiberG = ParsedLabelField(value: 0, sourceText: "Dietary Fiber 0g")
        let zeroFood = LabelTranscriptionParser.foodVersion(name: "My ham", confirmed: zeroFiber, market: "US", createdAt: Date())
        XCTAssertEqual(zeroFood?.nutrients[.fiberG], .knownZero)
    }
}

final class BarcodeTests: XCTestCase {

    func testValidGTIN13Accepted() {
        // 4006381333931 is a standard valid EAN-13 example.
        XCTAssertEqual(Barcode.validatedGTIN("4006381333931"), "4006381333931")
        XCTAssertEqual(Barcode.validatedGTIN("40063813339 31"), "4006381333931")
    }

    func testInvalidChecksumRejected() {
        XCTAssertNil(Barcode.validatedGTIN("4006381333932"))
        XCTAssertNil(Barcode.validatedGTIN("12345"))
        XCTAssertNil(Barcode.validatedGTIN(""))
    }

    func testValidUPCAAccepted() {
        // 036000291452 is the canonical valid UPC-A example.
        XCTAssertEqual(Barcode.validatedGTIN("036000291452"), "036000291452")
    }

    func testBarcodeLookupMatchesStoredIdentifier() async throws {
        let food = FoodVersion(
            foodID: "barcode-food", versionID: "1", canonicalName: "Barcode test food",
            identifiers: ["gtin": "0036000291452"],
            basis: .per100g,
            nutrients: [.energyKcal: .known(100)],
            evidence: SourceEvidence(sourceID: "test", evidenceType: .brandedLabelRecord)
        )
        let repo = InMemoryFoodCatalogRepository(foods: [food])
        let hits = try await repo.foodByBarcode("036000291452", market: "US")
        XCTAssertEqual(hits.count, 1)
        // DEVICE-001: an unknown code returns nothing rather than a guess.
        let misses = try await repo.foodByBarcode("4006381333931", market: "US")
        XCTAssertTrue(misses.isEmpty)
    }
}

final class TemplateTests: XCTestCase {

    let day = LogDay(year: 2026, month: 9, day: 14)

    // BUILD-013: templates are views over the same canonical metric IDs.
    func testAllTemplatesValidateAndShareMetricIDs() {
        let templates = [
            OwnerTemplate.configuration(effectiveFrom: day),
            OwnerTemplate.minimalDay(effectiveFrom: day),
            OwnerTemplate.busyWorkday(effectiveFrom: day),
            OwnerTemplate.travelDay(effectiveFrom: day)
        ]
        let ownerIDs = Set(OwnerTemplate.metrics().map(\.id))
        for template in templates {
            XCTAssertEqual(ConfigurationValidator.validate(template), [], template.templateID)
            XCTAssertTrue(Set(template.metrics.map(\.id)).isSubset(of: ownerIDs), template.templateID)
        }
    }

    func testTravelDayHidesBalanceInsteadOfJudging() {
        let travel = OwnerTemplate.travelDay(effectiveFrom: day)
        let balance = travel.layout.first { $0.cardID == "card.calorieBalance" }!
        XCTAssertTrue(balance.isHidden)
    }
}
