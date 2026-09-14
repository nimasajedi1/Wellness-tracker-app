import Foundation
import SwiftData

/// Shared container construction for the app process, App Intents (which run
/// in the app process), and — once the App Group capability is added — the
/// widget extension. The store stays local-only: no CloudKit (PRIV-002).
enum PersistenceFactory {

    /// Set this to your App Group identifier after adding the capability in
    /// Xcode (see XCODE_SETUP.md). Empty string = no app group; the store
    /// lives in the app sandbox and widgets are read-only via the snapshot.
    static let appGroupIdentifier = "group.com.nimasajedi.nimawellness"

    static var appGroupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static func schema() -> Schema {
        Schema([
            ObservationRecord.self,
            MealEntryRecord.self,
            ManualAdjustmentRecord.self,
            MutationReceiptRecord.self,
            ConfigurationVersionRecord.self,
            UserFoodRecord.self,
            FoodAliasRecord.self
        ])
    }

    static func makeContainer() throws -> ModelContainer {
        let schema = schema()
        // Prefer the app-group location so quick-action intents and (later)
        // interactive widgets share one store; fall back to the default
        // sandbox location when the entitlement is not configured yet.
        if let groupURL = appGroupURL {
            let storeURL = groupURL.appendingPathComponent("NimaWellness.store")
            let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
                return container
            }
        }
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
