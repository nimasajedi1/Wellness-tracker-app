import SwiftUI
import PhotosUI
import UIKit
import WellnessCore

/// DEVICE-007 review screen: the captured image beside the extracted values,
/// low-confidence/ambiguous fields highlighted, every field correctable, an
/// explicit basis choice when the label carries multiple columns, and an
/// explicit confirmation before any food is created or updated. A scan can
/// never silently overwrite an existing food — updating creates a new version
/// and old diary snapshots keep their values (FOOD-001).
struct EnhancedLabelCaptureSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let onSaved: (FoodVersion) -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var extracting = false
    @State private var extractionFailure: String?
    @State private var draft: StructuredLabelDraft?
    @State private var selectedBasis: LabelColumnBasis = .perServing
    @State private var name = ""
    @State private var updateExistingFoodID: String?
    @State private var showImageFull = false

    /// Field edit buffer: string values per nutrient for the selected column.
    @State private var amountTexts: [LabelNutrientKey: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                if let draft {
                    reviewSections(draft)
                }
            }
            .navigationTitle("Label capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(updateExistingFoodID == nil ? "Create food" : "Save new version") { confirm() }
                        .disabled(!canConfirm)
                }
            }
            .onChange(of: photoItem) {
                Task { await capture() }
            }
            .onChange(of: selectedBasis) {
                populateEditBuffer()
            }
            .sheet(isPresented: $showImageFull) {
                if let imageData, let uiImage = UIImage(data: imageData) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: uiImage).resizable().scaledToFit()
                    }
                    .presentationDetents([.large])
                }
            }
        }
    }

    // MARK: - Sections

    private var photoSection: some View {
        Section("Label photo") {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(imageData == nil ? "Choose label photo" : "Choose a different photo", systemImage: "photo")
            }
            if extracting { ProgressView("Reading label…") }
            if let imageData, let uiImage = UIImage(data: imageData) {
                // The image stays beside the values for verification; tap to zoom.
                Button {
                    showImageFull = true
                } label: {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Captured label image; tap to enlarge")
            }
            if let extractionFailure {
                Label(extractionFailure, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func reviewSections(_ draft: StructuredLabelDraft) -> some View {
        if draft.columns.count > 1 {
            Section("Which column do you mean?") {
                // Columns stay distinct until this explicit choice (DEVICE-007).
                Picker("Basis", selection: $selectedBasis) {
                    ForEach(draft.columns) { column in
                        Text(column.basis.displayName).tag(column.basis)
                    }
                }
                .pickerStyle(.segmented)
            }
        }

        Section("Product") {
            TextField("Food name", text: $name)
            if let match = matchingExistingFood {
                Picker("This label is for", selection: $updateExistingFoodID) {
                    Text("A new food").tag(String?.none)
                    Text("New version of “\(match.canonicalName)”").tag(String?.some(match.foodID))
                }
                Text("Updating never rewrites meals you already logged; they keep the version they were logged with.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }

        Section("Serving") {
            LabeledContent("Description") {
                TextField("e.g. 2 slices (56g)", text: servingDescriptionBinding)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Mass (g)") {
                TextField("—", text: decimalBinding(\.servingMassG)).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("Volume (mL)") {
                TextField("—", text: decimalBinding(\.servingVolumeML)).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("Servings per container") {
                TextField("—", text: decimalBinding(\.servingsPerContainer)).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
        }

        Section("Nutrition facts — confirm every value") {
            ForEach(LabelNutrientKey.allCases, id: \.rawValue) { key in
                nutrientRow(key)
            }
        } footer: {
            Text("Empty fields stay unknown; they are never saved as zero, and a %DV is never converted into an amount. Values marked for review differ from expectations — check them against the image.")
        }

        let issues = currentIssues()
        if !issues.isEmpty {
            Section("Review notes") {
                ForEach(issues) { issue in
                    Label(issue.message, systemImage: issue.severity == .blocking ? "xmark.octagon" : "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(issue.severity == .blocking ? .red : .orange)
                }
            }
        }
        if !draft.extractionNotes.isEmpty {
            Section("Extraction notes") {
                ForEach(draft.extractionNotes, id: \.self) { note in
                    Text(note).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    private func nutrientRow(_ key: LabelNutrientKey) -> some View {
        let extracted = currentColumn?.nutrients[key]
        let flagged = fieldIsFlagged(key)
        return VStack(alignment: .leading, spacing: 2) {
            LabeledContent {
                HStack(spacing: 4) {
                    TextField("—", text: Binding(
                        get: { amountTexts[key] ?? "" },
                        set: { amountTexts[key] = $0; applyEdit(key: key, text: $0) }
                    ))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    Text(key == .calories ? "kcal" : key.canonicalUnit.rawValue)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            } label: {
                HStack(spacing: 4) {
                    if flagged {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .imageScale(.small)
                            .accessibilityLabel("Needs review")
                    }
                    Text(key.displayName)
                }
            }
            if let extracted {
                Text("Read: “\(extracted.sourceText)”\(extracted.dailyValuePercent.map { " · \($0)% DV (not used as amount)" } ?? "")")
                    .font(.caption2)
                    .foregroundStyle(flagged ? .orange : Theme.secondaryText)
            }
        }
    }

    // MARK: - State plumbing

    private var currentColumn: LabelColumn? {
        draft?.columns.first { $0.basis == selectedBasis }
    }

    private var matchingExistingFood: FoodVersion? {
        let needle = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return nil }
        return appModel.userFoods.first { $0.canonicalName.lowercased() == needle }
    }

    private var canConfirm: Bool {
        guard let draft, draft.looksLikeNutritionLabel || hasManualEntries else { return false }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return !currentIssues().contains { $0.severity == .blocking }
    }

    private var hasManualEntries: Bool {
        amountTexts.values.contains { Double($0) != nil }
    }

    private func currentIssues() -> [LabelValidationIssue] {
        guard let draft else { return [] }
        return (try? LabelDraftValidator.validate(draft: draft, basis: selectedBasis))?.issues ?? []
    }

    private func fieldIsFlagged(_ key: LabelNutrientKey) -> Bool {
        let lowConfidence = currentColumn?.nutrients[key].map { $0.confidence == .low || $0.conflicting } ?? false
        return lowConfidence || currentIssues().contains { $0.field == key.rawValue }
    }

    private var servingDescriptionBinding: Binding<String> {
        Binding(
            get: { draft?.servingDescription ?? "" },
            set: { draft?.servingDescription = $0.isEmpty ? nil : $0 }
        )
    }

    private func decimalBinding(_ keyPath: WritableKeyPath<StructuredLabelDraft, Decimal?>) -> Binding<String> {
        Binding(
            get: {
                guard let value = draft?[keyPath: keyPath] else { return "" }
                return "\(value)"
            },
            set: { text in
                draft?[keyPath: keyPath] = Decimal(string: text.replacingOccurrences(of: ",", with: "."))
            }
        )
    }

    /// A user edit replaces the extracted reading for that field; corrections
    /// re-validate immediately so blocking flags clear before commit.
    private func applyEdit(key: LabelNutrientKey, text: String) {
        guard var draft, let index = draft.columns.firstIndex(where: { $0.basis == selectedBasis }) else { return }
        if text.isEmpty {
            draft.columns[index].nutrients.removeValue(forKey: key)
        } else if let value = Decimal(string: text.replacingOccurrences(of: ",", with: ".")) {
            draft.columns[index].nutrients[key] = ExtractedLabelValue(
                amount: value,
                dailyValuePercent: draft.columns[index].nutrients[key]?.dailyValuePercent,
                sourceText: draft.columns[index].nutrients[key]?.sourceText ?? "entered by you",
                confidence: .high,
                conflicting: false
            )
        }
        self.draft = draft
    }

    private func populateEditBuffer() {
        amountTexts = [:]
        guard let column = currentColumn else { return }
        for (key, value) in column.nutrients {
            if let amount = value.amount {
                amountTexts[key] = "\(amount)"
            }
        }
        if name.isEmpty, let productName = draft?.productName {
            name = productName
        }
    }

    // MARK: - Capture

    private func capture() async {
        guard let photoItem else { return }
        extracting = true
        extractionFailure = nil
        defer { extracting = false }
        guard let data = try? await photoItem.loadTransferable(type: Data.self) else {
            extractionFailure = "Could not load that photo."
            return
        }
        imageData = data

        // Preferred extractor first; on any failure fall back to the DEVICE-002
        // line path; if that also fails, the form stays fully manual — food
        // entry is never blocked (DEVICE-007 degradation rule).
        var produced: StructuredLabelDraft?
        do {
            produced = try await StructuredLabelExtractorFactory.make().extract(imageData: data)
        } catch {
            if let fallback = try? await LineParserLabelExtractor().extract(imageData: data) {
                produced = fallback
                extractionFailure = "Structured reading failed; used basic text recognition instead."
            } else {
                extractionFailure = "Nothing readable was found — enter the values manually from the label."
            }
        }

        if let produced {
            if produced.looksLikeNutritionLabel {
                draft = produced
                selectedBasis = produced.columns.first?.basis ?? .perServing
            } else {
                // Not a nutrition label: say so; keep manual entry available.
                draft = StructuredLabelDraft(columns: [LabelColumn(basis: .perServing)], extractionSource: produced.extractionSource)
                selectedBasis = .perServing
                extractionFailure = "That image does not look like a nutrition label. You can still enter values manually."
            }
        } else {
            draft = StructuredLabelDraft(columns: [LabelColumn(basis: .perServing)], extractionSource: .manualEntry)
            selectedBasis = .perServing
        }
        populateEditBuffer()
    }

    // MARK: - Confirm

    private func confirm() {
        guard let draft else { return }
        do {
            let validated = try LabelDraftValidator.validate(draft: draft, basis: selectedBasis)
            let existingID = updateExistingFoodID
            let version = try LabelDraftValidator.foodVersion(
                from: validated,
                draft: draft,
                name: name,
                market: "US",
                existingFoodID: existingID,
                newVersionID: existingID.map { appModel.nextUserFoodVersionID(foodID: $0) } ?? "1",
                createdAt: appModel.dateProvider.now()
            )
            appModel.saveUserFood(version)
            onSaved(version)
            dismiss()
        } catch {
            extractionFailure = "Cannot save yet: \(error). Correct the flagged fields first."
        }
    }
}
