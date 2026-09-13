import Foundation

public enum CardWidth: String, Codable, Sendable {
    case half, full
}

public struct LayoutCard: Codable, Hashable, Sendable, Identifiable {
    public var cardID: String
    public var title: String?
    public var metricIDs: [MetricID]
    public var goalIDs: [GoalID]
    public var width: CardWidth
    public var order: Int
    public var isPinnedSummary: Bool
    public var isHidden: Bool

    public var id: String { cardID }

    public init(
        cardID: String,
        title: String? = nil,
        metricIDs: [MetricID] = [],
        goalIDs: [GoalID] = [],
        width: CardWidth = .half,
        order: Int,
        isPinnedSummary: Bool = false,
        isHidden: Bool = false
    ) {
        self.cardID = cardID
        self.title = title
        self.metricIDs = metricIDs
        self.goalIDs = goalIDs
        self.width = width
        self.order = order
        self.isPinnedSummary = isPinnedSummary
        self.isHidden = isHidden
    }
}

/// Versioned tracker configuration (BUILD-007): Save publishes a new version
/// with an effective date; historical days keep the version effective then.
public struct TrackerConfiguration: Codable, Hashable, Sendable, Identifiable {
    public var schemaVersion: Int
    public var templateID: String
    public var version: Int
    public var name: String
    public var effectiveFrom: LogDay
    public var metrics: [MetricDefinition]
    public var goals: [GoalConfiguration]
    public var layout: [LayoutCard]
    /// Metric IDs hidden from view but still collected (BUILD-008).
    public var hiddenMetricIDs: [MetricID]
    /// Metric IDs whose automatic collection is disabled; history preserved.
    public var collectionDisabledMetricIDs: [MetricID]

    public var id: String { "\(templateID)@\(version)" }

    public init(
        schemaVersion: Int = 1,
        templateID: String,
        version: Int = 1,
        name: String,
        effectiveFrom: LogDay,
        metrics: [MetricDefinition],
        goals: [GoalConfiguration],
        layout: [LayoutCard],
        hiddenMetricIDs: [MetricID] = [],
        collectionDisabledMetricIDs: [MetricID] = []
    ) {
        self.schemaVersion = schemaVersion
        self.templateID = templateID
        self.version = version
        self.name = name
        self.effectiveFrom = effectiveFrom
        self.metrics = metrics
        self.goals = goals
        self.layout = layout
        self.hiddenMetricIDs = hiddenMetricIDs
        self.collectionDisabledMetricIDs = collectionDisabledMetricIDs
    }
}

public enum ConfigurationValidationError: Error, Equatable, Sendable {
    case duplicateMetricID(MetricID)
    case duplicateGoalID(GoalID)
    case duplicateCardID(String)
    case unknownMetricReference(MetricID, referencedBy: String)
    case unknownGoalReference(GoalID, referencedBy: String)
    case dependencyCycle([MetricID])
    case emptyComposite(GoalID)
    case invalidBounds(GoalID, String)
    case schemaVersionUnsupported(Int)
}

/// Validation applied before Save and before import preview (BUILD-009,
/// BUILD-012, SEC-002). Failure is atomic: nothing is applied.
public enum ConfigurationValidator {
    public static let supportedSchemaVersions: Set<Int> = [1]
    public static let maxMetrics = 200
    public static let maxGoals = 200
    public static let maxCards = 100

    public static func validate(_ config: TrackerConfiguration) -> [ConfigurationValidationError] {
        var errors: [ConfigurationValidationError] = []

        if !supportedSchemaVersions.contains(config.schemaVersion) {
            errors.append(.schemaVersionUnsupported(config.schemaVersion))
        }

        // Uniqueness
        var metricIDs = Set<MetricID>()
        for metric in config.metrics {
            if !metricIDs.insert(metric.id).inserted { errors.append(.duplicateMetricID(metric.id)) }
        }
        var goalIDs = Set<GoalID>()
        for goal in config.goals {
            if !goalIDs.insert(goal.id).inserted { errors.append(.duplicateGoalID(goal.id)) }
        }
        var cardIDs = Set<String>()
        for card in config.layout {
            if !cardIDs.insert(card.cardID).inserted { errors.append(.duplicateCardID(card.cardID)) }
        }

        // References
        for goal in config.goals {
            if let metricID = goal.metricID, !metricIDs.contains(metricID) {
                errors.append(.unknownMetricReference(metricID, referencedBy: goal.id.rawValue))
            }
            for member in goal.memberGoalIDs where !goalIDs.contains(member) {
                errors.append(.unknownGoalReference(member, referencedBy: goal.id.rawValue))
            }
            if goal.kind == .composite && goal.memberGoalIDs.isEmpty {
                errors.append(.emptyComposite(goal.id))
            }
            errors.append(contentsOf: validateBounds(goal))
        }
        for card in config.layout {
            for metricID in card.metricIDs where !metricIDs.contains(metricID) {
                errors.append(.unknownMetricReference(metricID, referencedBy: card.cardID))
            }
            for goalID in card.goalIDs where !goalIDs.contains(goalID) {
                errors.append(.unknownGoalReference(goalID, referencedBy: card.cardID))
            }
        }
        for metric in config.metrics {
            for dependency in metric.dependencies where !metricIDs.contains(dependency) {
                errors.append(.unknownMetricReference(dependency, referencedBy: metric.id.rawValue))
            }
        }

        // Dependency cycles (BUILD-009, REG-039)
        if let cycle = findCycle(in: config.metrics) {
            errors.append(.dependencyCycle(cycle))
        }

        return errors
    }

    static func validateBounds(_ goal: GoalConfiguration) -> [ConfigurationValidationError] {
        var errors: [ConfigurationValidationError] = []
        let bounds = goal.bounds
        switch goal.kind {
        case .minimum:
            if goal.scoringEnabled, bounds.metMinimum == nil {
                errors.append(.invalidBounds(goal.id, "minimum goal needs metMinimum"))
            }
            if let met = bounds.metMinimum, let near = bounds.nearMinimum, near > met {
                errors.append(.invalidBounds(goal.id, "nearMinimum must not exceed metMinimum"))
            }
        case .maximum:
            if goal.scoringEnabled, bounds.metMaximum == nil {
                errors.append(.invalidBounds(goal.id, "maximum goal needs metMaximum"))
            }
            if let met = bounds.metMaximum, let near = bounds.nearMaximum, near < met {
                errors.append(.invalidBounds(goal.id, "nearMaximum must not be below metMaximum"))
            }
        case .range, .exact:
            guard let lower = bounds.metLower, let upper = bounds.metUpper else {
                if goal.scoringEnabled {
                    errors.append(.invalidBounds(goal.id, "range goal needs metLower and metUpper"))
                }
                return errors
            }
            if lower > upper {
                errors.append(.invalidBounds(goal.id, "metLower must not exceed metUpper"))
            }
            if let nearLower = bounds.nearLower, nearLower > lower {
                errors.append(.invalidBounds(goal.id, "nearLower must not exceed metLower"))
            }
            if let nearUpper = bounds.nearUpper, nearUpper < upper {
                errors.append(.invalidBounds(goal.id, "nearUpper must not be below metUpper"))
            }
        case .completion, .trendOnly, .composite:
            break
        }
        return errors
    }

    /// Depth-first cycle detection over metric dependencies.
    static func findCycle(in metrics: [MetricDefinition]) -> [MetricID]? {
        let adjacency = Dictionary(uniqueKeysWithValues: metrics.map { ($0.id, $0.dependencies) })
        var state: [MetricID: Int] = [:] // 0 unvisited, 1 in stack, 2 done
        var stack: [MetricID] = []
        var cycle: [MetricID]? = nil

        func visit(_ node: MetricID) {
            guard cycle == nil else { return }
            state[node] = 1
            stack.append(node)
            for next in adjacency[node] ?? [] {
                if state[next] == 1 {
                    if let start = stack.firstIndex(of: next) {
                        cycle = Array(stack[start...])
                    } else {
                        cycle = [next, node]
                    }
                    return
                }
                if state[next, default: 0] == 0 {
                    visit(next)
                }
            }
            stack.removeLast()
            state[node] = 2
        }

        for metric in metrics where state[metric.id, default: 0] == 0 {
            visit(metric.id)
            if cycle != nil { break }
        }
        return cycle
    }
}

/// Export/import of configuration only — never health observations or chat
/// (BUILD-012, PRIV-004 separation).
public enum ConfigurationPorting {
    public static let maxImportBytes = 1_000_000

    public static func export(_ config: TrackerConfiguration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(config)
    }

    public static func importConfiguration(from data: Data) throws -> TrackerConfiguration {
        guard data.count <= maxImportBytes else {
            throw ConfigurationValidationError.invalidBounds(GoalID("import"), "file exceeds size limit")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let config = try decoder.decode(TrackerConfiguration.self, from: data)
        let errors = ConfigurationValidator.validate(config)
        if let first = errors.first {
            throw first
        }
        return config
    }
}
