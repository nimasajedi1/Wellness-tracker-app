import SwiftUI
import WellnessCore

/// Exact-value editor sheet (UI-004/UI-006): direct numeric editing and dated
/// interval editing live here instead of being crammed into the compact grid.
struct ValueEditorSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let metricID: MetricID

    @State private var numericText = ""
    @State private var intervalStart = Date()
    @State private var intervalEnd = Date()
    @State private var intervalHasEnd = true

    private var metric: MetricDefinition? {
        appModel.metricDefinition(metricID)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let metric {
                    switch metric.valueType {
                    case .interval:
                        intervalEditor(metric)
                    default:
                        numericEditor(metric)
                    }
                }
            }
            .navigationTitle(metric?.name ?? "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { populate() }
        }
    }

    @ViewBuilder
    private func numericEditor(_ metric: MetricDefinition) -> some View {
        Section {
            HStack {
                TextField("Value", text: $numericText)
                    .keyboardType(.decimalPad)
                    .font(.title2.monospacedDigit())
                if let unit = metric.canonicalUnit {
                    Text(unit.rawValue).foregroundStyle(Theme.secondaryText)
                }
            }
        } footer: {
            if nutritionMetricMap[metric.id] != nil {
                // FOOD-020: an absolute edit becomes an auditable adjustment.
                Text("Setting the daily total records a visible adjustment against logged meals. Foods added later still add normally.")
            }
        }
    }

    @ViewBuilder
    private func intervalEditor(_ metric: MetricDefinition) -> some View {
        Section {
            // STORE-007/008: real date pickers; an end before the start is a
            // date problem the user resolves here, never a modulo-24 wrap.
            DatePicker("Start", selection: $intervalStart)
            Toggle("Completed", isOn: $intervalHasEnd)
            if intervalHasEnd {
                DatePicker("End", selection: $intervalEnd)
                if intervalEnd < intervalStart {
                    Label("End is before start — check the dates", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        } footer: {
            Text("An interval without an end stays in progress; it never counts as zero.")
        }
    }

    private var canSave: Bool {
        guard let metric else { return false }
        switch metric.valueType {
        case .interval:
            return !intervalHasEnd || intervalEnd >= intervalStart
        default:
            return Double(numericText.replacingOccurrences(of: ",", with: ".")) != nil
        }
    }

    private func populate() {
        guard let metric else { return }
        if metric.valueType == .interval {
            for observation in appModel.dayObservations.reversed() where observation.metricID == metricID {
                if case .interval(let interval) = observation.value {
                    intervalStart = interval.start
                    if let end = interval.end {
                        intervalEnd = end
                        intervalHasEnd = true
                    } else {
                        intervalHasEnd = false
                    }
                    return
                }
            }
            intervalHasEnd = false
        } else if let value = appModel.aggregated(metricID).numericValue {
            numericText = value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
        }
    }

    private func save() {
        guard let metric else { return }
        switch metric.valueType {
        case .interval:
            appModel.saveInterval(metricID, interval: DatedInterval(
                start: intervalStart,
                end: intervalHasEnd ? intervalEnd : nil,
                timeZoneIdentifier: appModel.dateProvider.timeZone.identifier
            ))
        default:
            if let value = Double(numericText.replacingOccurrences(of: ",", with: ".")) {
                appModel.setDailyTotal(metricID, to: value)
            }
        }
        dismiss()
    }
}
