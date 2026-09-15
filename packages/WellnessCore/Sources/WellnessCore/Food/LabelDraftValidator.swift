import Foundation

/// Deterministic validation of a structured label draft (DEVICE-007).
/// Whatever produced the draft — Vision, a generative model, or typing — these
/// checks and the user's explicit confirmation stand between the draft and a
/// committed food. Valid JSON from a model is never sufficient.

public enum LabelIssueSeverity: String, Codable, Sendable {
    /// Field cannot be accepted as-is; it is dropped to unknown unless corrected.
    case blocking
    /// Field is plausible but should be reviewed; shown highlighted, kept.
    case review
}

public struct LabelValidationIssue: Codable, Hashable, Sendable, Identifiable {
    public var field: String
    public var severity: LabelIssueSeverity
    public var message: String

    public var id: String { "\(field)|\(message)" }

    public init(field: String, severity: LabelIssueSeverity, message: String) {
        self.field = field
        self.severity = severity
        self.message = message
    }
}

public enum LabelDraftError: Error, Equatable, Sendable {
    /// The image did not contain anything recognizable as a nutrition panel.
    case notANutritionLabel
    /// The selected column does not exist in the draft.
    case columnNotFound
    /// Nothing committable remained after validation.
    case noAcceptedValues
    /// Committing requires a name.
    case missingName
}

/// The outcome of validating one selected column: accepted values, per-field
/// issues, and what was dropped to unknown.
public struct ValidatedLabelColumn: Sendable, Equatable {
    public var basis: LabelColumnBasis
    /// Accepted absolute amounts in canonical units. A field with only a %DV
    /// reading is NOT here — %DV never substitutes for an absolute amount.
    public var accepted: [LabelNutrientKey: Decimal]
    /// Fields the label declared but validation dropped to unknown, with reason.
    public var droppedToUnknown: [LabelNutrientKey: String]
    public var issues: [LabelValidationIssue]

    public var hasBlockingIssues: Bool {
        issues.contains { $0.severity == .blocking }
    }
}

public enum LabelDraftValidator {

    /// Validate one column of the draft. Pure and total: never throws for
    /// bad values — it reports them so the review screen can highlight and
    /// the user can correct before commit.
    public static func validate(draft: StructuredLabelDraft, basis: LabelColumnBasis) throws -> ValidatedLabelColumn {
        guard draft.looksLikeNutritionLabel else { throw LabelDraftError.notANutritionLabel }
        guard let column = draft.columns.first(where: { $0.basis == basis }) else {
            throw LabelDraftError.columnNotFound
        }

        var accepted: [LabelNutrientKey: Decimal] = [:]
        var dropped: [LabelNutrientKey: String] = [:]
        var issues: [LabelValidationIssue] = []

        for (key, value) in column.nutrients {
            guard let amount = value.amount else {
                if value.dailyValuePercent != nil {
                    // %DV present without an absolute amount: stays unknown.
                    dropped[key] = "Only %DV was read; the absolute amount is unknown"
                    issues.append(LabelValidationIssue(
                        field: key.rawValue, severity: .review,
                        message: "\(key.displayName): only a %DV was read — enter the \(key.canonicalUnit.rawValue) amount from the label or leave it unknown"
                    ))
                }
                continue
            }
            if value.conflicting {
                dropped[key] = "Conflicting readings"
                issues.append(LabelValidationIssue(
                    field: key.rawValue, severity: .blocking,
                    message: "\(key.displayName): conflicting readings — confirm the printed value"
                ))
                continue
            }
            if amount < 0 {
                dropped[key] = "Negative amount"
                issues.append(LabelValidationIssue(
                    field: key.rawValue, severity: .blocking,
                    message: "\(key.displayName): negative amounts are impossible"
                ))
                continue
            }
            if amount > key.plausibleMaximumPerBasis {
                dropped[key] = "Implausibly large amount"
                issues.append(LabelValidationIssue(
                    field: key.rawValue, severity: .blocking,
                    message: "\(key.displayName): \(amount) \(key.canonicalUnit.rawValue) is implausible for one basis — check the reading"
                ))
                continue
            }
            if value.confidence == .low {
                issues.append(LabelValidationIssue(
                    field: key.rawValue, severity: .review,
                    message: "\(key.displayName): low-confidence reading — verify against the image"
                ))
            }
            accepted[key] = amount
        }

        issues.append(contentsOf: crossFieldChecks(accepted: accepted))
        issues.append(contentsOf: servingChecks(draft: draft))

        return ValidatedLabelColumn(basis: basis, accepted: accepted, droppedToUnknown: dropped, issues: issues)
    }

    /// Component-arithmetic checks. Labels legitimately round, so violations
    /// are review flags, never silent rewrites of the printed values
    /// (FOOD-009 applies the same rule to calories).
    static func crossFieldChecks(accepted: [LabelNutrientKey: Decimal]) -> [LabelValidationIssue] {
        var issues: [LabelValidationIssue] = []
        let roundingSlack: Decimal = 1   // grams of printed-rounding tolerance

        func flagIfExceeds(_ part: LabelNutrientKey, _ whole: LabelNutrientKey) {
            if let partValue = accepted[part], let wholeValue = accepted[whole], partValue > wholeValue + roundingSlack {
                issues.append(LabelValidationIssue(
                    field: part.rawValue, severity: .review,
                    message: "\(part.displayName) (\(partValue) g) exceeds \(whole.displayName.lowercased()) (\(wholeValue) g) — check both readings"
                ))
            }
        }
        flagIfExceeds(.saturatedFat, .totalFat)
        flagIfExceeds(.transFat, .totalFat)
        flagIfExceeds(.dietaryFiber, .totalCarbohydrate)
        flagIfExceeds(.totalSugars, .totalCarbohydrate)
        flagIfExceeds(.addedSugars, .totalSugars)

        // 4/4/9 comparison: a large disagreement flags a possible misreading;
        // the printed calories remain authoritative either way (FOOD-009).
        if let calories = accepted[.calories] {
            let protein = accepted[.protein] ?? 0
            let carbs = accepted[.totalCarbohydrate] ?? 0
            let fat = accepted[.totalFat] ?? 0
            if accepted[.protein] != nil || accepted[.totalCarbohydrate] != nil || accepted[.totalFat] != nil {
                let estimate = 4 * protein + 4 * carbs + 9 * fat
                let slack = max(Decimal(30), estimate / 2)
                if calories > estimate + slack || (estimate > 0 && calories + slack < estimate) {
                    issues.append(LabelValidationIssue(
                        field: LabelNutrientKey.calories.rawValue, severity: .review,
                        message: "Calories (\(calories)) differ a lot from the 4/4/9 macro estimate (\(estimate)) — check for a misread digit. Label rounding can explain small gaps."
                    ))
                }
            }
        }
        return issues
    }

    static func servingChecks(draft: StructuredLabelDraft) -> [LabelValidationIssue] {
        var issues: [LabelValidationIssue] = []
        if let mass = draft.servingMassG, mass <= 0 || mass > 5000 {
            issues.append(LabelValidationIssue(
                field: "servingMassG", severity: .blocking,
                message: "Serving mass \(mass) g is outside the plausible range"
            ))
        }
        if let volume = draft.servingVolumeML, volume <= 0 || volume > 5000 {
            issues.append(LabelValidationIssue(
                field: "servingVolumeML", severity: .blocking,
                message: "Serving volume \(volume) mL is outside the plausible range"
            ))
        }
        if let servings = draft.servingsPerContainer, servings <= 0 || servings > 1000 {
            issues.append(LabelValidationIssue(
                field: "servingsPerContainer", severity: .blocking,
                message: "Servings per container \(servings) is outside the plausible range"
            ))
        }
        if draft.servingMassG == nil && draft.servingVolumeML == nil {
            issues.append(LabelValidationIssue(
                field: "servingBasis", severity: .review,
                message: "No serving mass or volume was read; exact-weight portions will be unavailable until one is entered (FOOD-005)"
            ))
        }
        return issues
    }

    /// Build the committable food from a validated, user-confirmed column.
    /// Called only after the review screen's explicit confirmation. The result
    /// snapshots the accepted facts as a new immutable version (FOOD-001):
    /// creating or updating a food never rewrites earlier diary snapshots, and
    /// a scan can never silently overwrite a verified catalog food — an update
    /// is a new versionID on the user's own food.
    public static func foodVersion(
        from validated: ValidatedLabelColumn,
        draft: StructuredLabelDraft,
        name: String,
        market: String,
        existingFoodID: String?,
        newVersionID: String,
        createdAt: Date
    ) throws -> FoodVersion {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        guard !cleanName.isEmpty else { throw LabelDraftError.missingName }
        guard !validated.accepted.isEmpty else {
            throw LabelDraftError.noAcceptedValues
        }

        var nutrients: [NutrientID: NutrientValue] = [:]
        for (key, amount) in validated.accepted {
            nutrients[key.nutrientID] = amount == 0 ? .knownZero : .known(amount)
        }
        for (key, reason) in validated.droppedToUnknown where nutrients[key.nutrientID] == nil {
            nutrients[key.nutrientID] = .unknown(reason: reason)
        }
        // Declared micronutrients with absolute amounts ride along verbatim;
        // %DV-only rows stay out (never converted to amounts).
        if let column = draft.columns.first(where: { $0.basis == validated.basis }) {
            for micro in column.micronutrients {
                guard let amount = micro.amount, amount >= 0, let unitText = micro.unitText else { continue }
                let slug = micro.name.lowercased()
                    .replacingOccurrences(of: " ", with: "_")
                    .filter { $0.isLetter || $0 == "_" }
                guard !slug.isEmpty else { continue }
                nutrients[NutrientID("micro_\(slug)_\(unitText)")] = amount == 0 ? .knownZero : .known(amount)
            }
        }

        var identifiers: [String: String] = [:]
        if let barcode = draft.barcodes.compactMap({ Barcode.validatedGTIN($0) }).first {
            identifiers["gtin"] = barcode
        }

        return FoodVersion(
            foodID: existingFoodID ?? "user-label-\(UUID().uuidString.prefix(8))",
            versionID: newVersionID,
            canonicalName: cleanName,
            marketCountry: market,
            identifiers: identifiers,
            basis: .namedServing(
                name: draft.servingDescription ?? validated.basis.displayName,
                massG: draft.servingMassG,
                volumeML: draft.servingVolumeML
            ),
            nutrients: nutrients,
            evidence: SourceEvidence(
                sourceID: "user-label-capture",
                sourceLocator: "Label capture (\(draft.extractionSource.rawValue), basis: \(validated.basis.displayName)) reviewed and confirmed by user",
                retrievedAt: createdAt,
                evidenceType: .userEnteredLabel
            )
        )
    }
}
