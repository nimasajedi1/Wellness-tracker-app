import SwiftUI
import WellnessCore

/// History (UI-015): day navigation, meal and observation details, and a
/// 30-day strip where missing days show as missing — never as zero-intake
/// failures (REG-055).
struct HistoryView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            List {
                Section("Last 30 days") {
                    dayStrip
                }
                Section("Meals on \(appModel.selectedDay.isoString)") {
                    let entries = appModel.ledger.entriesForDay(appModel.selectedDay)
                    if entries.isEmpty {
                        Text("No meals recorded")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(entries) { entry in
                        MealEntryRow(entry: entry)
                    }
                }
                Section("Observations") {
                    if appModel.dayObservations.isEmpty {
                        Text("No observations recorded")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(appModel.dayObservations) { observation in
                        ObservationRow(observation: observation)
                    }
                }
                Section("Adjustments and receipts") {
                    let adjustments = appModel.ledger.adjustments.filter { $0.logDay == appModel.selectedDay && !$0.isDeleted }
                    ForEach(adjustments) { adjustment in
                        // FOOD-020: adjustments stay visible in History.
                        Label("\(adjustment.reason) (\(adjustment.deltaValue >= 0 ? "+" : "")\(adjustment.deltaValue) \(adjustment.nutrientID.rawValue))",
                              systemImage: "slider.horizontal.3")
                            .font(.footnote)
                    }
                    if adjustments.isEmpty {
                        Text("No manual adjustments")
                            .foregroundStyle(Theme.secondaryText)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DaySelector()
                }
            }
        }
    }

    private var dayStrip: some View {
        let days = appModel.daysWithData(last: 30).sorted { $0.key < $1.key }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(days, id: \.key) { day, hasData in
                    Button {
                        appModel.selectDay(day)
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(day.day)")
                                .font(.caption.weight(day == appModel.selectedDay ? .bold : .regular))
                                .monospacedDigit()
                            Circle()
                                .fill(hasData ? Theme.accent : Theme.border.opacity(0.6))
                                .frame(width: 6, height: 6)
                        }
                        .frame(width: 34, height: 44)
                        .background(day == appModel.selectedDay ? Theme.accent.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(day.isoString): \(hasData ? "has records" : "no records")")
                }
            }
        }
    }
}

struct MealEntryRow: View {
    @Environment(AppModel.self) private var appModel
    let entry: MealEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let revision = entry.currentRevision {
                HStack {
                    Text(revision.items.map(\.displayName).joined(separator: ", "))
                        .font(.subheadline.weight(.medium))
                        .strikethrough(revision.status == .deleted)
                    Spacer()
                    Text(revision.status == .deleted ? "Removed" : "Rev \(revision.revisionNumber)")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
                ForEach(revision.items) { item in
                    Text("\(item.portionDescription) · \(NutrientDisplay.displayString(item.nutrients[.energyKcal] ?? .unknown(reason: "missing"), nutrientID: .energyKcal)) kcal")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                if entry.revisions.count > 1 && revision.status != .deleted {
                    Button("Undo last change") {
                        appModel.undoLastRevision(entryID: entry.id)
                    }
                    .font(.caption)
                }
                if revision.status == .committed {
                    Button("Remove", role: .destructive) {
                        appModel.removeMeal(entryID: entry.id)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct ObservationRow: View {
    let observation: Observation

    var body: some View {
        HStack {
            Text(observation.metricID.rawValue)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(valueText)
                .font(.caption.monospacedDigit())
        }
    }

    private var valueText: String {
        switch observation.value {
        case .quantity(let amount, let unit): return "\(amount.cleanString) \(unit.rawValue)"
        case .count(let n): return "\(n)"
        case .durationMinutes(let m): return "\(Int(m)) min"
        case .boolean(let flag): return flag ? "Yes" : "No"
        case .checklist(let items):
            return items.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value ? "✓" : "–")" }.joined(separator: " ")
        case .interval(let interval):
            if let minutes = interval.elapsedMinutes {
                return "\(Int(minutes) / 60) h \(Int(minutes) % 60) m"
            }
            return interval.end == nil ? "In progress" : "Invalid interval"
        case .rating(let rating): return "\(rating)"
        case .timestamp(let date): return date.formatted(date: .omitted, time: .shortened)
        case .enumeration(let value): return value
        case .pairedQuantity(let first, let second, _): return "\(first.cleanString)/\(second.cleanString)"
        case .note: return "Note"
        }
    }
}
