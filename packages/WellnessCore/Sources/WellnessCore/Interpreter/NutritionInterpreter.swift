import Foundation

/// Application-owned interpreter contract (ARCH-002, section 11.1). The model
/// returns a small typed proposal; it never returns finished answers containing
/// invented nutrition. Facts and math stay in deterministic code.
public struct InterpretedTurn: Codable, Hashable, Sendable {
    public enum Intent: String, Codable, Sendable {
        case logFood
        case lookupFood
        case compare
        case hypothetical
        case reviseMeal
        case removeEntry
        case summarizeDay
        case recordObservation
        case proposeGoalChange
        case clarify
        case unsupported
    }

    public struct FoodMention: Codable, Hashable, Sendable {
        public enum Reference: String, Codable, Sendable {
            case explicitFood
            case savedAlias
            case previousEntry
            case unknown
        }
        public var textSpan: String
        public var normalizedQuery: String
        public var brand: String?
        public var restaurant: String?
        public var market: String?
        public var quantity: Double?
        public var unit: String?
        public var count: Double?
        public var perItemQuantity: Double?
        public var preparation: String?
        public var reference: Reference
        /// Named modifiers only ("no cheese"); never free-form nutrition edits.
        public var modifiers: [String]

        public init(
            textSpan: String,
            normalizedQuery: String,
            brand: String? = nil,
            restaurant: String? = nil,
            market: String? = nil,
            quantity: Double? = nil,
            unit: String? = nil,
            count: Double? = nil,
            perItemQuantity: Double? = nil,
            preparation: String? = nil,
            reference: Reference = .unknown,
            modifiers: [String] = []
        ) {
            self.textSpan = textSpan
            self.normalizedQuery = normalizedQuery
            self.brand = brand
            self.restaurant = restaurant
            self.market = market
            self.quantity = quantity
            self.unit = unit
            self.count = count
            self.perItemQuantity = perItemQuantity
            self.preparation = preparation
            self.reference = reference
            self.modifiers = modifiers
        }
    }

    public struct Clarification: Codable, Hashable, Sendable {
        public var question: String
        /// Bounded selectable candidates (UI-014, CHAT-012: at most five).
        public var options: [String]
        public init(question: String, options: [String] = []) {
            self.question = question
            self.options = Array(options.prefix(5))
        }
    }

    public struct MetricChangeProposal: Codable, Hashable, Sendable {
        public var metricID: MetricID
        public var proposedValue: Double
        public var unit: String?
        public init(metricID: MetricID, proposedValue: Double, unit: String? = nil) {
            self.metricID = metricID
            self.proposedValue = proposedValue
            self.unit = unit
        }
    }

    public var intent: Intent
    public var items: [FoodMention]
    /// Validated against supplied candidates by the application, never trusted
    /// as an arbitrary ID (CHAT-015).
    public var targetEntryID: UUID?
    public var targetLogDay: LogDay?
    public var metricChanges: [MetricChangeProposal]
    public var unresolvedQuestions: [Clarification]

    public init(
        intent: Intent,
        items: [FoodMention] = [],
        targetEntryID: UUID? = nil,
        targetLogDay: LogDay? = nil,
        metricChanges: [MetricChangeProposal] = [],
        unresolvedQuestions: [Clarification] = []
    ) {
        self.intent = intent
        // Bounded batch: at most eight food mentions per turn (CHAT-007).
        self.items = Array(items.prefix(8))
        self.targetEntryID = targetEntryID
        self.targetLogDay = targetLogDay
        self.metricChanges = metricChanges
        self.unresolvedQuestions = unresolvedQuestions
    }
}

/// Availability states (ARCH-004). Mirrors the SDK's public cases with an
/// unknown-case fallback; UI maps each to actionable guidance.
public enum InterpreterAvailability: Equatable, Sendable {
    case ready
    case deviceNotSupported
    case intelligenceDisabled
    case modelNotReady        // downloading or not yet provisioned
    case unsupportedLocale
    case unknown(String)
}

public enum InterpreterError: Error, Sendable {
    case unavailable(InterpreterAvailability)
    case generationFailed(String)
    case refused(String)
    case cancelled
    case budgetExceeded
}

/// Context supplied per turn: current request, active draft, bounded recent
/// identities and metric definitions — never full transcripts (CHAT-012).
public struct InterpretationContext: Sendable {
    public var selectedLogDay: LogDay
    public var activeDraftSummary: String?
    public var recentEntryCandidates: [(id: UUID, summary: String)]
    public var savedAliases: [String]
    public var activeMetricIDs: [MetricID]

    public init(
        selectedLogDay: LogDay,
        activeDraftSummary: String? = nil,
        recentEntryCandidates: [(id: UUID, summary: String)] = [],
        savedAliases: [String] = [],
        activeMetricIDs: [MetricID] = []
    ) {
        self.selectedLogDay = selectedLogDay
        self.activeDraftSummary = activeDraftSummary
        self.recentEntryCandidates = Array(recentEntryCandidates.prefix(5))
        self.savedAliases = savedAliases
        self.activeMetricIDs = activeMetricIDs
    }
}

/// Model abstraction boundary (ARCH-002). Implementations: AppleInterpreter
/// (explicit on-device SystemLanguageModel, in the app target), MockInterpreter
/// (deterministic, for tests and UI development), future providers (P2).
public protocol NutritionInterpreter: Sendable {
    func availability() async -> InterpreterAvailability
    /// One bounded, cancellable interpretation (ARCH-005, CHAT-011).
    func interpret(_ text: String, context: InterpretationContext) async throws -> InterpretedTurn
}
