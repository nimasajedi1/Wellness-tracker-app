import Foundation
import AppIntents
import SwiftData
import WellnessCore

/// Quick actions (DEVICE-003): hydration increments, supplement toggles, and
/// favorite logging exposed to Shortcuts and widgets. Every action goes
/// through the same domain commands and mutation-ID idempotence as the main
/// app; one invocation is one write, and a retry of the same invocation
/// cannot double-log.
///
/// These intents run in the app's process. Interactive widget buttons can use
/// them once the App Group is configured (see XCODE_SETUP.md) so the widget
/// extension reaches the same store.
@MainActor
enum QuickActionService {

    static func openStore() throws -> (PersonalStore, MealLedger, LogDay, TimeZone) {
        let container = try PersistenceFactory.makeContainer()
        let store = PersonalStore(container: container)
        let ledger = try store.loadLedger()
        let timeZone = TimeZone.current
        let day = LogDay(date: Date(), timeZone: timeZone)
        return (store, ledger, day, timeZone)
    }

    static func addWater(milliliters: Double) throws {
        let (store, _, day, timeZone) = try openStore()
        let observation = Observation(
            metricID: OwnerMetrics.water,
            value: .quantity(milliliters, .milliliter),
            observedAt: Date(),
            timeZoneIdentifier: timeZone.identifier,
            logDay: day,
            source: .manual
        )
        try store.save(observation: observation)
        // Keep the widget snapshot current when the intent ran outside the app
        // (the app republishes a full snapshot on next launch).
        if var snapshot = WidgetSnapshotStore.read(), snapshot.dayISO == day.isoString {
            snapshot.waterML = (snapshot.waterML ?? 0) + milliliters
            snapshot.generatedAt = Date()
            WidgetSnapshotStore.write(snapshot)
        }
    }

    static func toggleSupplement(item: String) throws {
        let (store, _, day, timeZone) = try openStore()
        var state: [String: Bool] = ["AM": false, "PM": false]
        for observation in try store.observations(on: day) where observation.metricID == OwnerMetrics.supplements {
            if case .checklist(let items) = observation.value {
                for (key, done) in items { state[key] = done }
            }
        }
        state[item] = !(state[item] ?? false)
        let observation = Observation(
            metricID: OwnerMetrics.supplements,
            value: .checklist(state),
            observedAt: Date(),
            timeZoneIdentifier: timeZone.identifier,
            logDay: day,
            source: .manual
        )
        try store.save(observation: observation)
    }

    /// Log a favorite by its saved alias and default portion (FOOD-014).
    /// Returns a summary, or nil when the favorite cannot be resolved — an
    /// unresolvable favorite is never guessed into a log.
    static func logFavorite(named name: String, foods: [FoodVersion], aliases: [FoodAlias]) throws -> String? {
        let needle = name.lowercased()
        guard let alias = aliases.first(where: { $0.alias.lowercased() == needle })
            ?? aliases.first(where: { $0.alias.lowercased().contains(needle) }) else { return nil }
        guard let portion = alias.defaultPortion else { return nil }
        guard let food = foods.first(where: { $0.foodID == alias.foodID }) else { return nil }
        guard let scaled = try? PortionEngine.scale(food: food, portion: portion) else { return nil }

        let (store, ledger, day, _) = try openStore()
        var working = ledger
        let snapshot = MealItemSnapshot.from(food: food, scaled: scaled, portionDescription: alias.alias)
        let entry = try working.commitMeal(
            logDay: day,
            mealLabel: "Favorite",
            items: [snapshot],
            mutationID: UUID(),   // one invocation = one distinct log (REG-032)
            at: Date()
        )
        try store.persist(ledger: working, touchedEntryIDs: [entry.id])
        let kcal = NutrientDisplay.displayString(snapshot.nutrients[.energyKcal] ?? .unknown(reason: "missing"), nutrientID: .energyKcal)
        return "Logged \(food.canonicalName) (\(kcal) kcal)"
    }
}

struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Add water"
    static let description = IntentDescription("Adds a water increment to today's hydration total.")

    @Parameter(title: "Amount (mL)", default: 250)
    var milliliters: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard milliliters > 0, milliliters <= 2000 else {
            return .result(dialog: "Choose an amount between 1 and 2000 mL.")
        }
        try QuickActionService.addWater(milliliters: milliliters)
        return .result(dialog: "Added \(Int(milliliters)) mL of water.")
    }
}

enum SupplementPeriod: String, AppEnum {
    case am = "AM"
    case pm = "PM"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Supplement time")
    static let caseDisplayRepresentations: [SupplementPeriod: DisplayRepresentation] = [
        .am: "AM", .pm: "PM"
    ]
}

struct ToggleSupplementIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle supplements check"
    static let description = IntentDescription("Toggles the AM or PM supplements check for today.")

    @Parameter(title: "Time", default: .am)
    var period: SupplementPeriod

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try QuickActionService.toggleSupplement(item: period.rawValue)
        return .result(dialog: "Toggled \(period.rawValue) supplements.")
    }
}

struct LogFavoriteIntent: AppIntent {
    static let title: LocalizedStringResource = "Log favorite food"
    static let description = IntentDescription("Logs a saved favorite with its preferred portion.")

    @Parameter(title: "Favorite name")
    var name: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (store, _, _, _) = try QuickActionService.openStore()
        let foods = SeedCatalog.foods + ((try? store.loadUserFoods()) ?? [])
        let aliases = SeedCatalog.aliases + ((try? store.loadAliases()) ?? [])
        if let summary = try QuickActionService.logFavorite(named: name, foods: foods, aliases: aliases) {
            return .result(dialog: "\(summary)")
        }
        // DEVICE-003/FOOD-014: no default portion or no match -> no guess.
        return .result(dialog: "No favorite named “\(name)” with a saved portion. Open the app to log it.")
    }
}

struct NimaWellnessShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddWaterIntent(),
            phrases: ["Add water in \(.applicationName)"],
            shortTitle: "Add water",
            systemImageName: "drop"
        )
        AppShortcut(
            intent: ToggleSupplementIntent(),
            phrases: ["Toggle supplements in \(.applicationName)"],
            shortTitle: "Supplements",
            systemImageName: "pills"
        )
    }
}
