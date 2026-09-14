import Foundation
import WellnessCore

/// Seed foods (CAT-001): the user's own transcribed labels, clearly marked as
/// user-entered evidence. Synthetic fixtures never surface in search; there
/// are no invented "official" records here.
///
/// Kept in its own file because quick-action intents and the widget extension
/// also compile it.
enum SeedCatalog {
    static let foods: [FoodVersion] = [
        FoodVersion(
            foodID: "user-ham",
            versionID: "1",
            canonicalName: "Ham, sliced (my label)",
            basis: .namedServing(name: "1 serving", massG: 56, volumeML: nil),
            nutrients: [
                .energyKcal: .known(60),
                .proteinG: .known(9),
                .fiberG: .unknown(reason: "Not on label")
            ],
            evidence: SourceEvidence(sourceID: "U01", sourceLocator: "User label photo transcription", evidenceType: .userEnteredLabel)
        ),
        FoodVersion(
            foodID: "user-shake",
            versionID: "1",
            canonicalName: "Protein shake (my label)",
            basis: .namedServing(name: "1 container", massG: nil, volumeML: nil),
            nutrients: [
                .energyKcal: .known(130),
                .proteinG: .known(30),
                .fiberG: .known(1)
            ],
            evidence: SourceEvidence(sourceID: "U02", sourceLocator: "User label photo transcription", evidenceType: .userEnteredLabel)
        ),
        FoodVersion(
            foodID: "user-tray",
            versionID: "1",
            canonicalName: "Factor meal tray (my label)",
            basis: .namedServing(name: "1 tray", massG: 340, volumeML: nil),
            nutrients: [
                .energyKcal: .known(500),
                .proteinG: .known(43),
                .fiberG: .known(7)
            ],
            evidence: SourceEvidence(sourceID: "U03", sourceLocator: "User label photo transcription", evidenceType: .userEnteredLabel)
        )
    ]

    static let aliases: [FoodAlias] = [
        FoodAlias(
            alias: "my ham", foodID: "user-ham", preferredVersionID: "1",
            defaultPortion: PortionRequest(.servings(2))
        ),
        FoodAlias(
            alias: "my shake", foodID: "user-shake", preferredVersionID: "1",
            defaultPortion: PortionRequest(.servings(1))
        )
    ]
}