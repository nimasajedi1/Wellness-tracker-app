import Foundation

/// Deterministic interpreter for tests and for keeping the UI fully usable when
/// the on-device model is unavailable (ARCH-002 acceptance). It handles a small
/// set of clear phrasings; anything else returns a clarify/unsupported result —
/// it never invents nutrition facts.
public struct MockInterpreter: NutritionInterpreter {
    public var forcedAvailability: InterpreterAvailability

    public init(forcedAvailability: InterpreterAvailability = .ready) {
        self.forcedAvailability = forcedAvailability
    }

    public func availability() async -> InterpreterAvailability {
        forcedAvailability
    }

    public func interpret(_ text: String, context: InterpretationContext) async throws -> InterpretedTurn {
        guard case .ready = forcedAvailability else {
            throw InterpreterError.unavailable(forcedAvailability)
        }
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Questions and hypotheticals are previews, never logs (CHAT-001, REG-018).
        if lowered.hasSuffix("?") || lowered.hasPrefix("what about") || lowered.hasPrefix("how about")
            || lowered.contains("would this be") || lowered.hasPrefix("i might") {
            return InterpretedTurn(intent: .hypothetical, items: parseMentions(from: lowered))
        }

        // Negations and discards (CHAT-004, REG-019/020).
        if lowered.hasPrefix("i didn't") || lowered.hasPrefix("i did not")
            || lowered.contains("threw out") || lowered.contains("scrapped") {
            return InterpretedTurn(intent: .removeEntry, items: parseMentions(from: lowered))
        }

        // Corrections referencing the active draft (CHAT-003, REG-024).
        if lowered.hasPrefix("no ") && context.activeDraftSummary != nil {
            return InterpretedTurn(intent: .reviseMeal, items: parseMentions(from: lowered))
        }

        // Ambiguous quantity: "29 grams tuna, same as last time" needs a
        // clarification when mass and protein-per-can are both plausible
        // (CHAT-005, REG-023).
        if lowered.contains("same as last time") || lowered.contains("same tuna") {
            return InterpretedTurn(
                intent: .clarify,
                unresolvedQuestions: [
                    InterpretedTurn.Clarification(
                        question: "Does the number refer to food weight or protein per can?",
                        options: ["Food weight in grams", "Protein per can"]
                    )
                ]
            )
        }

        if lowered.hasPrefix("i had") || lowered.hasPrefix("i ate") || lowered.hasPrefix("log ") {
            let mentions = parseMentions(from: lowered)
            if mentions.isEmpty {
                return InterpretedTurn(
                    intent: .clarify,
                    unresolvedQuestions: [InterpretedTurn.Clarification(question: "What food and how much?")]
                )
            }
            return InterpretedTurn(intent: .logFood, items: mentions, targetLogDay: context.selectedLogDay)
        }

        return InterpretedTurn(intent: .unsupported)
    }

    /// Minimal "NNN g <food>" extraction. Deliberately conservative: quantities
    /// it cannot parse are left nil so the review flow must ask.
    func parseMentions(from text: String) -> [InterpretedTurn.FoodMention] {
        let pattern = #"(\d+(?:\.\d+)?)\s*(g|grams?|ml|oz|l)\b(?:\s+of)?\s+(?:my\s+)?([a-z][a-z\s]{1,40}?)(?:[.,?]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var mentions: [InterpretedTurn.FoodMention] = []
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match,
                  let quantityRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let nameRange = Range(match.range(at: 3), in: text) else { return }
            let quantity = Double(text[quantityRange])
            var unit = String(text[unitRange])
            if unit.hasPrefix("gram") { unit = "g" }
            let name = text[nameRange].trimmingCharacters(in: .whitespaces)
            mentions.append(InterpretedTurn.FoodMention(
                textSpan: String(text[quantityRange.lowerBound..<nameRange.upperBound]),
                normalizedQuery: name,
                quantity: quantity,
                unit: unit,
                reference: text.contains("my \(name)") ? .savedAlias : .unknown
            ))
        }
        return Array(mentions.prefix(8))
    }
}
