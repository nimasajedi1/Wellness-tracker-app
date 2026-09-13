import SwiftUI
import SwiftData
import WellnessCore

@main
struct NimaWellnessApp: App {
    let container: ModelContainer
    @State private var appModel: AppModel

    init() {
        do {
            // Personal data store, separate from any future catalog store
            // (STORE-001). No CloudKit/iCloud sync in P0 (PRIV-002).
            let schema = Schema([
                ObservationRecord.self,
                MealEntryRecord.self,
                ManualAdjustmentRecord.self,
                MutationReceiptRecord.self,
                ConfigurationVersionRecord.self
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create personal data store: \(error)")
        }
        let model = AppModel(modelContainer: container)
        _appModel = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .modelContainer(container)
        }
    }
}

/// Four primary destinations sharing the selected tracker and date (section 6.1).
/// No sign-in wall: first launch works locally (UI-001).
struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
            ChatView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.text.bubble.right") }
            HistoryView()
                .tabItem { Label("History", systemImage: "calendar") }
            BuilderView()
                .tabItem { Label("Builder", systemImage: "square.grid.2x2") }
        }
        .tint(Theme.accent)
        .task {
            await appModel.bootstrap()
        }
    }
}
