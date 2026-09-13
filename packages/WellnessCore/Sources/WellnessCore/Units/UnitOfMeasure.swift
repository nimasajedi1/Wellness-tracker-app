import Foundation

/// Canonical measurement units supported by the portion and observation engines (FOOD-005).
/// Mass ounces and US fluid ounces are distinct units; household volume measures require
/// an explicit food-specific mass mapping before they can convert to grams (FOOD-006).
public enum UnitOfMeasure: String, Codable, Sendable, CaseIterable, Hashable {
    // Mass
    case gram = "g"
    case kilogram = "kg"
    case ounceMass = "oz"
    case pound = "lb"
    // Volume
    case milliliter = "mL"
    case liter = "L"
    case fluidOunceUS = "flozUS"
    case cupUS = "cupUS"
    case tablespoonUS = "tbspUS"
    case teaspoonUS = "tspUS"
    // Energy
    case kilocalorie = "kcal"
    case kilojoule = "kJ"
    // Time
    case minute = "min"
    case hour = "h"
    // Discrete
    case count = "count"
    case namedServing = "serving"
    case package = "package"
    case recipePortion = "recipePortion"
    // Other quantities
    case milligram = "mg"
    case microgram = "mcg"
    case step = "step"

    public enum Dimension: String, Codable, Sendable {
        case mass, volume, energy, time, discrete
    }

    public var dimension: Dimension {
        switch self {
        case .gram, .kilogram, .ounceMass, .pound, .milligram, .microgram:
            return .mass
        case .milliliter, .liter, .fluidOunceUS, .cupUS, .tablespoonUS, .teaspoonUS:
            return .volume
        case .kilocalorie, .kilojoule:
            return .energy
        case .minute, .hour:
            return .time
        case .count, .namedServing, .package, .recipePortion, .step:
            return .discrete
        }
    }

    /// Exact conversion factor to the dimension's canonical unit
    /// (grams, milliliters, kilocalories, minutes). Discrete units have no
    /// cross-unit conversion; they return nil except for identity.
    public var factorToCanonical: Decimal? {
        switch self {
        case .gram: return 1
        case .kilogram: return 1000
        // International avoirdupois ounce, exact by definition (REG-026).
        case .ounceMass: return Decimal(string: "28.349523125")!
        case .pound: return Decimal(string: "453.59237")!
        case .milligram: return Decimal(string: "0.001")!
        case .microgram: return Decimal(string: "0.000001")!
        case .milliliter: return 1
        case .liter: return 1000
        case .fluidOunceUS: return Decimal(string: "29.5735295625")!
        case .cupUS: return Decimal(string: "236.5882365")!
        case .tablespoonUS: return Decimal(string: "14.78676478125")!
        case .teaspoonUS: return Decimal(string: "4.92892159375")!
        case .kilocalorie: return 1
        // Thermochemical: 1 kcal = 4.184 kJ. Conversions are labeled (FOOD-009).
        case .kilojoule: return Decimal(1) / Decimal(string: "4.184")!
        case .minute: return 1
        case .hour: return 60
        case .count, .namedServing, .package, .recipePortion, .step:
            return nil
        }
    }
}

public enum UnitConversionError: Error, Equatable, Sendable {
    case incompatibleDimensions(from: UnitOfMeasure, to: UnitOfMeasure)
    case discreteUnitNeedsMapping(UnitOfMeasure)
    case volumeToMassNeedsDensity
}

public enum UnitConverter {
    /// Convert within one dimension using exact decimal factors.
    /// Cross-dimension conversion (volume→mass) is rejected here; it needs an
    /// evidenced density or portion mapping supplied by the caller (FOOD-006).
    public static func convert(_ value: Decimal, from: UnitOfMeasure, to: UnitOfMeasure) throws -> Decimal {
        if from == to { return value }
        guard from.dimension == to.dimension else {
            if from.dimension == .volume && to.dimension == .mass {
                throw UnitConversionError.volumeToMassNeedsDensity
            }
            throw UnitConversionError.incompatibleDimensions(from: from, to: to)
        }
        guard let fromFactor = from.factorToCanonical, let toFactor = to.factorToCanonical else {
            throw UnitConversionError.discreteUnitNeedsMapping(from.factorToCanonical == nil ? from : to)
        }
        return value * fromFactor / toFactor
    }
}
