import Foundation
import Observation
import WellnessCore

/// One chat transcript element. Result cards carry typed domain data; numbers
/// are always rendered from validated objects, never from model prose (CHAT-013).
struct ChatMessage: Identifiable {
    enum Content {
        case userText(String)
        case assistantText(String)
        case preview(MealPreview)
        case receipt(String)
        case clarification(InterpretedTurn.Clarification)
        case failure(String)
    }
    let id = UUID()
    let content: Content
    let timestamp: Date
}

/// A non-destructive meal preview (UI-011): totals change only after Add.
struct MealPreview: Identifiable {
    let id = UUID()
    /// Mutation ID minted at preview time so repeated confirmation is
    /// idempotent (CHAT-016).
    let mutationID = UUID()
    var items: [MealItemSnapshot]
    /// Portions parallel to `items`, kept so Save favorite can store the
    /// preferred portion with the identity (FOOD-014).
    var portions: [PortionRequest] = []
    var unresolvedMentions: [InterpretedTurn.FoodMention]
    var isHypothetical: Bool
    var logDay: LogDay
    var committedEntryID: UUID?

    var isLogged: Bool { committedEntryID != nil }
}

@MainActor
@Observable
final class ChatModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var isInterpreting = false
    var composerText = ""

    private let appModel: AppModel
    private var interpretTask: Task<Void, Never>?

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    /// Foods and aliases resolvable right now: seeds plus the user's own
    /// label-captured foods and favorites — all local, all evidence-labeled.
    private var catalogFoods: [FoodVersion] { appModel.resolvableFoods }
    private var catalogAliases: [FoodAlias] { appModel.resolvableAliases }

    // MARK: Sending

    func send() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // One foreground interpretation at a time (ARCH-005): a second send
        // while busy is visibly rejected, not queued into duplicate writes.
        guard !isInterpreting else {
            append(.assistantText("Still working on the previous message — cancel it or wait a moment."))
            return
        }
        composerText = ""
        append(.userText(text))
        isInterpreting = true
        interpretTask = Task { [weak self] in
            await self?.interpret(text)
            self?.isInterpreting = false
        }
    }

    func cancelInterpretation() {
        // CHAT-018: cancellation never commits; a late result is dropped.
        interpretTask?.cancel()
        isInterpreting = false
    }

    private func interpret(_ text: String) async {
        let context = InterpretationContext(
            selectedLogDay: appModel.selectedDay,
            activeDraftSummary: nil,
            recentEntryCandidates: appModel.ledger.entriesForDay(appModel.selectedDay)
                .filter(\.isCountedInTotals)
                .suffix(5)
                .map { entry in
                    (id: entry.id, summary: entry.currentRevision?.items.map(\.displayName).joined(separator: ", ") ?? "meal")
                },
            savedAliases: catalogAliases.map(\.alias)
        )
        do {
            let turn = try await appModel.interpreter.interpret(text, context: context)
            guard !Task.isCancelled else { return }
            await handle(turn: turn, originalText: text)
        } catch let error as InterpreterError {
            guard !Task.isCancelled else { return }
            handle(error: error, originalText: text)
        } catch {
            guard !Task.isCancelled else { return }
            append(.failure("Interpretation failed. Your text is kept — use manual entry on Today, or try again."))
            composerText = text
        }
    }

    // MARK: Turn handling

    private func handle(turn: InterpretedTurn, originalText: String) async {
        switch turn.intent {
        case .logFood, .lookupFood, .hypothetical, .compare:
            let isHypothetical = turn.intent != .logFood
            var resolvedItems: [MealItemSnapshot] = []
            var resolvedPortions: [PortionRequest] = []
            var unresolved: [InterpretedTurn.FoodMention] = []
            for mention in turn.items {
                if let resolved = await resolve(mention: mention) {
                    resolvedItems.append(resolved.snapshot)
                    resolvedPortions.append(resolved.portion)
                } else {
                    unresolved.append(mention)
                }
            }
            if resolvedItems.isEmpty && unresolved.isEmpty {
                append(.assistantText("Tell me the food and amount, e.g. “112 g of my ham”."))
                return
            }
            let preview = MealPreview(
                items: resolvedItems,
                portions: resolvedPortions,
                unresolvedMentions: unresolved,
                isHypothetical: isHypothetical,
                logDay: turn.targetLogDay ?? appModel.selectedDay
            )
            append(.preview(preview))
        case .clarify:
            if let question = turn.unresolvedQuestions.first {
                append(.clarification(question))
            } else {
                append(.assistantText("Could you say that with the food and amount?"))
            }
        case .removeEntry:
            let entries = appModel.ledger.entriesForDay(appModel.selectedDay).filter(\.isCountedInTotals)
            if let last = entries.last {
                // REG-019/020: no positive log; offer removal of an existing entry.
                let names = last.currentRevision?.items.map(\.displayName).joined(separator: ", ") ?? "meal"
                append(.assistantText("Nothing was logged from that. If you want, remove the most recent entry (\(names)) from History."))
            } else {
                append(.assistantText("Nothing was logged from that, and there is no committed entry to remove today."))
            }
        case .summarizeDay:
            append(.assistantText(daySummaryText()))
        case .recordObservation, .proposeGoalChange:
            // CHAT-008/009: observation and goal changes need their typed review
            // flows; the P0 slice directs to the visual editors.
            append(.assistantText("Use the Today card or Builder to make that change — chat-side review for it lands in the M3 slice."))
        case .reviseMeal:
            append(.assistantText("To correct a logged meal, open it in History and edit — conversational corrections land in the M3 slice."))
        case .unsupported:
            append(.assistantText("That's outside what this assistant does. It logs foods and tracker observations from plain sentences."))
        }
        _ = originalText
    }

    private func handle(error: InterpreterError, originalText: String) {
        // CHAT-014/REG-042: failures preserve text and leave manual paths usable.
        switch error {
        case .unavailable(let availability):
            append(.failure("\(Self.availabilityText(availability)) Manual entry on Today keeps working."))
        case .cancelled:
            append(.assistantText("Cancelled. Nothing was logged."))
        case .refused(let reason), .generationFailed(let reason):
            append(.failure("The on-device model could not process that (\(reason)). Your text is kept — try rephrasing or use manual entry."))
        case .budgetExceeded:
            append(.failure("That request needed too many steps. Try one food at a time or use manual entry."))
        }
        composerText = originalText
    }

    // MARK: Resolution (deterministic; the model never supplies nutrients)

    private func resolve(mention: InterpretedTurn.FoodMention) async -> (snapshot: MealItemSnapshot, portion: PortionRequest)? {
        var food: FoodVersion?
        let query = mention.normalizedQuery.lowercased()
        if mention.reference == .savedAlias || query.hasPrefix("my ") {
            if let alias = catalogAliases.first(where: { query.contains($0.alias.lowercased()) || $0.alias.lowercased().contains(query) }) {
                food = catalogFoods.first { $0.foodID == alias.foodID }
            }
        }
        if food == nil {
            food = catalogFoods.first { candidate in
                candidate.marketCountry == "US" &&
                candidate.evidence.evidenceType != .syntheticFixture &&
                candidate.canonicalName.lowercased().contains(query)
            }
        }
        guard let food else { return nil }

        let portion: PortionRequest
        if let quantity = mention.quantity, let unitString = mention.unit {
            switch unitString {
            case "g": portion = PortionRequest(.mass(Decimal(quantity), .gram))
            case "kg": portion = PortionRequest(.mass(Decimal(quantity), .kilogram))
            case "oz": portion = PortionRequest(.mass(Decimal(quantity), .ounceMass))
            case "ml", "mL": portion = PortionRequest(.volume(Decimal(quantity), .milliliter))
            case "l", "L": portion = PortionRequest(.volume(Decimal(quantity), .liter))
            case "serving", "servings": portion = PortionRequest(.servings(Decimal(quantity)))
            default: return nil
            }
        } else if let count = mention.count, let perItem = mention.perItemQuantity {
            portion = PortionRequest(.countWithUnitMass(count: Decimal(count), perItemMassG: Decimal(perItem)))
        } else {
            // No quantity: the review card must ask; no assumed portion.
            return nil
        }

        guard let scaled = try? PortionEngine.scale(food: food, portion: portion) else { return nil }
        let snapshot = MealItemSnapshot.from(
            food: food,
            scaled: scaled,
            portionDescription: describe(portion)
        )
        return (snapshot, portion)
    }

    /// Save the preview's first item as a favorite: identity plus preferred
    /// portion, never a remembered nutrient number (FOOD-012/014).
    func saveFavorite(from preview: MealPreview) {
        guard let item = preview.items.first else { return }
        let alias = FoodAlias(
            alias: item.displayName.lowercased(),
            foodID: item.foodID,
            preferredVersionID: item.foodVersionID,
            defaultPortion: preview.portions.first
        )
        appModel.saveFavorite(alias)
        append(.receipt("Saved favorite “\(alias.alias)”\(alias.defaultPortion != nil ? " with its portion" : ""). Quick actions and Shortcuts can log it."))
    }

    private func describe(_ portion: PortionRequest) -> String {
        switch portion.kind {
        case .mass(let amount, let unit): return "\(amount) \(unit.rawValue)"
        case .volume(let amount, let unit): return "\(amount) \(unit.rawValue)"
        case .servings(let n): return "\(n) serving(s)"
        case .countWithUnitMass(let count, let mass): return "\(count) × \(mass) g"
        }
    }

    // MARK: Scanner and label capture (P1)

    /// Resolve a scanned barcode through the same local catalog (DEVICE-001).
    /// Invalid checksums and unknown codes fall back to typed search — never a
    /// guessed product.
    func handleScannedBarcode(_ raw: String) {
        guard let gtin = Barcode.validatedGTIN(raw) else {
            append(.assistantText("That barcode could not be read reliably. Try again, or type the product name to search."))
            return
        }
        let keys = Set(Barcode.lookupKeys(for: gtin))
        let matches = catalogFoods.filter { food in
            food.evidence.evidenceType != .syntheticFixture &&
            food.identifiers.contains { key, value in
                (key == "gtin" || key == "upc") && keys.contains(value.filter(\.isNumber))
            }
        }
        guard let food = matches.first else {
            append(.assistantText("Barcode \(gtin) is not in your local foods. Type the product name to search, or capture its label to add it."))
            return
        }
        // Identity resolved; the portion still needs the user (LOOKUP-007).
        if case .namedServing = food.basis {
            let scaled = try? PortionEngine.scale(food: food, portion: PortionRequest(.servings(1)))
            if let scaled {
                let preview = MealPreview(
                    items: [MealItemSnapshot.from(food: food, scaled: scaled, portionDescription: "1 serving — adjust before adding")],
                    unresolvedMentions: [],
                    isHypothetical: false,
                    logDay: appModel.selectedDay
                )
                append(.preview(preview))
                return
            }
        }
        append(.assistantText("Found \(food.canonicalName). Tell me the amount (e.g. “150 g \(food.canonicalName.lowercased())”)."))
    }

    /// Announce a label-captured food saved from the review sheet (DEVICE-002).
    func announceSavedLabelFood(_ food: FoodVersion) {
        append(.receipt("Saved “\(food.canonicalName)” from your label (evidence: your transcribed label). Log it by name or amount whenever you eat it."))
    }

    // MARK: Commit

    func addPreview(_ preview: MealPreview) {
        guard !preview.isHypothetical || confirmHypotheticalPolicyAllows() else { return }
        guard !preview.isLogged else { return }
        let entryID = appModel.commitMeal(
            items: preview.items,
            mealLabel: nil,
            mutationID: preview.mutationID
        )
        guard let entryID else {
            append(.failure("Save failed — the meal was not logged. Try again."))
            return
        }
        markPreviewLogged(preview.id, entryID: entryID)
        let names = preview.items.map(\.displayName).joined(separator: ", ")
        append(.receipt("Logged: \(names). \(daySummaryText())"))
    }

    func undoCommit(_ preview: MealPreview) {
        guard let entryID = preview.committedEntryID else { return }
        appModel.removeMeal(entryID: entryID)
        append(.receipt("Removed again. \(daySummaryText())"))
    }

    private func confirmHypotheticalPolicyAllows() -> Bool {
        // A hypothetical preview can still be added deliberately by the user
        // tapping Add — that is an explicit confirmation, not a silent count.
        true
    }

    private func markPreviewLogged(_ previewID: UUID, entryID: UUID) {
        for index in messages.indices {
            if case .preview(var preview) = messages[index].content, preview.id == previewID {
                preview.committedEntryID = entryID
                messages[index] = ChatMessage(content: .preview(preview), timestamp: messages[index].timestamp)
            }
        }
    }

    // MARK: Summary

    /// Deterministic daily summary above the composer (section 6.4): computed
    /// from committed records, identical to the dashboard (UI-002).
    func daySummaryText() -> String {
        let protein = appModel.aggregated(OwnerMetrics.protein)
        let calories = appModel.aggregated(OwnerMetrics.calories)
        let fiber = appModel.aggregated(OwnerMetrics.fiber)
        func text(_ label: String, _ aggregate: AggregatedMetricValue, unit: String) -> String {
            guard aggregate.hasAnyObservation, let value = aggregate.numericValue else { return "\(label) —" }
            let suffix = aggregate.coverage == .partial ? " (some values unknown)" : ""
            return "\(label) \(value.cleanString) \(unit)\(suffix)"
        }
        return [
            text("Protein", protein, unit: "g"),
            text("Fiber", fiber, unit: "g"),
            text("Calories", calories, unit: "kcal")
        ].joined(separator: " · ")
    }

    static func availabilityText(_ availability: InterpreterAvailability) -> String {
        switch availability {
        case .ready: return "On-device model ready."
        case .deviceNotSupported: return "This device does not support the on-device model."
        case .intelligenceDisabled: return "Apple Intelligence is turned off — enable it in Settings to use chat interpretation."
        case .modelNotReady: return "The on-device model is still downloading or preparing."
        case .unsupportedLocale: return "The on-device model does not support the current language setting."
        case .unknown(let detail): return "Model state unknown (\(detail))."
        }
    }

    private func append(_ content: ChatMessage.Content) {
        messages.append(ChatMessage(content: content, timestamp: Date()))
    }
}

