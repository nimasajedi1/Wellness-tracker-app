import Foundation

/// Nutrient identity keys. Numeric IDs from source datasets are mapped to these
/// stable keys at ingestion; new nutrients do not require schema migrations.
public struct NutrientID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let energyKcal: NutrientID = "energy_kcal"
    public static let proteinG: NutrientID = "protein_g"
    public static let fiberG: NutrientID = "fiber_g"
    public static let carbohydrateG: NutrientID = "carbohydrate_g"
    public static let fatG: NutrientID = "fat_g"
    public static let saturatedFatG: NutrientID = "saturated_fat_g"
    public static let sodiumMg: NutrientID = "sodium_mg"
    public static let addedSugarG: NutrientID = "added_sugar_g"
    public static let caffeineMg: NutrientID = "caffeine_mg"
}

/// A nutrient amount whose absence is explicit: unknown is never zero (FOOD-002).
public enum NutrientValue: Codable, Hashable, Sendable {
    case known(Decimal)
    case knownZero
    case unknown(reason: String)

    public var decimalValue: Decimal? {
        switch self {
        case .known(let value): return value
        case .knownZero: return 0
        case .unknown: return nil
        }
    }

    public var isKnown: Bool { decimalValue != nil }
}

/// Evidence classes (FOOD-003). A label is evidence of reported composition,
/// not a laboratory measurement of the user's serving (SAFE-002).
public enum EvidenceType: String, Codable, Sendable {
    case officialSource       // manufacturer/restaurant published document
    case usdaReference
    case brandedLabelRecord
    case userEnteredLabel
    case recipeCalculated
    case estimate
    case syntheticFixture     // test data; excluded from production search
}

public enum ServingBasis: Codable, Hashable, Sendable {
    case per100g
    case per100mL
    /// A named label serving, e.g. "1 slice (56 g)". Mass/volume mapping is
    /// stored only when the source states it.
    case namedServing(name: String, massG: Decimal?, volumeML: Decimal?)

    /// Reference mass in grams for scaling, when known.
    public var referenceMassG: Decimal? {
        switch self {
        case .per100g: return 100
        case .per100mL: return nil
        case .namedServing(_, let massG, _): return massG
        }
    }

    public var referenceVolumeML: Decimal? {
        switch self {
        case .per100g: return nil
        case .per100mL: return 100
        case .namedServing(_, _, let volumeML): return volumeML
        }
    }
}

public struct SourceEvidence: Codable, Hashable, Sendable {
    public var sourceID: String
    public var sourceURL: String?
    public var sourceLocator: String?
    public var sourcePublishedAt: Date?
    public var retrievedAt: Date?
    public var contentHash: String?
    public var parserVersion: String?
    public var licensePolicy: String?
    public var evidenceType: EvidenceType

    public init(
        sourceID: String,
        sourceURL: String? = nil,
        sourceLocator: String? = nil,
        sourcePublishedAt: Date? = nil,
        retrievedAt: Date? = nil,
        contentHash: String? = nil,
        parserVersion: String? = nil,
        licensePolicy: String? = nil,
        evidenceType: EvidenceType
    ) {
        self.sourceID = sourceID
        self.sourceURL = sourceURL
        self.sourceLocator = sourceLocator
        self.sourcePublishedAt = sourcePublishedAt
        self.retrievedAt = retrievedAt
        self.contentHash = contentHash
        self.parserVersion = parserVersion
        self.licensePolicy = licensePolicy
        self.evidenceType = evidenceType
    }
}

public enum FoodAvailability: String, Codable, Sendable {
    case available, discontinued, unknown
}

/// Versioned, source-backed food record (section 10.1). A logged food snapshots
/// its version; catalog updates never rewrite committed meals (FOOD-001, REG-051).
public struct FoodVersion: Codable, Hashable, Sendable, Identifiable {
    public var foodID: String
    public var versionID: String
    public var canonicalName: String
    public var brand: String?
    public var restaurant: String?
    public var marketCountry: String
    public var language: String
    /// raw/cooked/drained and similar identity modifiers (FOOD-004).
    public var preparation: String?
    public var variant: String?
    public var packageSize: String?
    public var identifiers: [String: String]   // fdcID, gtin, sku, restaurantItemID
    public var basis: ServingBasis
    public var nutrients: [NutrientID: NutrientValue]
    public var evidence: SourceEvidence
    public var availability: FoodAvailability

    public var id: String { "\(foodID)#\(versionID)" }

    public init(
        foodID: String,
        versionID: String,
        canonicalName: String,
        brand: String? = nil,
        restaurant: String? = nil,
        marketCountry: String = "US",
        language: String = "en",
        preparation: String? = nil,
        variant: String? = nil,
        packageSize: String? = nil,
        identifiers: [String: String] = [:],
        basis: ServingBasis,
        nutrients: [NutrientID: NutrientValue],
        evidence: SourceEvidence,
        availability: FoodAvailability = .unknown
    ) {
        self.foodID = foodID
        self.versionID = versionID
        self.canonicalName = canonicalName
        self.brand = brand
        self.restaurant = restaurant
        self.marketCountry = marketCountry
        self.language = language
        self.preparation = preparation
        self.variant = variant
        self.packageSize = packageSize
        self.identifiers = identifiers
        self.basis = basis
        self.nutrients = nutrients
        self.evidence = evidence
        self.availability = availability
    }
}

/// Private alias pointing to a canonical identity, never to a remembered
/// nutrient number in conversation text (FOOD-012).
public struct FoodAlias: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var alias: String
    public var foodID: String
    public var preferredVersionID: String?
    public var market: String
    public var defaultPortion: PortionRequest?

    public init(id: UUID = UUID(), alias: String, foodID: String, preferredVersionID: String? = nil, market: String = "US", defaultPortion: PortionRequest? = nil) {
        self.id = id
        self.alias = alias
        self.foodID = foodID
        self.preferredVersionID = preferredVersionID
        self.market = market
        self.defaultPortion = defaultPortion
    }
}
