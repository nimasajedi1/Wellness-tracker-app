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
