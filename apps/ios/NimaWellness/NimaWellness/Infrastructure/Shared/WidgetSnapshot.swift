import Foundation
import WellnessCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Read-only summary the app publishes for widgets (DEVICE-003). Deliberately
/// coarse: day-level numbers and statuses only, because widgets can appear on
/// the lock screen — no meal names, notes, or health observations beyond the
/// tracked totals the user opted to display.
///
/// Compile this file into BOTH the app target and the widget extension.
struct WidgetSnapshot: Codable, Equatable {
    var dayISO: String
    var waterML: Double?
    var waterGoalML: Double?
    var proteinG: Double?
    var proteinGoalG: Double?
    var supplementsDone: Int?
    var supplementsTotal: Int?
    /// Overall chip statuses as raw GoalStatus strings keyed by short titles.
    var statuses: [String: String]
    var generatedAt: Date
}

enum WidgetSnapshotStore {
    static let key = "widgetSnapshot.v1"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: PersistenceFactory.appGroupIdentifier)
    }

    static func read() -> WidgetSnapshot? {
        guard let defaults = sharedDefaults ?? UserDefaults(suiteName: nil),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let defaults = sharedDefaults else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

