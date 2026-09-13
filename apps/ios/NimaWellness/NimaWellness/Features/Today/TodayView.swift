import SwiftUI
import WellnessCore

/// Compact Today dashboard (section 6.3): summary cards, quick actions, the
/// seven owner indicators, and a full-width calorie-balance row in every state
/// (UI-005). Detailed editors open in sheets rather than shrinking the layout.
struct TodayView: View {
    @Environment(AppModel.self) private var appModel
    @State private var editingMetric: MetricID?
    @State private var showResetConfirmation = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if case .error(let message) = appModel.saveState {
                        Label("Save failed: \(message)", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                    cardsGrid
                    statusGrid
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Nima Wellness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DaySelector()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        Button(role: .destructive) {
                            showResetConfirmation = true
                        } label: {
                            Label("Reset \(appModel.selectedDay.isoString)…", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog(
                "Reset \(appModel.selectedDay.isoString) on this tracker?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                // UI-010: names the date; resets only that day's observations and
                // committed food entries; configuration and other days survive.
                Button("Reset this day", role: .destructive) {
                    appModel.resetSelectedDay()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the day's tracked values and logged meals. Configuration, favorites, and other days are kept. Entries stay in the audit history.")
            }
            .sheet(item: $editingMetric) { metricID in
                ValueEditorSheet(metricID: metricID)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
        }
    }

    private var visibleCards: [LayoutCard] {
        (appModel.configuration?.layout ?? [])
            .filter { !$0.isHidden }
            .sorted { $0.order < $1.order }
    }

    /// Rows built from card widths: half-width cards pair up, full-width cards
    /// get their own row (the calorie balance card is always full-width).
    private var cardsGrid: some View {
        var rows: [[LayoutCard]] = []
        var pendingHalf: LayoutCard?
        for card in visibleCards {
            if card.width == .full {
                if let half = pendingHalf {
                    rows.append([half])
                    pendingHalf = nil
                }
                rows.append([card])
            } else if let half = pendingHalf {
                rows.append([half, card])
                pendingHalf = nil
            } else {
                pendingHalf = card
            }
        }
        if let half = pendingHalf { rows.append([half]) }

        return VStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(row) { card in
                        MetricCardView(card: card, onEdit: { editingMetric = $0 })
                    }
                }
            }
        }
    }

    /// Legacy status rows: six half-width indicators in two rows of three plus
    /// calorie balance always full-width at the bottom (UI-005, REG-010).
    private var statusGrid: some View {
        let evaluations = appModel.evaluations()
        let indicatorGoals: [GoalID] = [
            OwnerGoals.sleep, OwnerGoals.fasting, OwnerGoals.nutritionGroup,
            OwnerGoals.water, OwnerGoals.exercise, OwnerGoals.supplements
        ]
        return VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(indicatorGoals, id: \.rawValue) { goalID in
                    if let evaluation = evaluations[goalID] {
                        StatusChip(title: chipTitle(goalID), evaluation: evaluation)
                    }
                }
            }
            if let balance = evaluations[OwnerGoals.calorieBalance] {
                StatusChip(title: "Calorie balance", evaluation: balance)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func chipTitle(_ goalID: GoalID) -> String {
        switch goalID {
        case OwnerGoals.sleep: return "Sleep"
        case OwnerGoals.fasting: return "Fasting"
        case OwnerGoals.nutritionGroup: return "Nutrition"
        case OwnerGoals.water: return "Hydration"
        case OwnerGoals.exercise: return "Exercise"
        case OwnerGoals.supplements: return "Supplements"
        default: return goalID.rawValue
        }
    }
}

extension MetricID: @retroactive Identifiable {
    public var id: String { rawValue }
}

/// Colored status indicator with a text equivalent (A11Y-003): never color-only.
struct StatusChip: View {
    let title: String
    let evaluation: GoalEvaluation

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: Theme.statusSymbol(evaluation.status))
                    .imageScale(.small)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            Text(Theme.statusLabel(evaluation.status))
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.vertical, 6)
        .background(Theme.statusColor(evaluation.status).opacity(0.18))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.statusColor(evaluation.status).opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(Theme.statusLabel(evaluation.status)). \(evaluation.reason)")
    }
}

struct DaySelector: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                appModel.selectDay(appModel.selectedDay.adding(days: -1))
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous day")
            Text(appModel.isSelectedDayToday ? "Today" : appModel.selectedDay.isoString)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Button {
                appModel.selectDay(appModel.selectedDay.adding(days: 1))
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(appModel.isSelectedDayToday)
            .accessibilityLabel("Next day")
        }
    }
}
