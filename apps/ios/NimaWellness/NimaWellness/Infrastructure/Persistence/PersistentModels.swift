import Foundation
import SwiftData
import WellnessCore

/// SwiftData records wrap JSON-encoded domain payloads with a schema version
/// (STORE-001). The domain structs in WellnessCore stay the source of truth;
/// these records are storage envelopes with queryable index columns.
/// v2 adds the optional externalSampleID index column (HealthKit import
/// idempotence, HEALTH-003) and the user-food/alias records — additive,
/// lightweight-migratable changes.
let personalStoreSchemaVersion = 2

@Model
final class ObservationRecord {
    @Attribute(.unique) var id: UUID
    var metricID: String
    var logDay: String
    var observedAt: Date
    var isDeleted: Bool
    /// Stable ID for imported samples so reimports replace instead of add.
    var externalSampleID: String?
    var schemaVersion: Int
    var payload: Data

    init(observation: Observation) throws {
        self.id = observation.id
        self.metricID = observation.metricID.rawValue
        self.logDay = observation.logDay.isoString
        self.observedAt = observation.observedAt
        self.isDeleted = observation.isDeleted
        self.externalSampleID = observation.externalSampleID
        self.schemaVersion = personalStoreSchemaVersion
        self.payload = try JSONEncoder.domain.encode(observation)
    }

    func decoded() throws -> Observation {
        try JSONDecoder.domain.decode(Observation.self, from: payload)
    }

    func update(from observation: Observation) throws {
        metricID = observation.metricID.rawValue
        logDay = observation.logDay.isoString
        observedAt = observation.observedAt
        isDeleted = observation.isDeleted
        externalSampleID = observation.externalSampleID
        payload = try JSONEncoder.domain.encode(observation)
    }
}

/// Foods the user created from reviewed label captures (DEVICE-002). Private
/// records with userEnteredLabel evidence; never published anywhere (CAT-013).
@Model
final class UserFoodRecord {
    @Attribute(.unique) var key: String   // foodID#versionID
    var canonicalName: String
    var schemaVersion: Int
    var payload: Data

    init(food: FoodVersion) throws {
        self.key = food.id
        self.canonicalName = food.canonicalName
        self.schemaVersion = personalStoreSchemaVersion
        self.payload = try JSONEncoder.domain.encode(food)
    }

    func decoded() throws -> FoodVersion {
        try JSONDecoder.domain.decode(FoodVersion.self, from: payload)
    }
}

/// Private aliases/favorites (FOOD-012/014): identity plus optional preferred
/// portion, never a remembered nutrient number.
@Model
final class FoodAliasRecord {
    @Attribute(.unique) var id: UUID
    var alias: String
    var schemaVersion: Int
    var payload: Data

    init(alias: FoodAlias) throws {
        self.id = alias.id
        self.alias = alias.alias
        self.schemaVersion = personalStoreSchemaVersion
        self.payload = try JSONEncoder.domain.encode(alias)
    }

    func decoded() throws -> FoodAlias {
        try JSONDecoder.domain.decode(FoodAlias.self, from: payload)
    }

    func update(from alias: FoodAlias) throws {
        self.alias = alias.alias
        payload = try JSONEncoder.domain.encode(alias)
    }
}

@Model
final class MealEntryRecord {
    @Attribute(.unique) var id: UUID
    var logDay: String
    var schemaVersion: Int
    var payload: Data

    init(entry: MealEntry) throws {
        self.id = entry.id
        self.logDay = entry.logDay.isoString
        self.schemaVersion = personalStoreSchemaVersion
        self.payload = try JSONEncoder.domain.encode(entry)
    }

    func decoded() throws -> MealEntry {
        try JSONDecoder.domain.decode(MealEntry.self, from: payload)
    }

    func update(from entry: MealEntry) throws {
        logDay = entry.logDay.isoString
        payload = try JSONEncoder.domain.encode(entry)
    }
}

@Model
final class ManualAdjustmentRecord {
    @Attribute(.unique) var id: UUID
    var logDay: String
    var schemaVersion: Int
    var payload: Data

    init(adjustment: ManualAdjustment) throws {
        self.id = adjustment.id
        self.logDay = adjustment.logDay.isoString
        self.schemaVersion = personalStoreSchemaVersion
        self.payload = try JSONEncoder.domain.encode(adjustment)
    }

    func decoded() throws -> ManualAdjustment {
        try JSONDecoder.domain.decode(ManualAdjustment.self, from: payload)
    }

    func update(from adjustment: ManualAdjustment) throws {
        logDay = adjustment.logDay.isoString
        payload = try JSONEncoder.domain.encode(adjustment)
    }
}

@Model
final class MutationReceiptRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var schemaVersion: Int
    var payload: Data

    init(receipt: MutationReceipt) throws {
        self.id = receipt.id
        self.createdAt = receipt.createdAt
        self.schemaVersion = personalStoreSchemaVersion
        self.payload = try JSONEncoder.domain.encode(receipt)
    }

    func decoded() throws -> MutationReceipt {
        try JSONDecoder.domain.decode(MutationReceipt.self, from: payload)
    }
}

@Model
final class ConfigurationVersionRecord {
    @Attribute(.unique) var key: String   // templateID@version
    var templateID: String
    var version: Int
    var effectiveFrom: String
    var schemaVersion: Int
    var payload: Data

    init(configuration: TrackerConfiguration) throws {
        self.key = configuration.id
        self.templateID = configuration.templateID
        self.version = configuration.version
        self.effectiveFrom = configuration.effectiveFrom.isoString
        self.schemaVersion = personalStoreSchemaVersion
        self.payload = try JSONEncoder.domain.encode(configuration)
    }

    func decoded() throws -> TrackerConfiguration {
        try JSONDecoder.domain.decode(TrackerConfiguration.self, from: payload)
    }
}

extension JSONEncoder {
    static var domain: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var domain: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
