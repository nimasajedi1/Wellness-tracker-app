import Foundation

/// Deterministic parsing of one nutrition-panel row into the structured
/// schema (DEVICE-007). The iOS 27 Vision document reader feeds table rows and
/// text lines through this parser; it never guesses a nutrient the row does
/// not name, and it keeps %DV separate from absolute amounts.
public enum LabelRowParser {

    struct KeywordEntry {
        let key: LabelNutrientKey
        let keywords: [String]
        /// Longer keywords are matched first so "saturated fat" wins over "fat".
        var longestKeyword: Int { keywords.map(\.count).max() ?? 0 }
    }

    static let keywordTable: [KeywordEntry] = [
        KeywordEntry(key: .saturatedFat, keywords: ["saturated fat", "sat. fat", "sat fat"]),
        KeywordEntry(key: .transFat, keywords: ["trans fat", "trans-fat"]),
        KeywordEntry(key: .totalFat, keywords: ["total fat", "fat total"]),
        KeywordEntry(key: .cholesterol, keywords: ["cholesterol"]),
        KeywordEntry(key: .sodium, keywords: ["sodium"]),
        KeywordEntry(key: .dietaryFiber, keywords: ["dietary fiber", "dietary fibre", "fiber", "fibre"]),
        KeywordEntry(key: .addedSugars, keywords: ["added sugars", "added sugar", "incl. added sugars", "includes added sugars"]),
        KeywordEntry(key: .totalSugars, keywords: ["total sugars", "total sugar", "sugars"]),
        KeywordEntry(key: .totalCarbohydrate, keywords: ["total carbohydrate", "total carb", "carbohydrate", "carbohydrates"]),
        KeywordEntry(key: .protein, keywords: ["protein"]),
        KeywordEntry(key: .calories, keywords: ["calories", "energy"])
    ].sorted { $0.longestKeyword > $1.longestKeyword }

    /// Parse one row of label text. Returns nil when the row names no known
    /// nutrient — unknown rows are simply not nutrition facts, never guesses.
    public static func parseNutrientRow(_ rowText: String) -> (key: LabelNutrientKey, value: ExtractedLabelValue)? {
        let lowered = rowText.lowercased()
        guard let entry = keywordTable.first(where: { candidate in
            candidate.keywords.contains { lowered.contains($0) }
        }) else { return nil }

        let dailyValue = percentDailyValue(in: lowered)
        let amount = absoluteAmount(in: lowered, canonicalUnit: entry.key.canonicalUnit)

        if amount == nil && dailyValue == nil { return nil }
        return (entry.key, ExtractedLabelValue(
            amount: amount,
            dailyValuePercent: dailyValue,
            sourceText: rowText.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: amount != nil ? .medium : .low
        ))
    }

    /// "Serving size 2 slices (56g)" -> (description, massG?, volumeML?).
    public static func parseServingSizeRow(_ rowText: String) -> (description: String, massG: Decimal?, volumeML: Decimal?)? {
        let lowered = rowText.lowercased()
        guard lowered.contains("serving size") || lowered.contains("per ") || lowered.contains("portion") else { return nil }
        let description = rowText
            .replacingOccurrences(of: "Serving size", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mass = firstNumber(before: ["g", "gram", "grams"], in: lowered)
        let volume = firstNumber(before: ["ml", "milliliter", "milliliters"], in: lowered)
        if description.isEmpty && mass == nil && volume == nil { return nil }
        return (description.isEmpty ? rowText : description, mass, volume)
    }

    /// "8 servings per container" / "servings per container: 8".
    public static func parseServingsPerContainer(_ rowText: String) -> Decimal? {
        let lowered = rowText.lowercased()
        guard lowered.contains("per container") || lowered.contains("servings per") else { return nil }
        return firstNumber(in: lowered)
    }

    // MARK: - Extraction primitives

    static func percentDailyValue(in text: String) -> Decimal? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*%"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return Decimal(string: String(text[valueRange]))
    }

    /// The absolute amount, normalized to the nutrient's canonical unit.
    /// Explicit unit suffixes only: a bare number next to a nutrient name is
    /// accepted only for calories, which print without a unit.
    static func absoluteAmount(in text: String, canonicalUnit: UnitOfMeasure) -> Decimal? {
        let unitPatterns: [(String, Decimal, UnitOfMeasure)] = [
            ("mcg", Decimal(string: "0.001")!, .milligram),
            ("mg", 1, .milligram),
            ("g", 1, .gram)
        ]
        for (suffix, factor, unit) in unitPatterns {
            guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*"# + suffix + #"\b"#) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let valueRange = Range(match.range(at: 1), in: text),
                  let value = Decimal(string: String(text[valueRange])) else { continue }
            let inUnit = value * factor
            if unit == canonicalUnit { return inUnit }
            if unit == .gram && canonicalUnit == .milligram { return inUnit * 1000 }
            if unit == .milligram && canonicalUnit == .gram { return inUnit / 1000 }
            // Dimension mismatch (e.g. grams for calories): not this pattern.
            continue
        }
        if canonicalUnit == .kilocalorie {
            // "Calories 60" / "60 calories" / "Energy 250 kcal".
            if let regex = try? NSRegularExpression(pattern: #"(?:calories|energy)\D{0,3}(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?)\s*(?:kcal|calories)"#) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, range: range) {
                    for group in 1...2 {
                        if let valueRange = Range(match.range(at: group), in: text),
                           let value = Decimal(string: String(text[valueRange])) {
                            return value
                        }
                    }
                }
            }
        }
        return nil
    }

    static func firstNumber(before suffixes: [String], in text: String) -> Decimal? {
        for suffix in suffixes {
            if let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*"# + NSRegularExpression.escapedPattern(for: suffix) + #"\b"#) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, range: range),
                   let valueRange = Range(match.range(at: 1), in: text) {
                    return Decimal(string: String(text[valueRange]))
                }
            }
        }
        return nil
    }

    static func firstNumber(in text: String) -> Decimal? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return Decimal(string: String(text[valueRange]))
    }

    /// Assemble a draft from structured document content: table rows (already
    /// joined per row) and free text lines, plus machine-readable codes.
    /// Bilingual/complex labels: rows in unsupported languages simply do not
    /// match the keyword table and stay out — nothing is invented for them.
    public static func draft(
        fromRows rows: [String],
        freeTextLines: [String],
        barcodes: [String],
        source: LabelExtractionSource
    ) -> StructuredLabelDraft {
        var nutrients: [LabelNutrientKey: ExtractedLabelValue] = [:]
        var notes: [String] = []
        var servingDescription: String?
        var servingMassG: Decimal?
        var servingVolumeML: Decimal?
        var servingsPerContainer: Decimal?

        for row in rows + freeTextLines {
            if servingsPerContainer == nil, let count = parseServingsPerContainer(row) {
                servingsPerContainer = count
                continue
            }
            if servingDescription == nil, row.lowercased().contains("serving size"),
               let serving = parseServingSizeRow(row) {
                servingDescription = serving.description
                servingMassG = serving.massG
                servingVolumeML = serving.volumeML
                continue
            }
            if let parsed = parseNutrientRow(row) {
                if let existing = nutrients[parsed.key], existing.amount != parsed.value.amount {
                    // Same nutrient read twice with different values: keep the
                    // conflict visible instead of picking one (DEVICE-007).
                    var conflicted = existing
                    conflicted.conflicting = true
                    conflicted.sourceText = "\(existing.sourceText) / \(parsed.value.sourceText)"
                    nutrients[parsed.key] = conflicted
                    notes.append("\(parsed.key.displayName) appears more than once with different values")
                } else if nutrients[parsed.key] == nil {
                    nutrients[parsed.key] = parsed.value
                }
            }
        }

        return StructuredLabelDraft(
            servingsPerContainer: servingsPerContainer,
            servingDescription: servingDescription,
            servingMassG: servingMassG,
            servingVolumeML: servingVolumeML,
            columns: [LabelColumn(basis: .perServing, nutrients: nutrients)],
            barcodes: barcodes,
            extractionSource: source,
            extractionNotes: notes
        )
    }
}
