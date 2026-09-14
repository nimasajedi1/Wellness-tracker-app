import SwiftUI
import WellnessCore

/// Visual builder, P0 M2 slice (section 7): card library + live edits +
/// inspector, with safe drafts. Edits stay in a draft until Save publishes a
/// new configuration version effective today (BUILD-006/007); Cancel restores
/// the published layout. Reordering and width changes work without drag
/// gestures (BUILD-003, A11Y-004).
struct BuilderView: View {
    @Environment(AppModel.self) private var appModel
    @State private var draft: TrackerConfiguration?
    @State private var inspectingCard: LayoutCard?
    @State private var showAddField = false
    @State private var publishError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    editor(draft)
                } else {
                    ContentUnavailableView("Loading configuration…", systemImage: "square.grid.2x2")
                }
            }
            .navigationTitle("Builder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { resetDraft() }
                        .disabled(!hasChanges)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { publish() }
                        .disabled(!hasChanges)
                }
            }
            .alert("Could not save", isPresented: Binding(
                get: { publishError != nil },
                set: { if !$0 { publishError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(publishError ?? "")
            }
            .sheet(item: $inspectingCard) { card in
                CardInspectorView(card: card) { updated in
                    updateCard(updated)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showAddField) {
                AddFieldSheet { metric, goal, card in
                    addField(metric: metric, goal: goal, card: card)
                }
            }
            .task {
                if draft == nil { draft = appModel.configuration }
            }
            .onChange(of: appModel.configuration?.id) {
                if !hasChanges { draft = appModel.configuration }
            }
        }
    }

    private var hasChanges: Bool {
        draft != appModel.configuration && draft != nil
    }

    private func editor(_ draft: TrackerConfiguration) -> some View {
        List {
            Section {
                Button {
                    showAddField = true
                } label: {
                    Label("Add field…", systemImage: "plus.circle")
                }
                Menu {
                    // BUILD-001/BUILD-013: templates are views over the same
                    // canonical metric IDs; switching never duplicates the
                    // underlying fact stream, and Travel applies only on this
                    // explicit selection.
                    Button("Owner") { loadTemplate(OwnerTemplate.configuration(effectiveFrom: appModel.selectedDay)) }
                    Button("Minimal day") { loadTemplate(OwnerTemplate.minimalDay(effectiveFrom: appModel.selectedDay)) }
                    Button("Busy workday") { loadTemplate(OwnerTemplate.busyWorkday(effectiveFrom: appModel.selectedDay)) }
                    Button("Travel day") { loadTemplate(OwnerTemplate.travelDay(effectiveFrom: appModel.selectedDay)) }
                    Button("Blank") { loadTemplate(OwnerTemplate.blank(effectiveFrom: appModel.selectedDay)) }
                } label: {
                    Label("Start from template…", systemImage: "square.on.square")
                }
            } footer: {
                Text("New fields are typed registry entries — a caffeine limit or a stretch-break count needs no code and no migration. Templates are starting points over the same data; loading one is a draft until Save.")
            }

            Section("Cards (top to bottom)") {
                let cards = draft.layout.sorted { $0.order < $1.order }
                ForEach(cards) { card in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.title ?? card.cardID)
                                .font(.subheadline.weight(.medium))
                                .strikethrough(card.isHidden)
                            Text("\(card.width == .full ? "Full width" : "Half width")\(card.isHidden ? " · hidden" : "")")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Menu {
                            Button("Move up") { move(card, by: -1) }
                                .disabled(cards.first?.cardID == card.cardID)
                            Button("Move down") { move(card, by: 1) }
                                .disabled(cards.last?.cardID == card.cardID)
                            Button(card.width == .full ? "Make half width" : "Make full width") {
                                var updated = card
                                updated.width = card.width == .full ? .half : .full
                                updateCard(updated)
                            }
                            Button(card.isHidden ? "Show" : "Hide from view") {
                                // BUILD-008: hiding keeps history and collection.
                                var updated = card
                                updated.isHidden.toggle()
                                updateCard(updated)
                            }
                            Button("Inspect…") { inspectingCard = card }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Edit \(card.title ?? card.cardID)")
                    }
                }
            }

            Section("Preview") {
                BuilderPreview(draft: draft)
            } footer: {
                Text("Preview uses the production goal evaluator, not separate mock colors (BUILD-005). Save applies from today; past days keep their versions.")
            }
        }
    }

    private func resetDraft() {
        draft = appModel.configuration
    }

    private func loadTemplate(_ template: TrackerConfiguration) {
        draft = template
    }

    private func publish() {
        guard let draft else { return }
        do {
            try appModel.publishConfiguration(draft)
            self.draft = appModel.configuration
        } catch {
            // Validation failure is atomic: nothing was applied (SEC-002).
            publishError = String(describing: error)
        }
    }

    private func move(_ card: LayoutCard, by offset: Int) {
        guard var draft else { return }
        var cards = draft.layout.sorted { $0.order < $1.order }
        guard let index = cards.firstIndex(where: { $0.cardID == card.cardID }) else { return }
        let target = index + offset
        guard cards.indices.contains(target) else { return }
        cards.swapAt(index, target)
        for (newOrder, var item) in cards.enumerated() {
            item.order = newOrder
            cards[newOrder] = item
        }
        draft.layout = cards
        self.draft = draft
    }

    private func updateCard(_ card: LayoutCard) {
        guard var draft else { return }
        if let index = draft.layout.firstIndex(where: { $0.cardID == card.cardID }) {
            draft.layout[index] = card
            self.draft = draft
        }
    }

    private func addField(metric: MetricDefinition, goal: GoalConfiguration?, card: LayoutCard) {
        guard var draft else { return }
        draft.metrics.append(metric)
        if let goal { draft.goals.append(goal) }
        var newCard = card
        newCard.order = (draft.layout.map(\.order).max() ?? -1) + 1
        draft.layout.append(newCard)
        self.draft = draft
    }
}

/// Live phone-shaped preview using the real evaluator against scenario values.
struct BuilderPreview: View {
    @Environment(AppModel.self) private var appModel
    let draft: TrackerConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(draft.layout.filter { !$0.isHidden }.sorted { $0.order < $1.order }) { card in
                HStack {
                    Text(card.title ?? card.cardID)
                        .font(.caption2)
                    Spacer()
                }
                .padding(6)
                .frame(maxWidth: card.width == .full ? .infinity : 180, alignment: .leading)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Inspector for one card (BUILD-002/004 slice): rename, width, visibility,
/// and the goal thresholds of the metrics on the card.
struct CardInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var card: LayoutCard
    let onSave: (LayoutCard) -> Void

    init(card: LayoutCard, onSave: @escaping (LayoutCard) -> Void) {
        _card = State(initialValue: card)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Card") {
                    TextField("Title", text: Binding(
                        get: { card.title ?? "" },
                        set: { card.title = $0.isEmpty ? nil : $0 }
                    ))
                    Picker("Width", selection: $card.width) {
                        Text("Half").tag(CardWidth.half)
                        Text("Full").tag(CardWidth.full)
                    }
                    Toggle("Hidden", isOn: $card.isHidden)
                }
                Section {
                    Text("Metrics: \(card.metricIDs.map(\.rawValue).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                } footer: {
                    Text("Hiding keeps history and collection settings; deleting records is a separate privacy action (BUILD-008).")
                }
            }
            .navigationTitle("Inspect card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onSave(card)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Typed custom-field creation (BUILD-010): pick a value type and optional goal
/// kind; no formulas, no code. Creating "caffeine with a personal maximum"
/// is this sheet's acceptance path (OUT-004).
struct AddFieldSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (MetricDefinition, GoalConfiguration?, LayoutCard) -> Void

    @State private var name = ""
    @State private var category = "custom"
    @State private var valueType: MetricValueType = .quantity
    @State private var unit: UnitOfMeasure = .milligram
    @State private var step = "25"
    @State private var goalKind: GoalKind = .trendOnly
    @State private var targetText = ""
    @State private var nearText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Field") {
                    TextField("Name (e.g. Caffeine)", text: $name)
                    Picker("Type", selection: $valueType) {
                        Text("Quantity").tag(MetricValueType.quantity)
                        Text("Count").tag(MetricValueType.countValue)
                        Text("Rating").tag(MetricValueType.rating)
                        Text("Yes/No").tag(MetricValueType.boolean)
                    }
                    if valueType == .quantity {
                        Picker("Unit", selection: $unit) {
                            ForEach([UnitOfMeasure.milligram, .gram, .milliliter, .kilocalorie, .minute], id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                    }
                    TextField("Quick-add step", text: $step)
                        .keyboardType(.decimalPad)
                }
                Section("Goal") {
                    Picker("Goal type", selection: $goalKind) {
                        // BUILD-015: tracking-only is the default for new fields.
                        Text("Tracking only").tag(GoalKind.trendOnly)
                        Text("Minimum").tag(GoalKind.minimum)
                        Text("Maximum").tag(GoalKind.maximum)
                    }
                    if goalKind != .trendOnly {
                        TextField(goalKind == .maximum ? "Personal limit" : "Target", text: $targetText)
                            .keyboardType(.decimalPad)
                        TextField("Near-target allowance (optional)", text: $nearText)
                            .keyboardType(.decimalPad)
                    }
                } footer: {
                    Text("A field can be tracked with no goal and no red/green judgment.")
                }
            }
            .navigationTitle("Add field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func add() {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        // Distinct metric IDs for independent custom fields (BUILD-013).
        let metricID = MetricID("custom.\(cleanName.lowercased().replacingOccurrences(of: " ", with: "_")).\(UUID().uuidString.prefix(8))")
        let metric = MetricDefinition(
            id: metricID,
            name: cleanName,
            category: category,
            valueType: valueType,
            canonicalUnit: valueType == .quantity ? unit : (valueType == .countValue ? .count : nil),
            aggregation: valueType == .boolean ? .lastObservation : .sum,
            input: MetricInputConfig(kind: valueType == .boolean ? .toggle : .counter, step: Double(step) ?? 1)
        )

        var goal: GoalConfiguration?
        if goalKind != .trendOnly, let target = Double(targetText) {
            let near = Double(nearText) ?? 0
            let bounds: EvaluationBounds
            switch goalKind {
            case .maximum:
                bounds = EvaluationBounds(metMaximum: target, nearMaximum: target + near)
            default:
                bounds = EvaluationBounds(metMinimum: target, nearMinimum: max(target - near, 0))
            }
            goal = GoalConfiguration(
                id: GoalID("goal.\(metricID.rawValue)"),
                metricID: metricID,
                kind: goalKind == .maximum ? .maximum : .minimum,
                displayTarget: DisplayTarget(exact: target, unit: metric.canonicalUnit),
                bounds: bounds
            )
        } else {
            goal = GoalConfiguration(id: GoalID("goal.\(metricID.rawValue)"), metricID: metricID, kind: .trendOnly, scoringEnabled: false)
        }

        let card = LayoutCard(
            cardID: "card.\(metricID.rawValue)",
            title: cleanName,
            metricIDs: [metricID],
            goalIDs: goal.map { [$0.id] } ?? [],
            width: .half,
            order: 0
        )
        onAdd(metric, goal, card)
        dismiss()
    }
}
