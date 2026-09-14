import WidgetKit
import SwiftUI

/// Widget extension (DEVICE-003).
///
/// Xcode setup (see also XCODE_SETUP.md):
/// 1. File → New → Target → Widget Extension, name "NimaWellnessWidgets",
///    uncheck the configuration-intent option, and delete the template files.
/// 2. Add this file to the extension target, plus (target membership only):
///    `Infrastructure/Shared/WidgetSnapshot.swift`,
///    `Infrastructure/Persistence/PersistenceFactory.swift`,
///    `Infrastructure/Persistence/PersistentModels.swift`,
///    `Infrastructure/Persistence/PersonalStore.swift`,
///    `AppIntents/QuickActionIntents.swift`,
///    `Features/Chat/SeedCatalog.swift`, and the WellnessCore package.
/// 3. Add the App Group `group.com.nimasajedi.nimawellness` to BOTH the app
///    and the extension targets. Without it, the widget shows the last
///    snapshot and hides its interactive button instead of writing anywhere.
///
/// Privacy: the widget renders coarse day totals only; nothing else from the
/// diary reaches the lock screen by default.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let canQuickAdd: Bool
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: nil, canQuickAdd: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The app pushes reloads on every change; this hourly refresh only
        // catches day rollover.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [currentEntry()], policy: .after(next)))
    }

    private func currentEntry() -> SnapshotEntry {
        SnapshotEntry(
            date: Date(),
            snapshot: WidgetSnapshotStore.read(),
            canQuickAdd: PersistenceFactory.appGroupURL != nil
        )
    }
}

struct HydrationWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Water", systemImage: "drop.fill")
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            if let snapshot = entry.snapshot, let water = snapshot.waterML {
                Text("\(String(format: "%.2f", water / 1000)) L")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                if let goal = snapshot.waterGoalML {
                    ProgressView(value: min(water / goal, 1))
                        .tint(.blue)
                }
            } else {
                Text("—")
                    .font(.title2.weight(.bold))
                Text("Not recorded")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if entry.canQuickAdd {
                Button(intent: AddWaterIntent()) {
                    Label("+250 mL", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            } else {
                Text("Open the app to log")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct HydrationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NimaWellness.Hydration", provider: SnapshotProvider()) { entry in
            HydrationWidgetView(entry: entry)
        }
        .configurationDisplayName("Hydration")
        .description("Today's water total with a quick add.")
        .supportedFamilies([.systemSmall])
    }
}

struct StatusWidgetView: View {
    let entry: SnapshotEntry

    private func color(for status: String) -> Color {
        switch status {
        case "met": return .green
        case "near": return .yellow
        case "outside": return .red
        default: return .gray
        }
    }

    private func label(for status: String) -> String {
        switch status {
        case "met": return "On target"
        case "near": return "Near"
        case "outside": return "Outside"
        case "notScheduled": return "Not scheduled"
        case "unscored": return "Tracking"
        default: return "Incomplete"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.snapshot?.dayISO ?? "Today")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let statuses = entry.snapshot?.statuses, !statuses.isEmpty {
                ForEach(statuses.sorted(by: { $0.key < $1.key }), id: \.key) { title, status in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(for: status))
                            .frame(width: 8, height: 8)
                        Text(title)
                            .font(.caption)
                        Spacer()
                        Text(label(for: status))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Open the app to start tracking")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NimaWellness.Status", provider: SnapshotProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily status")
        .description("Today's indicator statuses at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct NimaWellnessWidgetBundle: WidgetBundle {
    var body: some Widget {
        HydrationWidget()
        StatusWidget()
    }
}
