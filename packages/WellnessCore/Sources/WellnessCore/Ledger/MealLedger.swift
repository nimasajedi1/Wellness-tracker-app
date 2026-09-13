import Foundation

/// Entry lifecycle (FOOD-011). Only current committed revisions affect intake
/// totals; questions and plans never do (CHAT-001).
public enum MealEntryStatus: String, Codable, Sendable {
    case draft
    case planned
    case committed
    case replaced
    case deleted
}

/// One food line inside a meal entry, snapshotting the food version and the
/// scaled nutrients at commit time (FOOD-001).
public struct MealItemSnapshot: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var foodID: String
    public var foodVersionID: String
    public var displayName: String
    public var portionDescription: String
    public var resolvedMassG: Decimal?
    public var nutrients: [NutrientID: NutrientValue]
    public var evidenceType: EvidenceType

    public init(
        id: UUID = UUID(),
        foodID: String,
        foodVersionID: String,
        displayName: String,
        portionDescription: String,
        resolvedMassG: Decimal? = nil,
        nutrients: [NutrientID: NutrientValue],
        evidenceType: EvidenceType
    ) {
        self.id = id
        self.foodID = foodID
        self.foodVersionID = foodVersionID
        self.displayName = displayName
        self.portionDescription = portionDescription
        self.resolvedMassG = resolvedMassG
        self.nutrients = nutrients
        self.evidenceType = evidenceType
    }

    public static func from(food: FoodVersion, scaled: ScaledNutrients, portionDescription: String) -> MealItemSnapshot {
        MealItemSnapshot(
            foodID: food.foodID,
            foodVersionID: food.versionID,
            displayName: food.canonicalName,
            portionDescription: portionDescription,
            resolvedMassG: scaled.resolvedMassG,
            nutrients: scaled.values,
            evidenceType: food.evidence.evidenceType
        )
    }
}

/// A meal entry revision. Corrections create a new revision of the same entry;
/// they never append a second meal (CHAT-003, REG-024).
public struct MealEntryRevision: Codable, Hashable, Sendable {
    public var revisionNumber: Int
    public var items: [MealItemSnapshot]
    public var status: MealEntryStatus
    public var createdAt: Date
    public var mutationID: UUID
    public var note: String?

    public init(revisionNumber: Int, items: [MealItemSnapshot], status: MealEntryStatus, createdAt: Date, mutationID: UUID, note: String? = nil) {
        self.revisionNumber = revisionNumber
        self.items = items
        self.status = status
        self.createdAt = createdAt
        self.mutationID = mutationID
        self.note = note
    }
}

public struct MealEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var logDay: LogDay
    public var mealLabel: String?
    public var revisions: [MealEntryRevision]

    public init(id: UUID = UUID(), logDay: LogDay, mealLabel: String? = nil, revisions: [MealEntryRevision]) {
        self.id = id
        self.logDay = logDay
        self.mealLabel = mealLabel
        self.revisions = revisions
    }

    public var currentRevision: MealEntryRevision? { revisions.last }
    public var isCountedInTotals: Bool { currentRevision?.status == .committed }
}

/// Auditable absolute-total adjustment (FOOD-019/020): "set today's protein to
/// 120 g" becomes a visible delta against the derived total at preview time.
public struct ManualAdjustment: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var logDay: LogDay
    public var nutrientID: NutrientID
    public var deltaValue: Decimal
    public var reason: String
    public var createdAt: Date
    public var mutationID: UUID
    public var isDeleted: Bool

    public init(id: UUID = UUID(), logDay: LogDay, nutrientID: NutrientID, deltaValue: Decimal, reason: String, createdAt: Date, mutationID: UUID, isDeleted: Bool = false) {
        self.id = id
        self.logDay = logDay
        self.nutrientID = nutrientID
        self.deltaValue = deltaValue
        self.reason = reason
        self.createdAt = createdAt
        self.mutationID = mutationID
        self.isDeleted = isDeleted
    }
}

/// Receipt for every mutation (STORE-005): drives visible history and Undo.
public struct MutationReceipt: Codable, Hashable, Sendable, Identifiable {
    public enum CommandType: String, Codable, Sendable {
        case commitMeal, reviseMeal, removeMeal, undo, manualAdjustment, dayReset
    }
    public var id: UUID
    public var mutationID: UUID
    public var commandType: CommandType
    public var affectedEntryID: UUID?
    public var oldRevision: Int?
    public var newRevision: Int?
    public var createdAt: Date
    public var summary: String

    public init(id: UUID = UUID(), mutationID: UUID, commandType: CommandType, affectedEntryID: UUID? = nil, oldRevision: Int? = nil, newRevision: Int? = nil, createdAt: Date, summary: String) {
        self.id = id
        self.mutationID = mutationID
        self.commandType = commandType
        self.affectedEntryID = affectedEntryID
        self.oldRevision = oldRevision
        self.newRevision = newRevision
        self.createdAt = createdAt
        self.summary = summary
    }
}

public enum LedgerError: Error, Equatable, Sendable {
    case entryNotFound
    case revisionConflict(expected: Int, actual: Int)
    case entryNotCommitted
    case nothingToUndo
    case invalidState(String)
}

/// In-memory meal ledger implementing the commit protocol invariants
/// (CHAT-015..017): idempotent mutation IDs, optimistic revision checks, and
/// persisted-undo-friendly revision history. Persistence adapters replay the
/// same operations; this type carries the domain rules.
public struct MealLedger: Sendable {
    public private(set) var entries: [UUID: MealEntry] = [:]
    public private(set) var adjustments: [ManualAdjustment] = []
    public private(set) var receipts: [MutationReceipt] = []
    private var appliedMutationIDs: Set<UUID> = []

    public init() {}

    /// Restore a ledger from persisted state (STORE-004: totals are rebuilt as
    /// projections). Applied mutation IDs are rebuilt so idempotence and
    /// persisted Undo survive a restart (CHAT-016, STORE-005, REG-034).
    public init(entries: [MealEntry], adjustments: [ManualAdjustment], receipts: [MutationReceipt]) {
        for entry in entries { self.entries[entry.id] = entry }
        self.adjustments = adjustments
        self.receipts = receipts
        for entry in entries {
            for revision in entry.revisions { appliedMutationIDs.insert(revision.mutationID) }
        }
        for adjustment in adjustments { appliedMutationIDs.insert(adjustment.mutationID) }
        for receipt in receipts { appliedMutationIDs.insert(receipt.mutationID) }
    }

    // MARK: - Commits

    /// Commit a new meal. Re-invoking with the same mutationID is a no-op
    /// (CHAT-016, REG-031); a deliberate "another one" uses a new mutationID
    /// (REG-032).
    @discardableResult
    public mutating func commitMeal(
        entryID: UUID = UUID(),
        logDay: LogDay,
        mealLabel: String? = nil,
        items: [MealItemSnapshot],
        mutationID: UUID,
        at now: Date
    ) throws -> MealEntry {
        if appliedMutationIDs.contains(mutationID) {
            if let existing = entries.values.first(where: { $0.revisions.contains { $0.mutationID == mutationID } }) {
                return existing
            }
            throw LedgerError.invalidState("Mutation already applied but entry missing")
        }
        let revision = MealEntryRevision(revisionNumber: 1, items: items, status: .committed, createdAt: now, mutationID: mutationID)
        let entry = MealEntry(id: entryID, logDay: logDay, mealLabel: mealLabel, revisions: [revision])
        entries[entryID] = entry
        appliedMutationIDs.insert(mutationID)
        receipts.append(MutationReceipt(
            mutationID: mutationID,
            commandType: .commitMeal,
            affectedEntryID: entryID,
            oldRevision: nil,
            newRevision: 1,
            createdAt: now,
            summary: "Logged \(items.count) item(s)"
        ))
        return entry
    }

    /// Revise an existing entry atomically: the new item list replaces the old
    /// one in a single revision (CHAT-003, REG-024). `expectedRevision`
    /// implements optimistic concurrency (CHAT-017).
    @discardableResult
    public mutating func reviseMeal(
        entryID: UUID,
        expectedRevision: Int,
        newItems: [MealItemSnapshot],
        mutationID: UUID,
        note: String? = nil,
        at now: Date
    ) throws -> MealEntry {
        if appliedMutationIDs.contains(mutationID), let existing = entries[entryID] {
            return existing
        }
        guard var entry = entries[entryID] else { throw LedgerError.entryNotFound }
        guard let current = entry.currentRevision else { throw LedgerError.invalidState("Entry has no revisions") }
        guard current.revisionNumber == expectedRevision else {
            throw LedgerError.revisionConflict(expected: expectedRevision, actual: current.revisionNumber)
        }
        let revision = MealEntryRevision(
            revisionNumber: current.revisionNumber + 1,
            items: newItems,
            status: .committed,
            createdAt: now,
            mutationID: mutationID,
            note: note
        )
        entry.revisions.append(revision)
        entries[entryID] = entry
        appliedMutationIDs.insert(mutationID)
        receipts.append(MutationReceipt(
            mutationID: mutationID,
            commandType: .reviseMeal,
            affectedEntryID: entryID,
            oldRevision: current.revisionNumber,
            newRevision: revision.revisionNumber,
            createdAt: now,
            summary: note ?? "Revised meal"
        ))
        return entry
    }

    /// Remove a committed entry reversibly (CHAT-004: "I scrapped the oatmeal"
    /// on an already-logged meal offers removal, kept as a revision).
    @discardableResult
    public mutating func removeMeal(entryID: UUID, mutationID: UUID, at now: Date) throws -> MealEntry {
        if appliedMutationIDs.contains(mutationID), let existing = entries[entryID] {
            return existing
        }
        guard var entry = entries[entryID] else { throw LedgerError.entryNotFound }
        guard let current = entry.currentRevision else { throw LedgerError.invalidState("Entry has no revisions") }
        let revision = MealEntryRevision(
            revisionNumber: current.revisionNumber + 1,
            items: current.items,
            status: .deleted,
            createdAt: now,
            mutationID: mutationID
        )
        entry.revisions.append(revision)
        entries[entryID] = entry
        appliedMutationIDs.insert(mutationID)
        receipts.append(MutationReceipt(
            mutationID: mutationID,
            commandType: .removeMeal,
            affectedEntryID: entryID,
            oldRevision: current.revisionNumber,
            newRevision: revision.revisionNumber,
            createdAt: now,
            summary: "Removed meal"
        ))
        return entry
    }

    /// Undo the latest mutation on an entry: restores the immediately preceding
    /// revision once (UI-012, REG-034). Old Undo cannot silently overwrite a
    /// newer revision because it always appends a restoring revision on top.
    @discardableResult
    public mutating func undoLastRevision(entryID: UUID, mutationID: UUID, at now: Date) throws -> MealEntry {
        if appliedMutationIDs.contains(mutationID), let existing = entries[entryID] {
            return existing
        }
        guard var entry = entries[entryID] else { throw LedgerError.entryNotFound }
        guard entry.revisions.count >= 2 else { throw LedgerError.nothingToUndo }
        let current = entry.revisions[entry.revisions.count - 1]
        let previous = entry.revisions[entry.revisions.count - 2]
        let restoring = MealEntryRevision(
            revisionNumber: current.revisionNumber + 1,
            items: previous.items,
            status: previous.status,
            createdAt: now,
            mutationID: mutationID,
            note: "Undo of revision \(current.revisionNumber)"
        )
        entry.revisions.append(restoring)
        entries[entryID] = entry
        appliedMutationIDs.insert(mutationID)
        receipts.append(MutationReceipt(
            mutationID: mutationID,
            commandType: .undo,
            affectedEntryID: entryID,
            oldRevision: current.revisionNumber,
            newRevision: restoring.revisionNumber,
            createdAt: now,
            summary: "Undid last change"
        ))
        return entry
    }

    // MARK: - Manual adjustments

    /// Apply "set today's <nutrient> total to X": records the delta against the
    /// supplied current derived total (FOOD-020, REG-033). The caller passes the
    /// derived total it previewed; a stale preview surfaces as a mismatch to
    /// re-confirm upstream.
    @discardableResult
    public mutating func applyAbsoluteTotalEdit(
        logDay: LogDay,
        nutrientID: NutrientID,
        targetTotal: Decimal,
        currentDerivedTotal: Decimal,
        mutationID: UUID,
        at now: Date
    ) -> ManualAdjustment? {
        if appliedMutationIDs.contains(mutationID) {
            return adjustments.first { $0.mutationID == mutationID }
        }
        let delta = targetTotal - currentDerivedTotal
        let adjustment = ManualAdjustment(
            logDay: logDay,
            nutrientID: nutrientID,
            deltaValue: delta,
            reason: "Set daily total to \(targetTotal)",
            createdAt: now,
            mutationID: mutationID
        )
        adjustments.append(adjustment)
        appliedMutationIDs.insert(mutationID)
        receipts.append(MutationReceipt(
            mutationID: mutationID,
            commandType: .manualAdjustment,
            createdAt: now,
            summary: "Adjustment \(delta) to \(nutrientID.rawValue)"
        ))
        return adjustment
    }

    // MARK: - Day reset

    /// Reset one day's committed meals and adjustments reversibly (UI-010,
    /// REG-054). Configuration, favorites, recipes, and other days are untouched.
    public mutating func resetDay(_ logDay: LogDay, mutationID: UUID, at now: Date) {
        guard !appliedMutationIDs.contains(mutationID) else { return }
        for (id, entry) in entries where entry.logDay == logDay && entry.isCountedInTotals {
            _ = try? removeMeal(entryID: id, mutationID: UUID(), at: now)
        }
        for index in adjustments.indices where adjustments[index].logDay == logDay {
            adjustments[index].isDeleted = true
        }
        appliedMutationIDs.insert(mutationID)
        receipts.append(MutationReceipt(
            mutationID: mutationID,
            commandType: .dayReset,
            createdAt: now,
            summary: "Reset day \(logDay.isoString)"
        ))
    }

    // MARK: - Projections

    /// Rebuildable daily nutrient totals (STORE-004, FOOD-019): committed
    /// snapshots plus visible adjustments — never a separate cached counter.
    public func dayNutrientTotals(
        logDay: LogDay,
        nutrientIDs: [NutrientID]
    ) -> [NutrientID: (total: Decimal, coverage: AggregatedMetricValue.Coverage, hasData: Bool)] {
        let dayEntries = entries.values.filter { $0.logDay == logDay && $0.isCountedInTotals }
        let snapshots = dayEntries.flatMap { $0.currentRevision?.items ?? [] }
        let dayAdjustments = adjustments.filter { $0.logDay == logDay && !$0.isDeleted }

        var result: [NutrientID: (Decimal, AggregatedMetricValue.Coverage, Bool)] = [:]
        for id in nutrientIDs {
            var total: Decimal = 0
            var knownCount = 0
            for item in snapshots {
                if let value = (item.nutrients[id] ?? .unknown(reason: "missing")).decimalValue {
                    total += value
                    knownCount += 1
                }
            }
            var hasData = knownCount > 0
            for adjustment in dayAdjustments where adjustment.nutrientID == id {
                total += adjustment.deltaValue
                hasData = true
            }
            let coverage: AggregatedMetricValue.Coverage
            if snapshots.isEmpty {
                coverage = hasData ? .complete : .none
            } else if knownCount < snapshots.count {
                coverage = .partial
            } else {
                coverage = .complete
            }
            result[id] = (total, coverage, hasData)
        }
        return result
    }

    public func entriesForDay(_ logDay: LogDay) -> [MealEntry] {
        entries.values
            .filter { $0.logDay == logDay }
            .sorted { ($0.revisions.first?.createdAt ?? .distantPast) < ($1.revisions.first?.createdAt ?? .distantPast) }
    }
}
