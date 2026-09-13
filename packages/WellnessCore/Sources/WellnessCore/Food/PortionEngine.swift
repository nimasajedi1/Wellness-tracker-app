import Foundation

/// A requested portion of a food. Decimal quantities are preserved end to end
/// (FOOD-007); rounding happens only at display time.
public struct PortionRequest: Codable, Hashable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        /// An exact mass, e.g. "112 g" or "4 oz by weight".
        case mass(Decimal, UnitOfMeasure)
        /// An exact volume; requires the record to have a volume basis or an
        /// evidenced density mapping.
        case volume(Decimal, UnitOfMeasure)
        /// N label servings: uses exactly N x the reported serving nutrients
        /// (FOOD-008), independent of the label's approximate gram note.
        case servings(Decimal)
        /// A count of items with an explicit per-item mass, e.g. "two 100 g kotlets".
        case countWithUnitMass(count: Decimal, perItemMassG: Decimal)
    }
    public var kind: Kind
    public init(_ kind: Kind) { self.kind = kind }
}

public enum PortionError: Error, Equatable, Sendable {
    case massBasisUnavailable          // record has no gram mapping for its serving
    case volumeBasisUnavailable
    case volumeToMassNeedsDensity      // FOOD-006: no evidenced density mapping
    case incompatibleUnits
    case nonPositiveQuantity
}

/// Scaled nutrient outcome. Unknown nutrients stay unknown; totals must report
/// coverage rather than silently treating gaps as zero (FOOD-002, REG-029).
public struct ScaledNutrients: Sendable, Equatable {
    public var values: [NutrientID: NutrientValue]
    /// Multiplier applied to the record's basis.
    public var scaleFactor: Decimal
    /// Resolved mass in grams when derivable.
    public var resolvedMassG: Decimal?

    public func value(_ id: NutrientID) -> NutrientValue {
        values[id] ?? .unknown(reason: "Not reported by source")
    }
}

public enum PortionEngine {

    /// Scale a food version's nutrients to the requested portion.
    /// Nutrients scale by requestedBasis / sourceBasis (FOOD-006) using decimal
    /// arithmetic; reported kcal remain authoritative (FOOD-009).
    public static func scale(food: FoodVersion, portion: PortionRequest) throws -> ScaledNutrients {
        let factor: Decimal
        var resolvedMassG: Decimal? = nil

        switch portion.kind {
        case .servings(let n):
            guard n > 0 else { throw PortionError.nonPositiveQuantity }
            switch food.basis {
            case .namedServing(_, let massG, _):
                factor = n
                if let massG { resolvedMassG = n * massG }
            case .per100g, .per100mL:
                // "A serving" is undefined for a per-100 record.
                throw PortionError.massBasisUnavailable
            }
        case .mass(let amount, let unit):
            guard amount > 0 else { throw PortionError.nonPositiveQuantity }
            guard unit.dimension == .mass else { throw PortionError.incompatibleUnits }
            let grams = try UnitConverter.convert(amount, from: unit, to: .gram)
            guard let basisMass = food.basis.referenceMassG, basisMass > 0 else {
                throw PortionError.massBasisUnavailable
            }
            factor = grams / basisMass
            resolvedMassG = grams
        case .volume(let amount, let unit):
            guard amount > 0 else { throw PortionError.nonPositiveQuantity }
            guard unit.dimension == .volume else { throw PortionError.incompatibleUnits }
            let milliliters = try UnitConverter.convert(amount, from: unit, to: .milliliter)
            guard let basisVolume = food.basis.referenceVolumeML, basisVolume > 0 else {
                // Converting volume to a mass basis needs an evidenced density.
                throw PortionError.volumeToMassNeedsDensity
            }
            factor = milliliters / basisVolume
        case .countWithUnitMass(let count, let perItemMassG):
            guard count > 0, perItemMassG > 0 else { throw PortionError.nonPositiveQuantity }
            let grams = count * perItemMassG
            guard let basisMass = food.basis.referenceMassG, basisMass > 0 else {
                throw PortionError.massBasisUnavailable
            }
            factor = grams / basisMass
            resolvedMassG = grams
        }

        var scaled: [NutrientID: NutrientValue] = [:]
        for (id, value) in food.nutrients {
            switch value {
            case .known(let amount):
                scaled[id] = .known(amount * factor)
            case .knownZero:
                scaled[id] = .knownZero
            case .unknown(let reason):
                scaled[id] = .unknown(reason: reason)
            }
        }
        return ScaledNutrients(values: scaled, scaleFactor: factor, resolvedMassG: resolvedMassG)
    }

    /// Sum nutrient snapshots with explicit coverage: a missing nutrient makes
    /// that nutrient's total partial, never zero (REG-029, section 22.2).
    public static func sum(_ parts: [ScaledNutrients], nutrientIDs: [NutrientID]) -> [NutrientID: (total: Decimal, coverage: AggregatedMetricValue.Coverage)] {
        var result: [NutrientID: (Decimal, AggregatedMetricValue.Coverage)] = [:]
        for id in nutrientIDs {
            var total: Decimal = 0
            var knownCount = 0
            for part in parts {
                if let value = part.value(id).decimalValue {
                    total += value
                    knownCount += 1
                }
            }
            let coverage: AggregatedMetricValue.Coverage
            if parts.isEmpty || knownCount == 0 {
                coverage = .none
            } else if knownCount < parts.count {
                coverage = .partial
            } else {
                coverage = .complete
            }
            result[id] = (total, coverage)
        }
        return result
    }
}

public enum NutrientDisplay {
    /// Display rounding only (FOOD-007): calories to whole kcal, macros to 0.1 g.
    public static func displayString(_ value: NutrientValue, nutrientID: NutrientID) -> String {
        guard let decimal = value.decimalValue else { return "—" }
        let double = NSDecimalNumber(decimal: decimal).doubleValue
        if nutrientID == .energyKcal {
            return String(format: "%.0f", double.rounded())
        }
        return String(format: "%.1f", (double * 10).rounded() / 10)
    }
}
