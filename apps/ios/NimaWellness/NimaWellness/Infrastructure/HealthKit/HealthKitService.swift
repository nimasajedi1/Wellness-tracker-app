import Foundation
import WellnessCore

/// Health data types the app can read (HEALTH-001): each is enabled
/// individually, permission is requested just-in-time for the enabled set
/// only, and everything is read-only in this release (HEALTH-006).
enum HealthDataType: String, Codable, CaseIterable, Identifiable {
    case steps
    case activeEnergy
    case restingEnergy
    case sleep
    case bodyMass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .steps: return "Steps"
        case .activeEnergy: return "Active energy"
        case .restingEnergy: return "Resting energy"
        case .sleep: return "Sleep"
        case .bodyMass: return "Weight"
        }
    }

    var purpose: String {
        switch self {
        case .steps: return "Fills the daily step total instead of manual entry."
        case .activeEnergy: return "Supplies the day's active energy for the balance estimate."
        case .restingEnergy: return "Enables the Health-data energy method (no formula added on top)."
        case .sleep: return "Fills the sleep duration from recorded sleep intervals."
        case .bodyMass: return "Records weight as a trend-only observation."
        }
    }
}

enum HealthKitError: Error {
    case unavailableOnDevice
    case queryFailed(String)
}

#if canImport(HealthKit)
import HealthKit

/// Read-only HealthKit adapter. Notes on honesty and reconciliation:
/// - HealthKit does not reveal denied *read* permissions; "no data" therefore
///   never claims the user denied access (HEALTH-002).
/// - Daily quantities use statistics queries, which already reconcile
///   overlapping iPhone/watch samples — raw overlapping samples are never
///   re-summed by this app (HEALTH-003).
/// - Sleep imports only actually-asleep stages; in-bed time is excluded, and
///   overlap is unioned by the durationUnion aggregation (HEALTH-005).
final class HealthKitService: @unchecked Sendable {

    static var isAvailableOnDevice: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private let store = HKHealthStore()

    private func objectType(for type: HealthDataType) -> HKObjectType? {
        switch type {
        case .steps: return HKQuantityType.quantityType(forIdentifier: .stepCount)
        case .activeEnergy: return HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        case .restingEnergy: return HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned)
        case .sleep: return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        case .bodyMass: return HKQuantityType.quantityType(forIdentifier: .bodyMass)
        }
    }

    /// Just-in-time authorization for exactly the enabled types (HEALTH-001).
    func requestReadAuthorization(for types: Set<HealthDataType>) async throws {
        guard Self.isAvailableOnDevice else { throw HealthKitError.unavailableOnDevice }
        let readTypes = Set(types.compactMap { objectType(for: $0) })
        guard !readTypes.isEmpty else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    private func dayWindow(_ day: LogDay, timeZone: TimeZone) -> (start: Date, end: Date) {
        let start = day.startOfDay(in: timeZone)
        let end = day.adding(days: 1, timeZone: timeZone).startOfDay(in: timeZone)
        return (start, end)
    }

    /// Daily total for a quantity type via a deduplicating statistics query.
    /// nil = no readable samples, which is NOT evidence of denied permission.
    func dailyQuantity(_ type: HealthDataType, day: LogDay, timeZone: TimeZone) async throws -> Double? {
        guard let quantityType = objectType(for: type) as? HKQuantityType else { return nil }
        let window = dayWindow(day, timeZone: timeZone)
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: .strictStartDate)

        let unit: HKUnit
        switch type {
        case .steps: unit = .count()
        case .activeEnergy, .restingEnergy: unit = .kilocalorie()
        case .bodyMass: unit = .gramUnit(with: .kilo)
        case .sleep: return nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: type == .bodyMass ? .discreteAverage : .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    // "No data" errors are a normal empty state, not a failure.
                    if (error as? HKError)?.code == .errorNoData {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }
                let quantity = type == .bodyMass
                    ? statistics?.averageQuantity()
                    : statistics?.sumQuantity()
                continuation.resume(returning: quantity?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Asleep intervals overlapping the day (extended back six hours so a
    /// night that started yesterday evening attributes to this morning's day).
    func sleepIntervals(day: LogDay, timeZone: TimeZone) async throws -> [ImportedSleepInterval] {
        guard let sleepType = objectType(for: .sleep) as? HKCategoryType else { return [] }
        let window = dayWindow(day, timeZone: timeZone)
        let start = window.start.addingTimeInterval(-6 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: window.end, options: [])

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, results, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let asleepValues = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        return samples
            .filter { asleepValues.contains($0.value) }   // in-bed excluded (HEALTH-005)
            .map { sample in
                ImportedSleepInterval(
                    sampleID: sample.uuid.uuidString,
                    start: sample.startDate,
                    end: sample.endDate
                )
            }
    }
}
#else
/// Stub so the target still compiles where HealthKit is unavailable.
final class HealthKitService: @unchecked Sendable {
    static var isAvailableOnDevice: Bool { false }
    func requestReadAuthorization(for types: Set<HealthDataType>) async throws {
        throw HealthKitError.unavailableOnDevice
    }
    func dailyQuantity(_ type: HealthDataType, day: LogDay, timeZone: TimeZone) async throws -> Double? { nil }
    func sleepIntervals(day: LogDay, timeZone: TimeZone) async throws -> [ImportedSleepInterval] { [] }
}
#endif
