import Foundation
import WellnessCore

#if canImport(FoundationModels)
import FoundationModels

/// Explicit on-device interpreter (ARCH-003): instantiates Apple's
/// SystemLanguageModel directly. No cloud routing, Private Cloud Compute, or
/// third-party provider is referenced anywhere in this target.
///
/// The @Generable mirror below is deliberately small (CHAT-012): structured
/// generation constrains shape, and the application validates every field
/// before anything can mutate state (CHAT-015).
@available(iOS 26.0, *)
final class AppleInterpreter: NutritionInterpreter, @unchecked Sendable {

    @Generable
    struct GeneratedFoodMention {
        @Guide(description: "The exact words from the user's message this mention covers")
        var textSpan: String
        @Guide(description: "Normalized food name to search, without quantity")
        var normalizedQuery: String
        @Guide(description: "Brand name if stated, otherwise omit")
        var brand: String?
        @Guide(description: "Restaurant name if stated, otherwise omit")
        var restaurant: String?
        @Guide(description: "Numeric quantity if clearly stated, otherwise omit")
        var quantity: Double?
        @Guide(description: "Unit for the quantity: g, kg, oz, mL, L, serving, count")
        var unit: String?
        @Guide(description: "Number of items when counted, e.g. 2 for 'two kotlets'")
        var count: Double?
        @Guide(description: "Mass or volume of each counted item if stated")
        var perItemQuantity: Double?
        @Guide(description: "Preparation state if stated: cooked, raw, dry, drained")
        var preparation: String?
        @Guide(description: "One of: explicitFood, savedAlias, previousEntry, unknown")
        var reference: String
    }

    @Generable
    struct GeneratedTurn {
        @Guide(description: """
        One of: logFood (user states they ate/drank something), lookupFood, \
        compare, hypothetical (question or plan, not consumed), reviseMeal \
        (correction of an existing meal), removeEntry, summarizeDay, \
        recordObservation, proposeGoalChange, clarify, unsupported
        """)
        var intent: String
        @Guide(description: "Food mentions found in the message, at most 8")
        var items: [GeneratedFoodMention]
        @Guide(description: "Candidate number (1-based) from the supplied recent-entry list this turn refers to; omit when none applies")
        var targetCandidateNumber: Int?
        @Guide(description: "One focused clarification question when the request is ambiguous; omit otherwise")
        var clarificationQuestion: String?
    }

    private let model: SystemLanguageModel

    init() {
        // Explicit selection of the on-device system model (ARCH-003, S03).
        self.model = SystemLanguageModel.default
    }

    func availability() async -> InterpreterAvailability {
        switch model.availability {
        case .available:
            return .ready
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .deviceNotSupported
            case .appleIntelligenceNotEnabled:
                return .intelligenceDisabled
            case .modelNotReady:
                return .modelNotReady
            @unknown default:
                // ARCH-004: retain an unknown-case fallback.
                return .unknown(String(describing: reason))
            }
        @unknown default:
            return .unknown(String(describing: model.availability))
        }
    }

    func interpret(_ text: String, context: InterpretationContext) async throws -> InterpretedTurn {
        guard case .ready = await availability() else {
            throw InterpreterError.unavailable(await availability())
        }

        let instructions = Self.instructions(for: context)
        let session = LanguageModelSession(model: model, instructions: instructions)

        do {
            // One bounded generation per turn by default (CHAT-011).
            let response = try await session.respond(
                to: Prompt(text),
                generating: GeneratedTurn.self
            )
            return Self.validated(response.content, context: context)
        } catch is CancellationError {
            throw InterpreterError.cancelled
        } catch {
            // Refusals, guardrail violations, and context overflows surface as a
            // reviewable fallback with the user's text preserved (CHAT-014).
            throw InterpreterError.generationFailed(String(describing: error))
        }
    }

    /// Prompt content is versioned as an app resource in later milestones
    /// (CHAT-019); this constant is prompt version p0.1.
    static func instructions(for context: InterpretationContext) -> String {
        var lines: [String] = [
            "You extract structured food-logging intent from one short message.",
            "You never invent nutrition facts, calories, or weights.",
            "Questions, plans, and 'what if' messages are hypothetical, not logFood.",
            "A correction like 'no lentils, just beans' is reviseMeal, not a new meal.",
            "If a number could mean either food mass or a nutrient amount, use intent clarify.",
            "Selected log day: \(context.selectedLogDay.isoString)."
        ]
        if let draft = context.activeDraftSummary {
            lines.append("Active draft: \(draft)")
        }
        if !context.recentEntryCandidates.isEmpty {
            lines.append("Recent entries (choose targetCandidateNumber from this list only):")
            for (index, candidate) in context.recentEntryCandidates.enumerated() {
                lines.append("\(index + 1). \(candidate.summary)")
            }
        }
        if !context.savedAliases.isEmpty {
            lines.append("Saved food aliases: \(context.savedAliases.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    /// Map and validate generated output into the domain contract. Entry
    /// targeting only resolves against the candidates the app supplied
    /// (CHAT-015); an out-of-range number is dropped.
    static func validated(_ generated: GeneratedTurn, context: InterpretationContext) -> InterpretedTurn {
        let intent = InterpretedTurn.Intent(rawValue: generated.intent) ?? .unsupported
        let items = generated.items.prefix(8).map { mention in
            InterpretedTurn.FoodMention(
                textSpan: mention.textSpan,
                normalizedQuery: mention.normalizedQuery,
                brand: mention.brand,
                restaurant: mention.restaurant,
                quantity: mention.quantity,
                unit: mention.unit,
                count: mention.count,
                perItemQuantity: mention.perItemQuantity,
                preparation: mention.preparation,
                reference: InterpretedTurn.FoodMention.Reference(rawValue: mention.reference) ?? .unknown
            )
        }
        var targetEntryID: UUID? = nil
        if let number = generated.targetCandidateNumber,
           number >= 1, number <= context.recentEntryCandidates.count {
            targetEntryID = context.recentEntryCandidates[number - 1].id
        }
        var clarifications: [InterpretedTurn.Clarification] = []
        if let question = generated.clarificationQuestion, !question.isEmpty {
            clarifications.append(InterpretedTurn.Clarification(question: question))
        }
        return InterpretedTurn(
            intent: intent,
            items: Array(items),
            targetEntryID: targetEntryID,
            targetLogDay: context.selectedLogDay,
            unresolvedQuestions: clarifications
        )
    }
}
#endif

/// Factory choosing the interpreter implementation (ARCH-002). When the
/// Foundation Models framework is unavailable at compile or run time, the app
/// falls back to the deterministic mock so manual functionality never depends
/// on the model (M0.5).
enum InterpreterFactory {
    static func make() -> any NutritionInterpreter {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return AppleInterpreter()
        }
        #endif
        return MockInterpreter(forcedAvailability: .deviceNotSupported)
    }
}
