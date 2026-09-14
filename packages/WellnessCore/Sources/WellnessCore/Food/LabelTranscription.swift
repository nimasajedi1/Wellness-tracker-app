import Foundation

/// Deterministic parser for OCR'd nutrition-label text (DEVICE-002). It only
/// proposes candidates for explicit user review — a photo can never overwrite a
/// verified food or commit anything by itself. Fields it cannot find stay
/// absent; nothing is defaulted to zero (FOOD-002).
public struct ParsedLabelField: Sendable, Equatable {
    public var value: Double
    /// The source line the value came from, shown in the review UI.
    public var sourceText: String

    public init(value: Double, sourceText: String) {
        self.value = value
        self.sourceText = sourceText
    }
}

public struct ParsedLabelCandidate: Sendable, Equatable {
    public var servingMassG: ParsedLabelField? = nil
    public var servingName: String? = nil
    public var energyKcal: ParsedLabelField? = nil
    public var proteinG: ParsedLabelField? = nil
    public var fiberG: ParsedLabelField? = nil
    public var carbohydrateG: ParsedLabelField? = nil
    public var fatG: ParsedLabelField? = nil
    public var sodiumMg: ParsedLabelField? = nil

    public init() {}

    public var hasAnyNutrient: Bool {
        energyKcal != nil || proteinG != nil || fiberG != nil
            || carbohydrateG != nil || fatG != nil || sodiumMg != nil
    }
}

public enum LabelTranscriptionParser {

    /// Parse recognized text lines into a review candidate. Conservative by
    /// design: ambiguous lines are skipped, and the first clear match per field
    /// wins (labels list each nutrient once).
    public static func parse(lines: [String]) -> ParsedLabelCandidate {
        var candidate = ParsedLabelCandidate()
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let lowered = line.lowercased()

            if candidate.servingMassG == nil,
               lowered.contains("serving") || lowered.contains("per "),
               let grams = firstNumber(in: lowered, before: "g", requireWordBoundary: true) {
                candidate.servingMassG = ParsedLabelField(value: grams, sourceText: line)
                continue
            }
            if candidate.energyKcal == nil, lowered.contains("calorie") || lowered.contains("kcal") {
                if let value = numberNear(keywords: ["calories", "calorie", "kcal"], in: lowered) {
                    candidate.energyKcal = ParsedLabelField(value: value, sourceText: line)
                    continue
                }
            }
            if candidate.proteinG == nil, lowered.contains("protein"),
               let value = numberNear(keywords: ["protein"], in: lowered) {
                candidate.proteinG = ParsedLabelField(value: value, sourceText: line)
                continue
            }
            if candidate.fiberG == nil, lowered.contains("fiber") || lowered.contains("fibre"),
               let value = numberNear(keywords: ["fiber", "fibre"], in: lowered) {
                candidate.fiberG = ParsedLabelField(value: value, sourceText: line)
                continue
            }
            if candidate.carbohydrateG == nil, lowered.contains("carbohydrate"),
               let value = numberNear(keywords: ["carbohydrate"], in: lowered) {
                candidate.carbohydrateG = ParsedLabelField(value: value, sourceText: line)
                continue
            }
            if candidate.fatG == nil, lowered.contains("total fat") || lowered.hasPrefix("fat"),
               let value = numberNear(keywords: ["fat"], in: lowered) {
                candidate.fatG = ParsedLabelField(value: value, sourceText: line)
                continue
            }
            if candidate.sodiumMg == nil, lowered.contains("sodium"),
               let value = numberNear(keywords: ["sodium"], in: lowered) {
                candidate.sodiumMg = ParsedLabelField(value: value, sourceText: line)
                continue
            }
        }
        return candidate
    }

    /// Build a reviewable FoodVersion from user-confirmed fields. Only called
    /// after explicit review; unconfirmed fields remain unknown, and the
    /// evidence type is always userEnteredLabel — never an official source.
    public static func foodVersion(
        name: String,
        confirmed: ParsedLabelCandidate,
        market: String,
        createdAt: Date
    ) -> FoodVersion? {
        guard confirmed.hasAnyNutrient, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var nutrients: [NutrientID: NutrientValue] = [:]
        func put(_ id: NutrientID, _ field: ParsedLabelField?) {
            if let field {
                nutrients[id] = field.value == 0 ? .knownZero : .known(Decimal(field.value))
            }
        }
        put(.energyKcal, confirmed.energyKcal)
        put(.proteinG, confirmed.proteinG)
        put(.fiberG, confirmed.fiberG)
        put(.carbohydrateG, confirmed.carbohydrateG)
        put(.fatG, confirmed.fatG)
        put(.sodiumMg, confirmed.sodiumMg)

        let basis: ServingBasis
        if let mass = confirmed.servingMassG {
            basis = .namedServing(name: confirmed.servingName ?? "1 serving", massG: Decimal(mass.value), volumeML: nil)
        } else {
            basis = .namedServing(name: confirmed.servingName ?? "1 serving", massG: nil, volumeML: nil)
        }

        return FoodVersion(
            foodID: "user-label-\(UUID().uuidString.prefix(8))",
            versionID: "1",
            canonicalName: name,
            marketCountry: market,
            basis: basis,
            nutrients: nutrients,
            evidence: SourceEvidence(
                sourceID: "user-label-capture",
                sourceLocator: "Label photo transcription reviewed by user",
                retrievedAt: createdAt,
                evidenceType: .userEnteredLabel
            )
        )
    }

    // MARK: - Number extraction

    static func numberNear(keywords: [String], in line: String) -> Double? {
        // Accept "protein 9g", "9 g protein", "calories 60", "60 calories".
        for keyword in keywords {
            guard let keywordRange = line.range(of: keyword) else { continue }
            let after = String(line[keywordRange.upperBound...])
            if let value = leadingNumber(in: after) { return value }
            let before = String(line[..<keywordRange.lowerBound])
            if let value = trailingNumber(in: before) { return value }
        }
        return nil
    }

    static func leadingNumber(in text: String) -> Double? {
        let pattern = #"^\s*[:\-]?\s*(\d+(?:\.\d+)?)"#
        return firstMatch(pattern, in: text)
    }

    static func trailingNumber(in text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*(?:g|mg)?\s*$"#
        return firstMatch(pattern, in: text)
    }

    static func firstNumber(in text: String, before unit: String, requireWordBoundary: Bool) -> Double? {
        let boundary = requireWordBoundary ? #"\b"# : ""
        let pattern = #"(\d+(?:\.\d+)?)\s*"# + NSRegularExpression.escapedPattern(for: unit) + boundary
        return firstMatch(pattern, in: text)
    }

    static func firstMatch(_ pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[valueRange])
    }
}
