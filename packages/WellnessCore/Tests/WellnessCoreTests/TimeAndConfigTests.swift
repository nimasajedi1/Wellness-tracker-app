import XCTest
@testable import WellnessCore

final class TimeAndConfigTests: XCTestCase {

    // REG-015: 23:30 -> next day 07:30 is eight hours.
    func testOvernightInterval() {
        let zone = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 12, hour: 23, minute: 30))!
        let end = cal.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 7, minute: 30))!
        let interval = DatedInterval(start: start, end: end, timeZoneIdentifier: zone.identifier)
        XCTAssertEqual(interval.elapsedMinutes!, 480, accuracy: 1e-9)
    }

    // REG-016: New York 2026-03-08, 01:30 -> 03:30 across the DST jump is one
    // elapsed hour, not two.
    func testDSTSpringForward() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let start = cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 30))!
        let end = cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 30))!
        let interval = DatedInterval(start: start, end: end, timeZoneIdentifier: zone.identifier)
        XCTAssertEqual(interval.elapsedMinutes!, 60, accuracy: 1e-9)
    }

    // STORE-008: an end before the start is invalid, never wrapped modulo 24 h.
    func testNegativeIntervalIsInvalid() {
        let start = Date(timeIntervalSince1970: 10_000)
        let end = Date(timeIntervalSince1970: 5_000)
        let interval = DatedInterval(start: start, end: end, timeZoneIdentifier: "UTC")
        XCTAssertNil(interval.elapsedMinutes)
    }

    // STORE-007: a missing endpoint means incomplete, not zero hours.
    func testOpenIntervalIsIncomplete() {
        let interval = DatedInterval(start: Date(), end: nil, timeZoneIdentifier: "UTC")
        XCTAssertNil(interval.elapsedMinutes)
        XCTAssertFalse(interval.isComplete)
    }

    // REG-017: log day is stored, not derived from the current time zone.
    func testLogDayStableAcrossTravel() {
        let day = LogDay(year: 2026, month: 9, day: 12)
        let observation = Observation(
            metricID: OwnerMetrics.water,
            value: .quantity(500, .milliliter),
            observedAt: Date(),
            timeZoneIdentifier: "America/New_York",
            logDay: day
        )
        // Whatever zone the device moves to later, the stored log day is fixed.
        XCTAssertEqual(observation.logDay, day)
    }

    // Sleep aggregation unions overlapping intervals rather than summing them.
    func testDurationUnionAvoidsDoubleCount() {
        let metric = OwnerTemplate.metrics().first { $0.id == OwnerMetrics.sleep }!
        let base = Date(timeIntervalSince1970: 1_789_000_000)
        let day = LogDay(year: 2026, month: 9, day: 13)
        func obs(startOffset: TimeInterval, endOffset: TimeInterval) -> Observation {
            Observation(
                metricID: OwnerMetrics.sleep,
                value: .interval(DatedInterval(start: base.addingTimeInterval(startOffset), end: base.addingTimeInterval(endOffset), timeZoneIdentifier: "UTC")),
                observedAt: base,
                timeZoneIdentifier: "UTC",
                logDay: day
            )
        }
        // 0-60 min and 30-90 min overlap: union is 90 minutes, not 120.
        let result = MetricAggregator.aggregate(metric: metric, observations: [obs(startOffset: 0, endOffset: 3600), obs(startOffset: 1800, endOffset: 5400)])
        XCTAssertEqual(result.numericValue!, 90, accuracy: 1e-9)
    }

    // REG-039 / BUILD-009: cyclic derived-field dependencies are rejected atomically.
    func testCyclicDependenciesRejected() {
        var config = OwnerTemplate.configuration(effectiveFrom: LogDay(year: 2026, month: 9, day: 13))
        config.metrics.append(MetricDefinition(
            id: "derived.a", name: "A", category: "custom", valueType: .quantity,
            dependencies: ["derived.b"], derived: .sum
        ))
        config.metrics.append(MetricDefinition(
            id: "derived.b", name: "B", category: "custom", valueType: .quantity,
            dependencies: ["derived.a"], derived: .sum
        ))
        let errors = ConfigurationValidator.validate(config)
        XCTAssertTrue(errors.contains { if case .dependencyCycle = $0 { return true }; return false })
    }

    func testOwnerTemplateValidates() {
        let config = OwnerTemplate.configuration(effectiveFrom: LogDay(year: 2026, month: 9, day: 13))
        XCTAssertEqual(ConfigurationValidator.validate(config), [])
        // UI-005: calorie balance card is full width.
        let balance = config.layout.first { $0.cardID == "card.calorieBalance" }!
        XCTAssertEqual(balance.width, .full)
        XCTAssertEqual(balance.order, config.layout.map(\.order).max())
    }

    // BUILD-012: export/import round-trips and re-validates.
    func testConfigurationRoundTrip() throws {
        let config = OwnerTemplate.configuration(effectiveFrom: LogDay(year: 2026, month: 9, day: 13))
        let data = try ConfigurationPorting.export(config)
        let restored = try ConfigurationPorting.importConfiguration(from: data)
        XCTAssertEqual(restored, config)
    }

    // SEC-002: invalid references fail import atomically.
    func testImportRejectsUnknownReferences() throws {
        var config = OwnerTemplate.configuration(effectiveFrom: LogDay(year: 2026, month: 9, day: 13))
        config.layout.append(LayoutCard(cardID: "card.bogus", metricIDs: ["metric.doesNotExist"], order: 99))
        let data = try ConfigurationPorting.export(config)
        XCTAssertThrowsError(try ConfigurationPorting.importConfiguration(from: data))
    }

    // REG-048 / STORE-015: reimporting the same legacy payload is refused.
    func testLegacyImportDeduplication() throws {
        let payload = """
        {"date":"2026-09-07","protein":120,"water":2.0,"steps":8000,"morningPills":true,"eveningPills":false}
        """.data(using: .utf8)!
        let preview = try LegacyImporter.preview(payloadData: payload, existingFingerprints: [])
        XCTAssertEqual(preview.logDay, LogDay(year: 2026, month: 9, day: 7))

        XCTAssertThrowsError(
            try LegacyImporter.preview(payloadData: payload, existingFingerprints: [preview.fingerprint])
        ) { error in
            guard case LegacyImportError.alreadyImported = error else { return XCTFail("wrong error") }
        }

        // Legacy water liters convert to canonical milliliters.
        let water = preview.fields.first { $0.metricID == OwnerMetrics.water }!
        guard case .quantity(let amount, let unit) = water.proposedValue else { return XCTFail() }
        XCTAssertEqual(amount, 2000, accuracy: 1e-9)
        XCTAssertEqual(unit, .milliliter)
    }

    // STORE-014: untouched-looking legacy zeros default to excluded.
    func testLegacyZeroDefaultsToMissing() throws {
        let payload = """
        {"date":"2026-09-07","protein":0,"fiber":0}
        """.data(using: .utf8)!
        let preview = try LegacyImporter.preview(payloadData: payload, existingFingerprints: [])
        for field in preview.fields {
            XCTAssertTrue(field.looksLikeUntouchedDefault)
            XCTAssertFalse(field.include)
        }
    }
}

final class MockInterpreterTests: XCTestCase {

    let context = InterpretationContext(selectedLogDay: LogDay(year: 2026, month: 9, day: 13))

    // REG-018 / CHAT-001: questions are hypothetical, never logs.
    func testQuestionIsHypothetical() async throws {
        let interpreter = MockInterpreter()
        let turn = try await interpreter.interpret("What about a poke bowl?", context: context)
        XCTAssertEqual(turn.intent, .hypothetical)
    }

    func testClearConsumptionIsLogFood() async throws {
        let interpreter = MockInterpreter()
        let turn = try await interpreter.interpret("I had 112 g of my ham", context: context)
        XCTAssertEqual(turn.intent, .logFood)
        XCTAssertEqual(turn.items.count, 1)
        XCTAssertEqual(turn.items[0].quantity, 112)
        XCTAssertEqual(turn.items[0].unit, "g")
        XCTAssertEqual(turn.items[0].reference, .savedAlias)
    }

    // REG-023 / CHAT-005: ambiguous 29 g tuna requires a clarification.
    func testAmbiguousQuantityAsksClarification() async throws {
        let interpreter = MockInterpreter()
        let turn = try await interpreter.interpret("It is 29 grams, same tuna as last time", context: context)
        XCTAssertEqual(turn.intent, .clarify)
        XCTAssertFalse(turn.unresolvedQuestions.isEmpty)
    }

    // REG-020 / CHAT-004: a discarded food is a removal, not a log.
    func testDiscardedFood() async throws {
        let interpreter = MockInterpreter()
        let turn = try await interpreter.interpret("I threw out the oatmeal", context: context)
        XCTAssertEqual(turn.intent, .removeEntry)
    }

    // REG-042 / ARCH-004: an unavailable model throws; no record is created.
    func testUnavailableModelThrows() async {
        let interpreter = MockInterpreter(forcedAvailability: .modelNotReady)
        do {
            _ = try await interpreter.interpret("I had 100 g beans", context: context)
            XCTFail("expected unavailable error")
        } catch let error as InterpreterError {
            guard case .unavailable(.modelNotReady) = error else { return XCTFail("wrong error") }
        } catch {
            XCTFail("wrong error type")
        }
    }
}
