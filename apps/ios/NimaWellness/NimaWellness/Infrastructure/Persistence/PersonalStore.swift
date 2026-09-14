import Foundation
import SwiftData
import WellnessCore

enum PersonalStoreError: Error {
    case saveFailed(String)
}

/// SwiftData adapter behind the domain (ARCH-001, M1.5). Mutations write the
/// affected records and save atomically; a failed save is reported truthfully
/// (STORE-003) and the caller keeps its draft.
@MainActor
final class PersonalStore {
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
    }

    // MARK: - Loading

    func loadLedger() throws -> MealLedger {
        let entries = try context.fetch(FetchDescriptor<MealEntryRecord>()).compactMap { try? $0.decoded() }
        let adjustments = try context.fetch(FetchDescriptor<ManualAdjustmentRecord>()).compactMap { try? $0.decoded() }
        let receipts = try context.fetch(FetchDescriptor<MutationReceiptRecord>()).compactMap { try? $0.decoded() }
        return MealLedger(entries: entries, adjustments: adjustments, receipts: receipts)
    }

    func observations(on day: LogDay) throws -> [Observation] {
        let dayKey = day.isoString
        let descriptor = FetchDescriptor<ObservationRecord>(
            predicate: #Predicate { $0.logDay == dayKey && !$0.isDeleted },
            sortBy: [SortDescriptor(\.observedAt)]
        )
        return try context.fetch(descriptor).compactMap { try? $0.decoded() }
    }

    func daysWithData(in range: ClosedRange<LogDay>) throws -> Set<LogDay> {
        let observations = try context.fetch(FetchDescriptor<ObservationRecord>())
        let entries = try context.fetch(FetchDescriptor<MealEntryRecord>())
        var days = Set<LogDay>()
        for record in observations where !record.isDeleted {
            if let day = LogDay(isoString: record.logDay), range.contains(day) { days.insert(day) }
        }
        for record in entries {
            if let day = LogDay(isoString: record.logDay), range.contains(day) { days.insert(day) }
        }
        return days
    }

    func latestConfiguration() throws -> TrackerConfiguration? {
        let records = try context.fetch(FetchDescriptor<ConfigurationVersionRecord>())
        return records
            .compactMap { try? $0.decoded() }
            .max { ($0.effectiveFrom, $0.version) < ($1.effectiveFrom, $1.version) }
    }

    func configuration(effectiveOn day: LogDay) throws -> TrackerConfiguration? {
        let records = try context.fetch(FetchDescriptor<ConfigurationVersionRecord>())
        let configs = records.compactMap { try? $0.decoded() }
        return configs
            .filter { $0.effectiveFrom <= day }
            .max { ($0.effectiveFrom, $0.version) < ($1.effectiveFrom, $1.version) }
            ?? configs.min { ($0.effectiveFrom, $0.version) < ($1.effectiveFrom, $1.version) }
    }

    // MARK: - Writing

    func save(observation: Observation) throws {
        let id = observation.id
        let existing = try context.fetch(FetchDescriptor<ObservationRecord>(predicate: #Predicate { $0.id == id }))
        if let record = existing.first {
            try record.update(from: observation)
        } else {
            context.insert(try ObservationRecord(observation: observation))
        }
        try saveContext()
    }

    /// Persist the ledger's state for the entries/adjustments/receipts touched
    /// by one mutation, in one transaction (STORE-003).
    func persist(ledger: MealLedger, touchedEntryIDs: [UUID]) throws {
        for entryID in touchedEntryIDs {
            guard let entry = ledger.entries[entryID] else { continue }
            let existing = try context.fetch(FetchDescriptor<MealEntryRecord>(predicate: #Predicate { $0.id == entryID }))
            if let record = existing.first {
                try record.update(from: entry)
            } else {
                context.insert(try MealEntryRecord(entry: entry))
            }
        }
        let storedAdjustments = Set(try context.fetch(FetchDescriptor<ManualAdjustmentRecord>()).map(\.id))
        for adjustment in ledger.adjustments {
            if storedAdjustments.contains(adjustment.id) {
                let adjustmentID = adjustment.id
                if let record = try context.fetch(FetchDescriptor<ManualAdjustmentRecord>(predicate: #Predicate { $0.id == adjustmentID })).first {
                    try record.update(from: adjustment)
                }
            } else {
                context.insert(try ManualAdjustmentRecord(adjustment: adjustment))
            }
        }
        let storedReceipts = Set(try context.fetch(FetchDescriptor<MutationReceiptRecord>()).map(\.id))
        for receipt in ledger.receipts where !storedReceipts.contains(receipt.id) {
            context.insert(try MutationReceiptRecord(receipt: receipt))
        }
        try saveContext()
    }

    func publish(configuration: TrackerConfiguration) throws {
        if let first = ConfigurationValidator.validate(configuration).first {
            throw first
        }
        context.insert(try ConfigurationVersionRecord(configuration: configuration))
        try saveContext()
    }

    // MARK: - Health import (P1)

    /// Replace all imported observations for one metric/day with a fresh set,
    /// atomically. Reimports and store-side updates/deletions stay idempotent
    /// because imports are keyed by stable external sample IDs (HEALTH-003);
    /// manual observations are never touched here.
    func replaceHealthObservations(metricID: MetricID, day: LogDay, with observations: [Observation]) throws {
        let metricKey = metricID.rawValue
        let dayKey = day.isoString
        let existing = try context.fetch(FetchDescriptor<ObservationRecord>(
            predicate: #Predicate { $0.metricID == metricKey && $0.logDay == dayKey && $0.externalSampleID != nil }
        ))
        for record in existing {
            context.delete(record)
        }
        for observation in observations where observation.source == .healthKit {
            context.insert(try ObservationRecord(observation: observation))
        }
        try saveContext()
    }

    /// Remove every imported observation (HEALTH-007 disconnect: stops future
    /// imports and, on request, clears imported copies; the originals stay in
    /// the health store — this app never deletes another app's samples).
    func deleteAllHealthObservations() throws {
        let records = try context.fetch(FetchDescriptor<ObservationRecord>(
            predicate: #Predicate { $0.externalSampleID != nil }
        ))
        for record in records where record.externalSampleID?.hasPrefix("healthkit:") == true {
            context.delete(record)
        }
        try saveContext()
    }

    // MARK: - User foods and favorites (P1)

    func saveUserFood(_ food: FoodVersion) throws {
        let key = food.id
        let existing = try context.fetch(FetchDescriptor<UserFoodRecord>(predicate: #Predicate { $0.key == key }))
        if existing.isEmpty {
            context.insert(try UserFoodRecord(food: food))
            try saveContext()
        }
        // Versioned facts (FOOD-001): an existing version is never overwritten;
        // a changed label becomes a new versionID upstream.
    }

    func loadUserFoods() throws -> [FoodVersion] {
        try context.fetch(FetchDescriptor<UserFoodRecord>()).compactMap { try? $0.decoded() }
    }

    func saveAlias(_ alias: FoodAlias) throws {
        let id = alias.id
        let existing = try context.fetch(FetchDescriptor<FoodAliasRecord>(predicate: #Predicate { $0.id == id }))
        if let record = existing.first {
            try record.update(from: alias)
        } else {
            context.insert(try FoodAliasRecord(alias: alias))
        }
        try saveContext()
    }

    func loadAliases() throws -> [FoodAlias] {
        try context.fetch(FetchDescriptor<FoodAliasRecord>()).compactMap { try? $0.decoded() }
    }

    func markObservationDeleted(id: UUID) throws {
        if let record = try context.fetch(FetchDescriptor<ObservationRecord>(predicate: #Predicate { $0.id == id })).first {
            record.isDeleted = true
            try saveContext()
        }
    }

    private func saveContext() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw PersonalStoreError.saveFailed(error.localizedDescription)
        }
    }
}
