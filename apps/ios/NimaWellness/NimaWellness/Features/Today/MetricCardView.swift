import SwiftUI
import WellnessCore

/// One dashboard card rendered from configuration data (M1.4): no per-field
/// business rules live in the view; values and statuses come from the registry,
/// aggregator, and evaluator.
struct MetricCardView: View {
    @Environment(AppModel.self) private var appModel
    let card: LayoutCard
    let onEdit: (MetricID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title ?? card.cardID)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            ForEach(card.metricIDs, id: \.rawValue) { metricID in
                metricRow(metricID)
            }
            if card.cardID == "card.calorieBalance" {
                energyRow
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func metricRow(_ metricID: MetricID) -> some View {
        if let metric = appModel.metricDefinition(metricID) {
            switch metric.valueType {
            case .boolean:
                booleanRow(metric)
            case .checklist:
                checklistRow(metric)
            case .interval:
                intervalRow(metric)
            default:
                quantityRow(metric)
            }
        }
    }

    private func quantityRow(_ metric: MetricDefinition) -> some View {
        let aggregate = appModel.aggregated(metric.id)
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.name)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(displayValue(aggregate, metric: metric))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                    if let hint = goalHint(metric) {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            Spacer()
            if let step = metric.input.step, metric.input.kind == .counter {
                Button {
                    appModel.increment(metric.id, by: step)
                } label: {
                    Text("+\(step.cleanString)\(unitSuffix(metric))")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .background(Theme.accent.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(step.cleanString) to \(metric.name)")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit(metric.id) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.name): \(displayValue(aggregate, metric: metric)). Double tap to edit exact value.")
        .accessibilityAddTraits(.isButton)
    }

    private func booleanRow(_ metric: MetricDefinition) -> some View {
        let aggregate = appModel.aggregated(metric.id)
        let isDone = (aggregate.numericValue ?? 0) > 0
        return Toggle(isOn: Binding(
            get: { isDone },
            set: { appModel.setBoolean(metric.id, to: $0) }
        )) {
            Text(metric.name)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .toggleStyle(.switch)
        .tint(Theme.accent)
    }

    private func checklistRow(_ metric: MetricDefinition) -> some View {
        let state = checklistState(metric)
        return HStack(spacing: 8) {
            ForEach(metric.checklistItems ?? [], id: \.self) { item in
                let done = state[item] ?? false
                Button {
                    appModel.toggleChecklistItem(metric.id, item: item)
                } label: {
                    Label(item, systemImage: done ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)   // A11Y-001
                        .background(done ? Theme.accent.opacity(0.2) : Theme.border.opacity(0.4))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(metric.name) \(item): \(done ? "done" : "not done")")
            }
            Spacer()
        }
    }

    private func intervalRow(_ metric: MetricDefinition) -> some View {
        let aggregate = appModel.aggregated(metric.id)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.name)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                // UI-009: duration shown as hours and minutes; open intervals
                // read as in progress, not zero.
                Text(durationText(aggregate))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            Button("Edit") { onEdit(metric.id) }
                .font(.caption)
                .frame(minHeight: 34)
        }
    }

    private var energyRow: some View {
        let energy = appModel.energySummary()
        return VStack(alignment: .leading, spacing: 4) {
            // UI-008: compact layout shows only Out and Net here; the full
            // calculation lives in details.
            HStack(spacing: 16) {
                labeledValue("Out", energy.estimatedOutKcal.map { "\(Int($0.rounded())) kcal" } ?? "—")
                labeledValue("Net", energy.netKcal.map { "\(Int($0.rounded())) kcal" } ?? "—")
                Spacer()
            }
            Text(energy.isProvisional ? "Provisional — mark the day complete in Settings to finalize" : energy.explanation)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(Theme.secondaryText)
            Text(value).font(.callout.weight(.bold)).monospacedDigit().foregroundStyle(Theme.text)
        }
    }

    // MARK: Helpers

    private func checklistState(_ metric: MetricDefinition) -> [String: Bool] {
        var state: [String: Bool] = [:]
        for observation in appModel.dayObservations where observation.metricID == metric.id {
            if case .checklist(let items) = observation.value {
                for (key, done) in items { state[key] = done }
            }
        }
        return state
    }

    private func displayValue(_ aggregate: AggregatedMetricValue, metric: MetricDefinition) -> String {
        guard aggregate.hasAnyObservation, let value = aggregate.numericValue else { return "—" }
        if metric.displayUnit == .liter, metric.canonicalUnit == .milliliter {
            return String(format: "%.2f L", value / 1000)
        }
        let unit = metric.canonicalUnit.map { " \($0.rawValue)" } ?? ""
        if value == value.rounded() {
            return "\(Int(value))\(unit == " step" ? "" : unit)"
        }
        return String(format: "%.1f%@", value, unit)
    }

    private func unitSuffix(_ metric: MetricDefinition) -> String {
        guard let unit = metric.canonicalUnit else { return "" }
        switch unit {
        case .step: return ""
        default: return " \(unit.rawValue)"
        }
    }

    private func goalHint(_ metric: MetricDefinition) -> String? {
        guard let goal = appModel.configuration?.goals.first(where: { $0.metricID == metric.id }),
              let target = goal.displayTarget else { return nil }
        let unit = target.unit == .milliliter ? "L" : (target.unit?.rawValue ?? "")
        func format(_ value: Double) -> String {
            let displayValue = target.unit == .milliliter ? value / 1000 : value
            return displayValue == displayValue.rounded() ? "\(Int(displayValue))" : String(format: "%.1f", displayValue)
        }
        if let exact = target.exact {
            if target.unit == .minute {
                return "/ \(Int(exact / 60)) h"
            }
            return "/ \(format(exact)) \(unit)"
        }
        if let lower = target.lower, let upper = target.upper {
            return "/ \(format(lower))–\(format(upper)) \(unit)"
        }
        return nil
    }

    private func durationText(_ aggregate: AggregatedMetricValue) -> String {
        guard aggregate.hasAnyObservation else { return "—" }
        guard let minutes = aggregate.numericValue else {
            return aggregate.coverage == .partial ? "In progress" : "—"
        }
        let total = Int(minutes.rounded())
        return "\(total / 60) h \(total % 60) m"
    }
}

extension Double {
    var cleanString: String {
        self == rounded() ? "\(Int(self))" : String(format: "%.1f", self)
    }
}
