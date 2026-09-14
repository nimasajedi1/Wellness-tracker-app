import SwiftUI
import PhotosUI
import WellnessCore

/// Optional label capture (DEVICE-002): the user picks a label photo, native
/// text recognition proposes fields, and an explicit review form decides what
/// is saved. A low-quality photo cannot overwrite anything automatically, and
/// no camera access is required for normal lookup.
struct LabelCaptureSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let onSaved: (FoodVersion) -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var recognizing = false
    @State private var recognitionError: String?
    @State private var candidate = ParsedLabelCandidate()
    @State private var recognizedAnything = false

    @State private var name = ""
    @State private var servingName = "1 serving"
    @State private var servingMassText = ""
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var fiberText = ""
    @State private var alsoSaveFavorite = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Label photo") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(recognizedAnything ? "Choose a different photo" : "Choose label photo", systemImage: "photo")
                    }
                    if recognizing { ProgressView("Reading label…") }
                    if let recognitionError {
                        Label(recognitionError, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Review — you confirm every value") {
                    TextField("Food name", text: $name)
                    TextField("Serving name (e.g. 1 slice)", text: $servingName)
                    labeledField("Serving mass (g)", text: $servingMassText, source: candidate.servingMassG?.sourceText)
                    labeledField("Calories (kcal)", text: $kcalText, source: candidate.energyKcal?.sourceText)
                    labeledField("Protein (g)", text: $proteinText, source: candidate.proteinG?.sourceText)
                    labeledField("Fiber (g)", text: $fiberText, source: candidate.fiberG?.sourceText)
                } footer: {
                    Text("Fields left empty stay unknown — they are never saved as zero. The saved food is marked as your transcribed label, not an official source.")
                }

                Section {
                    Toggle("Also save as favorite (1 serving)", isOn: $alsoSaveFavorite)
                }
            }
            .navigationTitle("Capture label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save food") { save() }
                        .disabled(!canSave)
                }
            }
            .onChange(of: photoItem) {
                Task { await recognize() }
            }
        }
    }

    private func labeledField(_ title: String, text: Binding<String>, source: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(title) {
                TextField("—", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            if let source {
                Text("From label: “\(source)”")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Double(kcalText) != nil || Double(proteinText) != nil || Double(fiberText) != nil)
    }

    private func save() {
        var confirmed = ParsedLabelCandidate()
        confirmed.servingName = servingName.isEmpty ? nil : servingName
        if let mass = Double(servingMassText) {
            confirmed.servingMassG = ParsedLabelField(value: mass, sourceText: candidate.servingMassG?.sourceText ?? "entered manually")
        }
        if let kcal = Double(kcalText) {
            confirmed.energyKcal = ParsedLabelField(value: kcal, sourceText: candidate.energyKcal?.sourceText ?? "entered manually")
        }
        if let protein = Double(proteinText) {
            confirmed.proteinG = ParsedLabelField(value: protein, sourceText: candidate.proteinG?.sourceText ?? "entered manually")
        }
        if let fiber = Double(fiberText) {
            confirmed.fiberG = ParsedLabelField(value: fiber, sourceText: candidate.fiberG?.sourceText ?? "entered manually")
        }
        guard let food = LabelTranscriptionParser.foodVersion(
            name: name.trimmingCharacters(in: .whitespaces),
            confirmed: confirmed,
            market: "US",
            createdAt: appModel.dateProvider.now()
        ) else { return }

        appModel.saveUserFood(food)
        if alsoSaveFavorite {
            appModel.saveFavorite(FoodAlias(
                alias: food.canonicalName.lowercased(),
                foodID: food.foodID,
                preferredVersionID: food.versionID,
                defaultPortion: PortionRequest(.servings(1))
            ))
        }
        onSaved(food)
        dismiss()
    }

    // MARK: OCR

    private func recognize() async {
        guard let photoItem else { return }
        recognizing = true
        recognitionError = nil
        defer { recognizing = false }
        do {
            guard let data = try await photoItem.loadTransferable(type: Data.self) else {
                recognitionError = "Could not load that photo."
                return
            }
            let lines = try await LabelTextRecognizer.recognizeLines(imageData: data)
            candidate = LabelTranscriptionParser.parse(lines: lines)
            recognizedAnything = true
            // Prefill the review fields; nothing is saved until Save food.
            if let mass = candidate.servingMassG { servingMassText = mass.value.cleanString }
            if let kcal = candidate.energyKcal { kcalText = kcal.value.cleanString }
            if let protein = candidate.proteinG { proteinText = protein.value.cleanString }
            if let fiber = candidate.fiberG { fiberText = fiber.value.cleanString }
            if !candidate.hasAnyNutrient {
                recognitionError = "No nutrition values were recognized — enter them manually from the label."
            }
        } catch {
            recognitionError = "Text recognition failed: \(error.localizedDescription). Enter the values manually."
        }
    }
}

enum LabelTextRecognizer {
    /// Native on-device text recognition. No image or text leaves the device.
    static func recognizeLines(imageData: Data) async throws -> [String] {
        #if canImport(Vision) && canImport(UIKit)
        guard let image = UIKit.UIImage(data: imageData), let cgImage = image.cgImage else { return [] }
        // Run synchronously off the main actor; Vision invokes the request's
        // completion during perform(), so collecting results afterward avoids
        // any double-resume of a continuation.
        return try await Task.detached(priority: .userInitiated) {
            let request = Vision.VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false   // label numbers, not prose
            let handler = Vision.VNImageRequestHandler(cgImage: cgImage)
            try handler.perform([request])
            let observations = request.results ?? []
            return observations.compactMap { $0.topCandidates(1).first?.string }
        }.value
        #else
        return []
        #endif
    }
}

#if canImport(Vision)
import Vision
#endif
#if canImport(UIKit)
import UIKit
#endif
