import Foundation

/// Repository protocols (ARCH-001): the domain is testable with in-memory
/// implementations; SwiftData adapters live in the app target.
public protocol ObservationRepository: Sendable {
    func observations(on day: LogDay) async throws -> [Observation]
    func observations(metricID: MetricID, on day: LogDay) async throws -> [Observation]
    func save(_ observation: Observation) async throws
    func markDeleted(id: UUID) async throws
}

public protocol ConfigurationRepository: Sendable {
    /// The configuration version effective for a given day (BUILD-007, UI-015).
    func configuration(effectiveOn day: LogDay) async throws -> TrackerConfiguration?
    func latestConfiguration() async throws -> TrackerConfiguration?
    func publish(_ configuration: TrackerConfiguration) async throws
}

public protocol FoodCatalogRepository: Sendable {
    func searchLocal(query: String, market: String) async throws -> [FoodVersion]
    func foodVersion(foodID: String, versionID: String) async throws -> FoodVersion?
    /// Exact barcode lookup (CAT-006, DEVICE-001). The GTIN must already be
    /// checksum-validated; matching is against stored identifier keys only.
    func foodByBarcode(_ gtin: String, market: String) async throws -> [FoodVersion]
    func aliases(matching text: String) async throws -> [FoodAlias]
    func saveAlias(_ alias: FoodAlias) async throws
}

// MARK: - In-memory implementations (M0: tests, previews, mock-driven UI)

public actor InMemoryObservationRepository: ObservationRepository {
    private var storage: [UUID: Observation] = [:]

    public init() {}

    public func observations(on day: LogDay) async throws -> [Observation] {
        storage.values.filter { $0.logDay == day && !$0.isDeleted }.sorted { $0.observedAt < $1.observedAt }
    }

    public func observations(metricID: MetricID, on day: LogDay) async throws -> [Observation] {
        try await observations(on: day).filter { $0.metricID == metricID }
    }

    public func save(_ observation: Observation) async throws {
        storage[observation.id] = observation
    }

    public func markDeleted(id: UUID) async throws {
        if var observation = storage[id] {
            observation.isDeleted = true
            storage[id] = observation
        }
    }
}

public actor InMemoryConfigurationRepository: ConfigurationRepository {
    private var versions: [TrackerConfiguration] = []

    public init(initial: TrackerConfiguration? = nil) {
        if let initial { versions = [initial] }
    }

    public func configuration(effectiveOn day: LogDay) async throws -> TrackerConfiguration? {
        versions
            .filter { $0.effectiveFrom <= day }
            .max { ($0.effectiveFrom, $0.version) < ($1.effectiveFrom, $1.version) }
            ?? versions.min { ($0.effectiveFrom, $0.version) < ($1.effectiveFrom, $1.version) }
    }

    public func latestConfiguration() async throws -> TrackerConfiguration? {
        versions.max { ($0.effectiveFrom, $0.version) < ($1.effectiveFrom, $1.version) }
    }

    public func publish(_ configuration: TrackerConfiguration) async throws {
        let errors = ConfigurationValidator.validate(configuration)
        if let first = errors.first { throw first }
        versions.append(configuration)
    }
}

public actor InMemoryFoodCatalogRepository: FoodCatalogRepository {
    private var foods: [String: FoodVersion] = [:]   // keyed by foodID#versionID
    private var aliasStore: [FoodAlias] = []

    public init(foods: [FoodVersion] = []) {
        for food in foods { self.foods[food.id] = food }
    }

    public func add(_ food: FoodVersion) {
        foods[food.id] = food
    }

    public func searchLocal(query: String, market: String) async throws -> [FoodVersion] {
        let needle = query.lowercased()
        return foods.values.filter { food in
            food.marketCountry == market &&
            // Synthetic fixtures never surface in production search (CAT-001).
            food.evidence.evidenceType != .syntheticFixture &&
            (food.canonicalName.lowercased().contains(needle)
             || (food.brand?.lowercased().contains(needle) ?? false)
             || (food.restaurant?.lowercased().contains(needle) ?? false))
        }.sorted { $0.canonicalName < $1.canonicalName }
    }

    public func foodVersion(foodID: String, versionID: String) async throws -> FoodVersion? {
        foods["\(foodID)#\(versionID)"]
    }

    public func foodByBarcode(_ gtin: String, market: String) async throws -> [FoodVersion] {
        let keys = Set(Barcode.lookupKeys(for: gtin))
        return foods.values.filter { food in
            food.marketCountry == market &&
            food.evidence.evidenceType != .syntheticFixture &&
            food.identifiers.contains { key, value in
                (key == "gtin" || key == "upc") && keys.contains(value.filter(\.isNumber))
            }
        }.sorted { $0.canonicalName < $1.canonicalName }
    }

    public func aliases(matching text: String) async throws -> [FoodAlias] {
        let needle = text.lowercased()
        return aliasStore.filter { needle.contains($0.alias.lowercased()) || $0.alias.lowercased().contains(needle) }
    }

    public func saveAlias(_ alias: FoodAlias) async throws {
        aliasStore.removeAll { $0.alias.lowercased() == alias.alias.lowercased() && $0.market == alias.market }
        aliasStore.append(alias)
    }
}
