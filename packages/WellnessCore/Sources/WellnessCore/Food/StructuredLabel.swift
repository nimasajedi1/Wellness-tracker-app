import Foundation

/// App-owned structured nutrition-label schema (DEVICE-007). Any producer —
/// the iOS 27 Vision document reader, the optional Foundation Models
/// interpreter, or the DEVICE-002 line parser — maps INTO this schema, and
/// only `LabelDraftValidator` plus explicit user confirmation can turn it
/// into a food. Missing, unreadable, conflicting, or unsupported fields stay
/// unknown; they are never inferred merely to complete the schema.

/// The nutrients a Nutrition Facts panel declares (DEVICE-007 field list).
public enum LabelNutrientKey: String, Codable, Sendable, CaseIterable, Hashable {
    case calories
    case totalFat
    case saturatedFat
    case transFat
    case cholesterol
    case sodium
    case totalCarbohydrate
    case dietaryFiber
    case totalSugars
    case addedSugars
    case protein

    /// Canonical unit for the absolute amount.
    public var canonicalUnit: UnitOfMeasure {
        switch self {
        case .calories: return .kilocalorie
        case .cholesterol, .sodium: return .milligram
        default: return .gram
        }
    }

    /// Catalog nutrient ID for the app's food records.
    public var nutrientID: NutrientID {
        switch self {
        case .calories: return .energyKcal
        case .totalFat: return .fatG
        case .saturatedFat: return .saturatedFatG
        case .transFat: return NutrientID("trans_fat_g")
        case .cholesterol: return NutrientID("cholesterol_mg")
        case .sodium: return .sodiumMg
        case .totalCarbohydrate: return .carbohydrateG
        case .dietaryFiber: return .fiberG
        case .totalSugars: return NutrientID("total_sugars_g")
        case .addedSugars: return .addedSugarG
        case .protein: return .proteinG
        }
    }

    public var displayName: String {
        switch self {
        case .calories: return "Calories"
        case .totalFat: return "Total fat"
        case .saturatedFat: return "Saturated fat"
        case .transFat: return "Trans fat"
        case .cholesterol: return "Cholesterol"
        case .sodium: return "Sodium"
        case .totalCarbohydrate: return "Total carbohydrate"
        case .dietaryFiber: return "Dietary fiber"
        case .totalSugars: return "Total sugars"
        case .addedSugars: return "Added sugars"
        case .protein: return "Protein"
        }
    }

    /// Loose per-serving sanity ceiling in the canonical unit, used only to
    /// reject impossible extractions (e.g. OCR reading 8000 g of protein).
    /// These are data-plausibility bounds, not health thresholds (SAFE-004).
    var plausibleMaximumPerBasis: Decimal {
        switch self {
        case .calories: return 5000
        case .cholesterol: return 3000     // mg
        case .sodium: return 10000         // mg
        default: return 500                // g
        }
    }
}

public enum ExtractionConfidence: String, Codable, Sendable, Comparable {
    case low, medium, high

    var rank: Int {
        switch self { case .low: return 0; case .medium: return 1; case .high: return 2 }
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// One extracted field: the normalized reading plus the evidence needed to
/// show the user what was read (DEVICE-007). An absolute amount and a %DV are
/// carried separately — %DV is never substituted for grams/milligrams.
public struct ExtractedLabelValue: Codable, Hashable, Sendable {
    /// Absolute amount in the key's canonical unit; nil = not read.
    public var amount: Decimal?
    /// Declared %DV when printed; informational only.
    public var dailyValuePercent: Decimal?
    /// Verbatim source text this reading came from.
    public var sourceText: String
    public var confidence: ExtractionConfidence
    /// True when the producer saw conflicting readings for this field.
    public var conflicting: Bool

    public init(
        amount: Decimal?,
        dailyValuePercent: Decimal? = nil,
        sourceText: String,
        confidence: ExtractionConfidence = .medium,
        conflicting: Bool = false
    ) {
        self.amount = amount
        self.dailyValuePercent = dailyValuePercent
        self.sourceText = sourceText
        self.confidence = confidence
        self.conflicting = conflicting
    }
}

/// A declared vitamin/mineral row (name kept verbatim; unit as printed).
public struct ExtractedMicronutrient: Codable, Hashable, Sendable {
    public var name: String
    public var amount: Decimal?
    public var unitText: String?
    public var dailyValuePercent: Decimal?
    public var sourceText: String
    public var confidence: ExtractionConfidence

    public init(name: String, amount: Decimal?, unitText: String?, dailyValuePercent: Decimal?, sourceText: String, confidence: ExtractionConfidence = .medium) {
        self.name = name
        self.amount = amount
        self.unitText = unitText
        self.dailyValuePercent = dailyValuePercent
        self.sourceText = sourceText
        self.confidence = confidence
    }
}

/// The basis a nutrition column is declared for. Columns stay distinct until
/// the user selects the intended basis (DEVICE-007).
public enum LabelColumnBasis: Codable, Hashable, Sendable {
    case perServing
    case perContainer
    case prepared
    case unprepared
    case per100g
    case per100mL
    case other(String)

    public var displayName: String {
        switch self {
        case .perServing: return "Per serving"
        case .perContainer: return "Per container"
        case .prepared: return "Prepared"
        case .unprepared: return "Unprepared"
        case .per100g: return "Per 100 g"
        case .per100mL: return "Per 100 mL"
        case .other(let name): return name
        }
    }
}

public struct LabelColumn: Codable, Hashable, Sendable, Identifiable {
    public var basis: LabelColumnBasis
    public var nutrients: [LabelNutrientKey: ExtractedLabelValue]
    public var micronutrients: [ExtractedMicronutrient]

    public var id: String { basis.displayName }

    public init(basis: LabelColumnBasis, nutrients: [LabelNutrientKey: ExtractedLabelValue] = [:], micronutrients: [ExtractedMicronutrient] = []) {
        self.basis = basis
        self.nutrients = nutrients
        self.micronutrients = micronutrients
    }
}

public enum LabelExtractionSource: String, Codable, Sendable {
    /// Vision RecognizeDocumentsRequest structured extraction (iOS 27 path).
    case visionDocument
    /// Foundation Models image interpretation over the Vision result (MAY path).
    case foundationModelInterpretation
    /// DEVICE-002 recognized-lines parser.
    case lineParser
    /// Values typed by the user in review.
    case manualEntry
}

/// The reviewable draft (DEVICE-007). Everything is optional; the validator
/// decides what is committable and the user confirms every value.
public struct StructuredLabelDraft: Codable, Hashable, Sendable {
    public var productName: String?
    public var servingsPerContainer: Decimal?
    public var servingDescription: String?
    public var servingMassG: Decimal?
    public var servingVolumeML: Decimal?
    public var columns: [LabelColumn]
    public var barcodes: [String]
    public var extractionSource: LabelExtractionSource
    /// Producer notes shown in review (e.g. "second column header unreadable").
    public var extractionNotes: [String]

    public init(
        productName: String? = nil,
        servingsPerContainer: Decimal? = nil,
        servingDescription: String? = nil,
        servingMassG: Decimal? = nil,
        servingVolumeML: Decimal? = nil,
        columns: [LabelColumn] = [],
        barcodes: [String] = [],
        extractionSource: LabelExtractionSource,
        extractionNotes: [String] = []
    ) {
        self.productName = productName
        self.servingsPerContainer = servingsPerContainer
        self.servingDescription = servingDescription
        self.servingMassG = servingMassG
        self.servingVolumeML = servingVolumeML
        self.columns = columns
        self.barcodes = barcodes
        self.extractionSource = extractionSource
        self.extractionNotes = extractionNotes
    }

    /// True when nothing on the image looked like a nutrition panel: no
    /// recognized nutrient rows in any column. Such an image is reported as
    /// not-a-label instead of producing an empty "food".
    public var looksLikeNutritionLabel: Bool {
        columns.contains { column in
            column.nutrients.values.contains { $0.amount != nil || $0.dailyValuePercent != nil }
        }
    }

    /// Bridge from the DEVICE-002 line-parser candidate so both capture paths
    /// share one review and validation pipeline.
    public static func from(candidate: ParsedLabelCandidate, source: LabelExtractionSource = .lineParser) -> StructuredLabelDraft {
        var nutrients: [LabelNutrientKey: ExtractedLabelValue] = [:]
        func put(_ key: LabelNutrientKey, _ field: ParsedLabelField?) {
            guard let field else { return }
            nutrients[key] = ExtractedLabelValue(amount: Decimal(field.value), sourceText: field.sourceText)
        }
        put(.calories, candidate.energyKcal)
        put(.protein, candidate.proteinG)
        put(.dietaryFiber, candidate.fiberG)
        put(.totalCarbohydrate, candidate.carbohydrateG)
        put(.totalFat, candidate.fatG)
        put(.sodium, candidate.sodiumMg)
        return StructuredLabelDraft(
            servingDescription: candidate.servingName,
            servingMassG: candidate.servingMassG.map { Decimal($0.value) },
            columns: [LabelColumn(basis: .perServing, nutrients: nutrients)],
            extractionSource: source
        )
    }
}
