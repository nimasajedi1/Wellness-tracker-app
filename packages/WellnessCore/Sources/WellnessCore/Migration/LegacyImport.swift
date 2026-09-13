import Foundation

/// User-initiated import of the legacy v19 web tracker payload
/// (`nimaWellnessTrackerCompactV2`, STORE-011..015). The native app cannot read
/// Safari localStorage; the user exports the JSON from the old page and shares
/// the file. The payload holds one date's state, not a historical ledger.
public struct LegacyPayload: Codable, Sendable {
    public var date: String?
    public var sleepStart: String?
    public var sleepEnd: String?
    public var fastStart: String?
    public var fastEnd: String?
    public var protein: Double?
    public var fiber: Double?
    public var water: Double?      // legacy unit: liters
    public var calories: Double?
    public var steps: Double?
    public var activeCalories: Double?
    public var exerciseDone: Bool?
    public var exerciseType: String?
    public var morningPills: Bool?
    public var eveningPills: Bool?
    public var theme: String?
}

public struct LegacyImportPreview: Sendable {
    public struct Field: Sendable, Identifiable {
        public var id: String { metricID.rawValue }
        public var metricID: MetricID
        public var proposedValue: ObservedValue
        /// Legacy default zeros are ambiguous (STORE-014): the preview asks
        /// whether the field was genuinely entered; untouched-looking values
        /// default to skipped.
        public var looksLikeUntouchedDefault: Bool
        public var include: Bool
    }
    public var logDay: LogDay
    /// Fingerprint for deduplication (STORE-015, REG-048).
    public var fingerprint: String
    public var fields: [Field]
    public var warnings: [String]
}

public enum LegacyImportError: Error, Equatable, Sendable {
    case missingDate
    case invalidPayload
    case alreadyImported(fingerprint: String)
}

public enum LegacyImporter {

    /// Stable fingerprint of payload content + date for idempotent imports.
    public static func fingerprint(of data: Data) -> String {
        // FNV-1a 64-bit; deterministic without CryptoKit (Linux-testable).
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    public static func preview(payloadData: Data, existingFingerprints: Set<String>) throws -> LegacyImportPreview {
        let payload: LegacyPayload
        do {
            payload = try JSONDecoder().decode(LegacyPayload.self, from: payloadData)
        } catch {
            throw LegacyImportError.invalidPayload
        }
        guard let dateString = payload.date, let day = LogDay(isoString: dateString) else {
            throw LegacyImportError.missingDate
        }
        let printKey = fingerprint(of: payloadData)
        if existingFingerprints.contains(printKey) {
            throw LegacyImportError.alreadyImported(fingerprint: printKey)
        }

        var fields: [LegacyImportPreview.Field] = []
        var warnings: [String] = [
            "The old tracker stores one day's state; earlier days cannot be recovered from this file.",
            "Values are imported as legacy manual data, not source-backed meals."
        ]

        func addQuantity(_ metricID: MetricID, _ value: Double?, unit: UnitOfMeasure, scale: Double = 1) {
            guard let value else { return }
            fields.append(LegacyImportPreview.Field(
                metricID: metricID,
                proposedValue: .quantity(value * scale, unit),
                looksLikeUntouchedDefault: value == 0,
                include: value != 0
            ))
        }

        addQuantity(OwnerMetrics.protein, payload.protein, unit: .gram)
        addQuantity(OwnerMetrics.fiber, payload.fiber, unit: .gram)
        // Legacy water is liters; canonical volume is milliliters.
        addQuantity(OwnerMetrics.water, payload.water, unit: .milliliter, scale: 1000)
        addQuantity(OwnerMetrics.calories, payload.calories, unit: .kilocalorie)
        addQuantity(OwnerMetrics.steps, payload.steps, unit: .step)
        addQuantity(OwnerMetrics.activeEnergy, payload.activeCalories, unit: .kilocalorie)

        if let done = payload.exerciseDone {
            fields.append(LegacyImportPreview.Field(
                metricID: OwnerMetrics.workoutDone,
                proposedValue: .boolean(done),
                looksLikeUntouchedDefault: done == false,
                include: done
            ))
        }
        if payload.morningPills != nil || payload.eveningPills != nil {
            fields.append(LegacyImportPreview.Field(
                metricID: OwnerMetrics.supplements,
                proposedValue: .checklist(["AM": payload.morningPills ?? false, "PM": payload.eveningPills ?? false]),
                looksLikeUntouchedDefault: (payload.morningPills ?? false) == false && (payload.eveningPills ?? false) == false,
                include: (payload.morningPills ?? false) || (payload.eveningPills ?? false)
            ))
        }
        if payload.sleepStart != nil || payload.sleepEnd != nil {
            warnings.append("Sleep times are clock-only in the old tracker; review their dates before importing.")
        }
        if payload.fastStart != nil || payload.fastEnd != nil {
            warnings.append("Fasting times are clock-only in the old tracker; review their dates before importing.")
        }

        return LegacyImportPreview(logDay: day, fingerprint: printKey, fields: fields, warnings: warnings)
    }

    /// Convert an accepted preview into observations with the legacyImport
    /// source label. Only included fields become records.
    public static func observations(from preview: LegacyImportPreview, timeZone: TimeZone, importedAt: Date) -> [Observation] {
        preview.fields.filter(\.include).map { field in
            Observation(
                metricID: field.metricID,
                value: field.proposedValue,
                observedAt: preview.logDay.startOfDay(in: timeZone),
                timeZoneIdentifier: timeZone.identifier,
                logDay: preview.logDay,
                source: .legacyImport,
                externalSampleID: "legacy:\(preview.fingerprint):\(field.metricID.rawValue)"
            )
        }
    }
}
