import Foundation

/// Versioned recipe (FOOD-015): ingredients with source versions, explicit
/// loss assumptions, finished edible batch mass, and portion definitions.
public struct RecipeVersion: Codable, Hashable, Sendable, Identifiable {
    public struct Ingredient: Codable, Hashable, Sendable {
        public var food: FoodVersion
        public var portion: PortionRequest
        public init(food: FoodVersion, portion: PortionRequest) {
            self.food = food
            self.portion = portion
        }
    }

    public var recipeID: String
    public var versionID: String
    public var name: String
    public var ingredients: [Ingredient]
    /// Finished edible batch mass in grams after cooking. Water loss changes
    /// mass and density but not the batch's calories (FOOD-016, REG-030).
    public var finishedBatchMassG: Decimal
    /// Equal-portion count when the user chose that assumption (FOOD-017).
    public var equalPortionCount: Int?
    /// Documented loss assumptions, e.g. "oil drained after frying: -10 g fat".
    public var lossAssumptions: [String]

    public var id: String { "\(recipeID)#\(versionID)" }

    public init(
        recipeID: String,
        versionID: String,
        name: String,
        ingredients: [Ingredient],
        finishedBatchMassG: Decimal,
        equalPortionCount: Int? = nil,
        lossAssumptions: [String] = []
    ) {
        self.recipeID = recipeID
        self.versionID = versionID
        self.name = name
        self.ingredients = ingredients
        self.finishedBatchMassG = finishedBatchMassG
        self.equalPortionCount = equalPortionCount
        self.lossAssumptions = lossAssumptions
    }
}

public enum RecipeError: Error, Equatable, Sendable {
    case invalidBatchMass
    case portionCountUndefined
    case invalidPortion
    case ingredientScalingFailed
}

public enum RecipeEngine {

    /// Total batch nutrients from ingredients. Unknown ingredient nutrients
    /// keep the batch total's coverage partial.
    public static func batchNutrients(recipe: RecipeVersion, nutrientIDs: [NutrientID]) throws -> [NutrientID: (total: Decimal, coverage: AggregatedMetricValue.Coverage)] {
        var parts: [ScaledNutrients] = []
        for ingredient in recipe.ingredients {
            guard let scaled = try? PortionEngine.scale(food: ingredient.food, portion: ingredient.portion) else {
                throw RecipeError.ingredientScalingFailed
            }
            parts.append(scaled)
        }
        return PortionEngine.sum(parts, nutrientIDs: nutrientIDs)
    }

    /// Nutrients for a weighed cooked portion: batch total x portionMass /
    /// finishedBatchMass (FOOD-017). REG-030: a 1,200 kcal batch with 1,000 g
    /// cooked yield gives 240 kcal for 200 g eaten.
    public static func weighedPortionNutrients(
        recipe: RecipeVersion,
        portionMassG: Decimal,
        nutrientIDs: [NutrientID]
    ) throws -> [NutrientID: (total: Decimal, coverage: AggregatedMetricValue.Coverage)] {
        guard recipe.finishedBatchMassG > 0 else { throw RecipeError.invalidBatchMass }
        guard portionMassG > 0 else { throw RecipeError.invalidPortion }
        let batch = try batchNutrients(recipe: recipe, nutrientIDs: nutrientIDs)
        let factor = portionMassG / recipe.finishedBatchMassG
        return batch.mapValues { (total: $0.total * factor, coverage: $0.coverage) }
    }

    /// Nutrients for N equal count-portions; requires the explicit equal-portion
    /// assumption (FOOD-017). Acceptance: a synthetic 1,200 kcal batch divided
    /// into 12 equal portions logs 300 kcal for three portions.
    public static func countPortionNutrients(
        recipe: RecipeVersion,
        portionsEaten: Decimal,
        nutrientIDs: [NutrientID]
    ) throws -> [NutrientID: (total: Decimal, coverage: AggregatedMetricValue.Coverage)] {
        guard let count = recipe.equalPortionCount, count > 0 else { throw RecipeError.portionCountUndefined }
        guard portionsEaten > 0 else { throw RecipeError.invalidPortion }
        let batch = try batchNutrients(recipe: recipe, nutrientIDs: nutrientIDs)
        let factor = portionsEaten / Decimal(count)
        return batch.mapValues { (total: $0.total * factor, coverage: $0.coverage) }
    }
}
