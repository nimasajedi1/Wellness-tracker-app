import Foundation
import SwiftData
import Observation
import WellnessCore

enum SaveState: Equatable {
    case idle
    case saving
    case saved
    case error(String)
}

/// Owner nutrition metrics map to ledger nutrient IDs; their dashboard totals
/// are always committed food snapshots plus auditable adjustments (FOOD-019) —
/// there is never a competing parallel counter.
let nutritionMetricMap: [MetricID: NutrientID] = [
    OwnerMetrics.protein: .proteinG,
    OwnerMetrics.fiber: .fiberG,
    OwnerMetrics.calories: .energyKcal
]

/// Shared application state (UI-002): Today, Chat, History, and Builder read
/// the same records through this model, so a chat mutation updates the
/// dashboard immediately and vice versa.
@MainActor
@Observable
final class AppModel {
    // MARK: State

    private(set) var configuration: TrackerConfiguration?
    var selectedDay: LogDay
    private(set) var dayObservations: [Observation] = []
    private(set) var ledger = MealLedger()
    private(set) var interpreterAvailability: InterpreterAvailability = .unknown("Not checked yet")
    private(set) var saveState: SaveState = .idle
    private(set) var lastError: String?

    /// Energy settings. The owner profile is an opt-in seed requiring explicit
    /// confirmation in Settings (ENERGY-002); resting stays unset until then.
    var restingInput: RestingEnergyInput?
    var balanceMode: BalanceGoalMode = .weightLoss
    /// Days the user explicitly marked complete (ENERGY-007).
    private(set) var completedDays: Set<String> = []

    // MARK: P1 state

    /// Exclusive expenditure method (ENERGY-003/004). nil falls back to
    /// restingPlusActive when a resting input is configured.
    var expenditureMethod: ExpenditureMethod? {
        didSet { persistExpenditureMethod() }
    }
    /// Per-metric exclusive source selection (HEALTH-003): manual and imported
    /// values never sum together.
    private(set) var sourcePolicies: [MetricID: MetricSourcePolicy] = [:]
    private(set) var enabledHealthTypes: Set<HealthDataType> = []
    private(set) var healthStatusMessage: String?
    private(set) var userFoods: [FoodVersion] = []
    private(set) var favorites: [FoodAlias] = []
    let healthService = HealthKitService()

    let interpreter: any NutritionInterpreter
    let dateProvider: DateProviding
    private var store: PersonalStore?
    private let modelContainer: ModelContainer?

    // MARK: Init

    init(modelContainer: ModelContainer?, dateProvider: DateProviding = SystemDateProvider(), interpreter: (any NutritionInterpreter)? = nil) {
        self.modelContainer = modelContainer
        self.dateProvider = dateProvider
        self.interpreter = interpreter ?? InterpreterFactory.make()
        self.selectedDay = LogDay(date: dateProvider.now(), timeZone: dateProvider.timeZone)
        self.completedDays = Set(UserDefaults.standard.stringArray(forKey: "completedDays") ?? [])
        restoreP1Settings()
    }

    // MARK: P1 settings persistence (UserDefaults; versioned store follows M2)

    private func restoreP1Settings() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "expenditureMethod"),
           let method = try? JSONDecoder().decode(ExpenditureMethod.self, from: data) {
            expenditureMethod = method
        }
        if let raw = defaults.dictionary(forKey: "sourcePolicies") as? [String: String] {
            for (key, value) in raw {
                if let policy = MetricSourcePolicy(rawValue: value) {
                    sourcePolicies[MetricID(key)] = policy
                }
            }
        }
        if let raw = defaults.stringArray(forKey: "enabledHealthTypes") {
            enabledHealthTypes = Set(raw.compactMap { HealthDataType(rawValue: $0) })
        }
        if let mode = defaults.string(forKey: "balanceMode").flatMap(BalanceGoalMode.init(rawValue:)) {
            balanceMode = mode
        }
    }

    private func persistExpenditureMethod() {
        let defaults = UserDefaults.standard
        if let method = expenditureMethod, let data = try? JSONEncoder().encode(method) {
            defaults.set(data, forKey: "expenditureMethod")
        } else {
            defaults.removeObject(forKey: "expenditureMethod")
        }
    }

    private func persistHealthSettings() {
        let defaults = UserDefaults.standard
        defaults.set(
            sourcePolicies.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value.rawValue },
            forKey: "sourcePolicies"
        )
        defaults.set(enabledHealthTypes.map(\.rawValue), forKey: "enabledHealthTypes")
    }

    var isSelectedDayToday: Bool {
        selectedDay == LogDay(date: dateProvider.now(), timeZone: dateProvider.timeZone)
    }

    var dateContext: GoalDateContext {
        GoalDateContext(
            logDay: selectedDay,
            now: dateProvider.now(),
            timeZone: dateProvider.timeZone,
            isPastDay: selectedDay < LogDay(date: dateProvider.now(), timeZone: dateProvider.timeZone)
        )
    }

    // MARK: Bootstrap

    func bootstrap() async {
        if store == nil, let modelContainer {
            store = PersonalStore(container: modelContainer)
        }
        do {
            if let store {
                if let existing = try store.latestConfiguration() {
                    configuration = existing
                } else {
                    // First launch: publish the owner template as version 1.
                    let owner = OwnerTemplate.configuration(effectiveFrom: selectedDay)
                    try store.publish(configuration: owner)
                    configuration = owner
                }
                ledger = try store.loadLedger()
                userFoods = (try? store.loadUserFoods()) ?? []
                favorites = (try? store.loadAliases()) ?? []
            } else {
                configuration = OwnerTemplate.configuration(effectiveFrom: selectedDay)
            }
            try reloadDay()
        } catch {
            lastError = "Could not load stored data: \(error.localizedDescription)"
        }
        interpreterAvailability = await interpreter.availability()
    }

    func selectDay(_ day: LogDay) {
        selectedDay = day
        do {
            // Historical status uses the configuration effective that day (UI-015).
            if let store, let effective = try store.configuration(effectiveOn: day) {
                configuration = effective
            }
            try reloadDay()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func reloadDay() throws {
        if let store {
            dayObservations = try store.observations(on: selectedDay)
        }
        publishWidgetSnapshot()
    }

    /// Publish the day summary for widgets after every reload/mutation so
    /// widgets track the same records as the app (UI-002, DEVICE-003). The
    /// snapshot is coarse day-level data only — nothing sensitive beyond the
    /// totals the user chose to track.
    private func publishWidgetSnapshot() {
        let water = aggregated(OwnerMetrics.water)
        let protein = aggregated(OwnerMetrics.protein)
        let supplements = aggregated(OwnerMetrics.supplements)
        let evaluationMap = evaluations()

        var statuses: [String: String] = [:]
        let titles: [(GoalID, String)] = [
            (OwnerGoals.water, "Hydration"),
            (OwnerGoals.nutritionGroup, "Nutrition"),
            (OwnerGoals.exercise, "Exercise"),
            (OwnerGoals.supplements, "Supplements")
        ]
        for (goalID, title) in titles {
            if let evaluation = evaluationMap[goalID] {
                statuses[title] = evaluation.status.rawValue
            }
        }

        WidgetSnapshotStore.write(WidgetSnapshot(
            dayISO: selectedDay.isoString,
            waterML: water.hasAnyObservation ? water.numericValue : nil,
            waterGoalML: configuration?.goals.first { $0.id == OwnerGoals.water }?.bounds.metMinimum,
            proteinG: protein.hasAnyObservation ? protein.numericValue : nil,
            proteinGoalG: configuration?.goals.first { $0.id == OwnerGoals.protein }?.bounds.metMinimum,
            supplementsDone: supplements.checklistDone,
            supplementsTotal: supplements.checklistTotal,
            statuses: statuses,
            generatedAt: dateProvider.now()
        ))
    }

    // MARK: Aggregation and evaluation

    func metricDefinition(_ id: MetricID) -> MetricDefinition? {
        configuration?.metrics.first { $0.id == id }
    }

    func aggregated(_ metricID: MetricID) -> AggregatedMetricValue {
        // Nutrition totals come from the meal ledger, not observations (FOOD-019).
        if let nutrientID = nutritionMetricMap[metricID] {
            let totals = ledger.dayNutrientTotals(logDay: selectedDay, nutrientIDs: [nutrientID])
            guard let entry = totals[nutrientID], entry.hasData else {
                return .unrecorded(metricID)
            }
            return AggregatedMetricValue(
                metricID: metricID,
                numericValue: NSDecimalNumber(decimal: entry.total).doubleValue,
                coverage: entry.coverage == .none ? .complete : entry.coverage,
                hasAnyObservation: true
            )
        }
        guard let metric = metricDefinition(metricID) else { return .unrecorded(metricID) }
        // Exclusive source selection (HEALTH-003): only observations admitted
        // by the metric's policy participate; manual + imported never sum.
        let policy = sourcePolicies[metricID] ?? .manual
        let admitted = dayObservations.filter { policy.admits($0.source) }
        return MetricAggregator.aggregate(metric: metric, observations: admitted)
    }

    /// Direct daily sum of imported health observations for metrics that are
    /// engine inputs rather than dashboard cards (ENERGY-003).
    private func importedHealthTotal(_ metricID: MetricID) -> Double? {
        var total = 0.0
        var found = false
        for observation in dayObservations where observation.metricID == metricID && observation.source == .healthKit {
            if case .quantity(let value, _) = observation.value {
                total += value
                found = true
            }
        }
        return found ? total : nil
    }

    /// All goal evaluations for the selected day using the one production
    /// evaluator (GOAL-001); Builder preview calls the same functions.
    func evaluations() -> [GoalID: GoalEvaluation] {
        guard let configuration else { return [:] }
        var results: [GoalID: GoalEvaluation] = [:]
        // First pass: scalar goals.
        for goal in configuration.goals where goal.kind != .composite {
            let value = goal.metricID.map { aggregated($0) }
            results[goal.id] = GoalEvaluator.evaluate(goal: goal, value: value, dateContext: dateContext)
        }
        // Second pass: composites over member results.
        for goal in configuration.goals where goal.kind == .composite {
            if goal.compositeRule == .ownerExercise {
                let workout = aggregated(OwnerMetrics.workoutDone)
                let steps = aggregated(OwnerMetrics.steps)
                results[goal.id] = GoalEvaluator.evaluateOwnerExercise(
                    goalID: goal.id,
                    workoutDone: workout.hasAnyObservation ? workout.numericValue.map { $0 > 0 } : nil,
                    steps: steps.hasAnyObservation ? steps.numericValue : nil
                )
            } else if goal.id == OwnerGoals.calorieBalance {
                results[goal.id] = GoalEvaluation(goalID: goal.id, status: energySummary().status, reason: energySummary().explanation)
            } else {
                let members = goal.memberGoalIDs.compactMap { results[$0] }
                results[goal.id] = GoalEvaluator.evaluateComposite(goal: goal, memberEvaluations: members)
            }
        }
        return results
    }

    func energySummary() -> EnergyDayResult {
        let intake = aggregated(OwnerMetrics.calories)
        let active = aggregated(OwnerMetrics.activeEnergy)
        let dayMarkedComplete = completedDays.contains(selectedDay.isoString)

        // Method selection is exclusive (ENERGY-005): the generalized engine
        // only reads the inputs its method defines.
        guard let method = expenditureMethod ?? restingInput.map({ ExpenditureMethod.restingPlusActive($0) }) else {
            return EnergyEngine.evaluateDay(
                intakeKcal: intake.hasAnyObservation ? intake.numericValue : nil,
                intakeCoverageComplete: dayMarkedComplete,
                restingInput: nil,
                activeKcal: active.hasAnyObservation ? active.numericValue : nil,
                activeConfirmed: dayMarkedComplete,
                mode: balanceMode
            )
        }

        let inputs = ExpenditureInputs(
            loggedActiveKcal: active.hasAnyObservation ? active.numericValue : nil,
            healthKitRestingKcal: importedHealthTotal(HealthMetrics.restingEnergy),
            healthKitActiveKcal: importedHealthTotal(HealthMetrics.activeEnergy),
            // Same-day samples cannot cover the full day yet (ENERGY-003).
            healthKitCoversFullDay: dateContext.isPastDay
        )
        return EnergyEngine.evaluateDay(
            intakeKcal: intake.hasAnyObservation ? intake.numericValue : nil,
            intakeCoverageComplete: dayMarkedComplete,
            method: method,
            inputs: inputs,
            dayMarkedComplete: dayMarkedComplete,
            mode: balanceMode
        )
    }

    func markSelectedDayComplete(_ complete: Bool) {
        if complete {
            completedDays.insert(selectedDay.isoString)
        } else {
            completedDays.remove(selectedDay.isoString)
        }
        UserDefaults.standard.set(Array(completedDays), forKey: "completedDays")
    }

    // MARK: Direct tracker edits

    /// Quick increment or direct numeric edit (UI-006). Nutrition metrics
    /// become auditable ledger adjustments; other metrics become observations.
    func increment(_ metricID: MetricID, by amount: Double) {
        guard amount != 0 else { return }
        if let nutrientID = nutritionMetricMap[metricID] {
            let current = ledger.dayNutrientTotals(logDay: selectedDay, nutrientIDs: [nutrientID])[nutrientID]?.total ?? 0
            let target = current + Decimal(amount)
            applyMutation { ledger, now in
                _ = ledger.applyAbsoluteTotalEdit(
                    logDay: self.selectedDay, nutrientID: nutrientID,
                    targetTotal: target, currentDerivedTotal: current,
                    mutationID: UUID(), at: now
                )
                return []
            }
            return
        }
        guard let metric = metricDefinition(metricID) else { return }
        let value: ObservedValue
        switch metric.valueType {
        case .countValue:
            value = .count(Int(amount))
        default:
            value = .quantity(amount, metric.canonicalUnit ?? .count)
        }
        saveObservation(metricID: metricID, value: value)
    }

    /// Set an absolute daily value (exact-value editor, FOOD-020 semantics for
    /// nutrition; a visible correcting delta for summed observations).
    func setDailyTotal(_ metricID: MetricID, to target: Double) {
        if let nutrientID = nutritionMetricMap[metricID] {
            let current = ledger.dayNutrientTotals(logDay: selectedDay, nutrientIDs: [nutrientID])[nutrientID]?.total ?? 0
            applyMutation { ledger, now in
                _ = ledger.applyAbsoluteTotalEdit(
                    logDay: self.selectedDay, nutrientID: nutrientID,
                    targetTotal: Decimal(target), currentDerivedTotal: current,
                    mutationID: UUID(), at: now
                )
                return []
            }
            return
        }
        let current = aggregated(metricID).numericValue ?? 0
        increment(metricID, by: target - current)
    }

    func setBoolean(_ metricID: MetricID, to newValue: Bool) {
        saveObservation(metricID: metricID, value: .boolean(newValue))
    }

    /// AM/PM supplement toggles: independent, persistent, and always followed
    /// by status recalculation (UI-007).
    func toggleChecklistItem(_ metricID: MetricID, item: String) {
        var state: [String: Bool] = [:]
        if let metric = metricDefinition(metricID), let items = metric.checklistItems {
            for name in items { state[name] = false }
        }
        // Rebuild current state from today's observations.
        for observation in dayObservations where observation.metricID == metricID {
            if case .checklist(let items) = observation.value {
                for (key, done) in items { state[key] = done }
            }
        }
        state[item] = !(state[item] ?? false)
        saveObservation(metricID: metricID, value: .checklist(state))
    }

    func saveInterval(_ metricID: MetricID, interval: DatedInterval) {
        saveObservation(metricID: metricID, value: .interval(interval))
    }

    private func saveObservation(metricID: MetricID, value: ObservedValue) {
        saveState = .saving
        let observation = Observation(
            metricID: metricID,
            value: value,
            observedAt: dateProvider.now(),
            timeZoneIdentifier: dateProvider.timeZone.identifier,
            logDay: selectedDay,
            source: .manual
        )
        do {
            try store?.save(observation: observation)
            try reloadDay()
            saveState = .saved
        } catch {
            // Save failed is shown truthfully; the value is not displayed as
            // saved (STORE-003, UI-010).
            saveState = .error(error.localizedDescription)
        }
    }

    // MARK: Meal ledger mutations

    /// Run a ledger mutation and persist it atomically. Returns touched entry IDs.
    private func applyMutation(_ mutate: (inout MealLedger, Date) throws -> [UUID]) {
        saveState = .saving
        var working = ledger
        do {
            let touched = try mutate(&working, dateProvider.now())
            try store?.persist(ledger: working, touchedEntryIDs: touched)
            ledger = working
            saveState = .saved
        } catch {
            saveState = .error(error.localizedDescription)
        }
    }

    /// Commit a confirmed meal preview (CHAT-002 review-first default). The
    /// mutation ID comes from the preview so double-confirmation is idempotent
    /// (CHAT-016, REG-031).
    func commitMeal(items: [MealItemSnapshot], mealLabel: String?, mutationID: UUID) -> UUID? {
        var committedID: UUID?
        applyMutation { ledger, now in
            let entry = try ledger.commitMeal(
                logDay: self.selectedDay,
                mealLabel: mealLabel,
                items: items,
                mutationID: mutationID,
                at: now
            )
            committedID = entry.id
            return [entry.id]
        }
        return committedID
    }

    func reviseMeal(entryID: UUID, expectedRevision: Int, newItems: [MealItemSnapshot], mutationID: UUID, note: String?) {
        applyMutation { ledger, now in
            _ = try ledger.reviseMeal(
                entryID: entryID, expectedRevision: expectedRevision,
                newItems: newItems, mutationID: mutationID, note: note, at: now
            )
            return [entryID]
        }
    }

    func removeMeal(entryID: UUID) {
        applyMutation { ledger, now in
            _ = try ledger.removeMeal(entryID: entryID, mutationID: UUID(), at: now)
            return [entryID]
        }
    }

    func undoLastRevision(entryID: UUID) {
        applyMutation { ledger, now in
            _ = try ledger.undoLastRevision(entryID: entryID, mutationID: UUID(), at: now)
            return [entryID]
        }
    }

    /// Reset the selected day only (UI-010, REG-054): confirmation and Undo are
    /// handled by the calling view; configuration, favorites, and other days
    /// are untouched.
    func resetSelectedDay() {
        saveState = .saving
        do {
            for observation in dayObservations {
                try store?.markObservationDeleted(id: observation.id)
            }
            var working = ledger
            let touched = working.entriesForDay(selectedDay).map(\.id)
            working.resetDay(selectedDay, mutationID: UUID(), at: dateProvider.now())
            try store?.persist(ledger: working, touchedEntryIDs: touched)
            ledger = working
            try reloadDay()
            saveState = .saved
        } catch {
            saveState = .error(error.localizedDescription)
        }
    }

    // MARK: Builder publishing

    /// Publish a new configuration version effective the selected date
    /// (BUILD-007). Validation failures leave the current version untouched.
    func publishConfiguration(_ draft: TrackerConfiguration) throws {
        var next = draft
        next.version = (configuration?.version ?? 0) + 1
        if let store {
            try store.publish(configuration: next)
        } else if let first = ConfigurationValidator.validate(next).first {
            throw first
        }
        configuration = next
    }

    // MARK: HealthKit (P1, read-only)

    /// Enable or disable one health type. Enabling requests permission for
    /// exactly that set (HEALTH-001) and switches the affected metric's source
    /// policy; disabling stops future imports (HEALTH-007) and returns the
    /// metric to manual entry.
    func setHealthType(_ type: HealthDataType, enabled: Bool) async {
        if enabled {
            do {
                try await healthService.requestReadAuthorization(for: enabledHealthTypes.union([type]))
            } catch {
                // HEALTH-002: unavailable is reported as unavailable; a denied
                // read is indistinguishable from no data and never claimed.
                healthStatusMessage = "Health data is not available on this device."
                return
            }
            enabledHealthTypes.insert(type)
        } else {
            enabledHealthTypes.remove(type)
        }
        switch type {
        case .steps:
            sourcePolicies[OwnerMetrics.steps] = enabled ? .healthKit : .manual
        case .activeEnergy:
            sourcePolicies[OwnerMetrics.activeEnergy] = enabled ? .healthKit : .manual
        case .sleep:
            sourcePolicies[OwnerMetrics.sleep] = enabled ? .healthKit : .manual
        case .restingEnergy, .bodyMass:
            break
        }
        persistHealthSettings()
        if enabled {
            await importHealthData()
        }
    }

    /// Import the enabled types for the selected day. Idempotent: daily totals
    /// carry stable external sample IDs, and each metric/day import replaces
    /// the previous imported set (HEALTH-003).
    func importHealthData() async {
        guard let store, !enabledHealthTypes.isEmpty else { return }
        let timeZone = dateProvider.timeZone
        let now = dateProvider.now()
        let day = selectedDay
        var failures: [String] = []

        for type in enabledHealthTypes {
            do {
                switch type {
                case .steps, .activeEnergy, .restingEnergy, .bodyMass:
                    let value = try await healthService.dailyQuantity(type, day: day, timeZone: timeZone)
                    // Which metrics this type's daily total feeds. Active energy
                    // feeds the engine input, and additionally the dashboard
                    // metric only while that metric's policy is healthKit — the
                    // policy keeps sources exclusive either way (ENERGY-005).
                    var targets: [(MetricID, UnitOfMeasure)]
                    switch type {
                    case .steps: targets = [(OwnerMetrics.steps, .step)]
                    case .restingEnergy: targets = [(HealthMetrics.restingEnergy, .kilocalorie)]
                    case .bodyMass: targets = [(HealthMetrics.bodyMass, .kilogram)]
                    case .activeEnergy:
                        targets = [(HealthMetrics.activeEnergy, .kilocalorie), (OwnerMetrics.activeEnergy, .kilocalorie)]
                    case .sleep: targets = []
                    }
                    for (metricID, unit) in targets {
                        // No readable samples -> the imported set is empty:
                        // unknown stays unknown, and the UI never claims the
                        // user denied permission (HEALTH-002).
                        let observations = value.map { value in
                            [HealthImportMapper.observation(
                                from: ImportedDailyQuantity(metricID: metricID, day: day, value: value, unit: unit, coversFullDay: dateContext.isPastDay),
                                timeZone: timeZone, importedAt: now
                            )]
                        } ?? []
                        try store.replaceHealthObservations(metricID: metricID, day: day, with: observations)
                    }
                case .sleep:
                    let intervals = try await healthService.sleepIntervals(day: day, timeZone: timeZone)
                    let observations = HealthImportMapper.sleepObservations(
                        metricID: OwnerMetrics.sleep, intervals: intervals,
                        day: day, timeZone: timeZone, importedAt: now
                    )
                    try store.replaceHealthObservations(metricID: OwnerMetrics.sleep, day: day, with: observations)
                }
            } catch {
                failures.append(type.displayName)
            }
        }
        healthStatusMessage = failures.isEmpty
            ? "Imported \(day.isoString) from Health."
            : "Could not read: \(failures.joined(separator: ", ")). Existing values are unchanged."
        try? reloadDay()
    }

    /// Disconnect entirely: stops imports; optionally clears imported copies.
    /// Samples in the health store itself are never deleted (HEALTH-007).
    func disconnectHealth(clearImportedCopies: Bool) {
        enabledHealthTypes = []
        sourcePolicies[OwnerMetrics.steps] = .manual
        sourcePolicies[OwnerMetrics.activeEnergy] = .manual
        sourcePolicies[OwnerMetrics.sleep] = .manual
        persistHealthSettings()
        if clearImportedCopies {
            try? store?.deleteAllHealthObservations()
            try? reloadDay()
        }
        healthStatusMessage = "Health imports stopped."
    }

    // MARK: User foods and favorites (P1)

    /// Save a reviewed label-capture food (DEVICE-002). Private, never shared.
    func saveUserFood(_ food: FoodVersion) {
        do {
            try store?.saveUserFood(food)
            if !userFoods.contains(where: { $0.id == food.id }) {
                userFoods.append(food)
            }
        } catch {
            lastError = "Could not save food: \(error.localizedDescription)"
        }
    }

    /// Save a favorite: identity plus preferred portion (FOOD-014).
    func saveFavorite(_ alias: FoodAlias) {
        do {
            try store?.saveAlias(alias)
            favorites.removeAll { $0.id == alias.id }
            favorites.append(alias)
        } catch {
            lastError = "Could not save favorite: \(error.localizedDescription)"
        }
    }

    /// All foods resolvable locally: the user's own label foods plus seeds.
    var resolvableFoods: [FoodVersion] {
        SeedCatalog.foods + userFoods
    }

    var resolvableAliases: [FoodAlias] {
        SeedCatalog.aliases + favorites
    }

    // MARK: History

    func daysWithData(last count: Int) -> [LogDay: Bool] {
        let today = LogDay(date: dateProvider.now(), timeZone: dateProvider.timeZone)
        let start = today.adding(days: -(count - 1))
        var result: [LogDay: Bool] = [:]
        var dataDays = Set<LogDay>()
        if let store {
            dataDays = (try? store.daysWithData(in: start...today)) ?? []
        }
        var day = start
        while day <= today {
            result[day] = dataDays.contains(day)
            day = day.adding(days: 1)
        }
        return result
    }
}
