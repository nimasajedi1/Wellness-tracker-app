import Foundation
import WellnessCore

/// DEVICE-007 extraction pipeline. Order of preference:
///   1. Vision `RecognizeDocumentsRequest` document hierarchy (iOS 27 path).
///   2. Optional Foundation Models image interpretation over the Vision
///      result (MAY; compiled in only with the NIMA_FM_IMAGE_LABELS flag).
///   3. DEVICE-002 recognized-lines parsing.
/// Every step degrades to the next on unavailability, refusal, or failure —
/// food entry is never blocked — and every step produces the same
/// `StructuredLabelDraft` that deterministic validation and user review gate.
/// No image or text leaves the device on any of these paths.
protocol StructuredLabelExtracting: Sendable {
    func extract(imageData: Data) async throws -> StructuredLabelDraft
}

enum LabelExtractionError: Error {
    case unsupportedImage
    case recognitionFailed(String)
    case unavailable
}

enum StructuredLabelExtractorFactory {
    /// The best extractor this device supports right now. Never nil: the
    /// line-parser fallback exists everywhere the app runs.
    static func make() -> any StructuredLabelExtracting {
        if #available(iOS 27.0, *) {
            #if canImport(Vision)
            return DocumentLabelReader()
            #endif
        }
        return LineParserLabelExtractor()
    }

    static var usesDocumentPath: Bool {
        if #available(iOS 27.0, *) {
            #if canImport(Vision)
            return true
            #else
            return false
            #endif
        }
        return false
    }
}

/// Baseline extractor: DEVICE-002 text recognition bridged into the shared
/// structured draft, so both OS generations use one review pipeline.
struct LineParserLabelExtractor: StructuredLabelExtracting {
    func extract(imageData: Data) async throws -> StructuredLabelDraft {
        let lines = try await LabelTextRecognizer.recognizeLines(imageData: imageData)
        guard !lines.isEmpty else { throw LabelExtractionError.recognitionFailed("No readable text") }
        return LabelRowParser.draft(fromRows: lines, freeTextLines: [], barcodes: [], source: .lineParser)
    }
}

#if canImport(Vision)
import Vision
#if canImport(UIKit)
import UIKit
#endif

/// iOS 27 structured-document reader (DEVICE-007, [S21]).
///
/// NOTE for the Mac build: `RecognizeDocumentsRequest` and the
/// `DocumentObservation` container types are new Vision APIs — verify the
/// exact property names (`document`, `tables`, `text.transcript`, `barcodes`)
/// against the installed iOS 27 SDK and adjust the traversal below if the
/// shipped surface differs. The traversal is deliberately thin: everything
/// semantic happens in WellnessCore's deterministic `LabelRowParser`.
@available(iOS 27.0, *)
struct DocumentLabelReader: StructuredLabelExtracting {

    func extract(imageData: Data) async throws -> StructuredLabelDraft {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw LabelExtractionError.unsupportedImage
        }
        let request = RecognizeDocumentsRequest()
        let observations: [DocumentObservation]
        do {
            observations = try await request.perform(on: cgImage)
        } catch {
            throw LabelExtractionError.recognitionFailed(String(describing: error))
        }
        guard let document = observations.first?.document else {
            throw LabelExtractionError.recognitionFailed("No document structure recognized")
        }

        // Table rows first: a Nutrition Facts panel is a table, and row
        // grouping keeps a nutrient's amount and %DV together.
        var rows: [String] = []
        for table in document.tables {
            for row in table.rows {
                let cells = row.compactMap { cell in
                    cell.content.text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let joined = cells.filter { !$0.isEmpty }.joined(separator: " ")
                if !joined.isEmpty { rows.append(joined) }
            }
        }

        // Remaining free text covers serving lines printed outside the table.
        let freeText = document.text.transcript
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Machine-readable codes found on the same capture.
        let barcodes = document.barcodes.compactMap { $0.payloadString }

        var draft = LabelRowParser.draft(
            fromRows: rows,
            freeTextLines: freeText,
            barcodes: barcodes,
            source: .visionDocument
        )

        #if NIMA_FM_IMAGE_LABELS
        // Optional Foundation Models refinement (MAY path, [S22-S23]): the
        // model only re-maps what Vision read; deterministic validation still
        // gates every value. Any failure keeps the Vision draft.
        if let refined = try? await FoundationModelLabelInterpreter().refine(draft: draft, imageData: imageData) {
            draft = refined
        }
        #endif

        return draft
        #else
        throw LabelExtractionError.unavailable
        #endif
    }
}

#if NIMA_FM_IMAGE_LABELS
#if canImport(FoundationModels)
import FoundationModels

/// Optional Foundation Models label interpreter (DEVICE-007 MAY path).
///
/// Compiled only when the NIMA_FM_IMAGE_LABELS compilation condition is set
/// (target build settings → Active Compilation Conditions) so the project
/// builds on SDKs that do not yet expose image prompting or the Vision
/// `OCRTool`/`BarcodeReaderTool` tool types. Verify those APIs against the
/// installed iOS 27 SDK before enabling the flag; on refusal, unavailability,
/// or schema failure the caller keeps the deterministic Vision draft.
@available(iOS 27.0, *)
struct FoundationModelLabelInterpreter {

    @Generable
    struct GeneratedNutrient {
        @Guide(description: "One of: calories, totalFat, saturatedFat, transFat, cholesterol, sodium, totalCarbohydrate, dietaryFiber, totalSugars, addedSugars, protein")
        var key: String
        @Guide(description: "Absolute amount in g, mg, or kcal as printed; omit when only a %DV is printed")
        var amount: Double?
        @Guide(description: "Percent Daily Value when printed; never converted to an amount")
        var dailyValuePercent: Double?
        @Guide(description: "The exact printed text this reading came from")
        var sourceText: String
        @Guide(description: "Column this value belongs to: perServing, perContainer, prepared, or unprepared")
        var column: String
    }

    @Generable
    struct GeneratedLabel {
        var productName: String?
        var servingsPerContainer: Double?
        var servingDescription: String?
        var servingMassG: Double?
        var servingVolumeML: Double?
        var nutrients: [GeneratedNutrient]
    }

    func refine(draft: StructuredLabelDraft, imageData: Data) async throws -> StructuredLabelDraft {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { throw LabelExtractionError.unavailable }

        let session = LanguageModelSession(
            model: model,
            // Vision-backed read-only tools per [S23]; verify tool type names
            // against the SDK when enabling this flag.
            tools: [OCRTool(), BarcodeReaderTool()],
            instructions: """
            Map this nutrition label into the structured schema. Report only \
            values printed on the label; never estimate or complete missing \
            fields. Keep %DV separate from absolute amounts. Distinguish \
            per-serving from per-container columns.
            Vision pre-read for reference:
            \(draft.columns.flatMap { column in column.nutrients.values.map(\.sourceText) }.joined(separator: "\n"))
            """
        )
        let response = try await session.respond(
            to: Prompt {
                "Extract the nutrition facts from this label image."
                Image(data: imageData)
            },
            generating: GeneratedLabel.self
        )
        return Self.merge(generated: response.content, into: draft)
    }

    /// Map generated output into the schema. Unknown keys/columns are dropped;
    /// the deterministic validator and review UI still gate everything.
    static func merge(generated: GeneratedLabel, into base: StructuredLabelDraft) -> StructuredLabelDraft {
        var columns: [LabelColumnBasis: LabelColumn] = [:]
        for nutrient in generated.nutrients {
            guard let key = LabelNutrientKey(rawValue: nutrient.key) else { continue }
            let basis: LabelColumnBasis
            switch nutrient.column {
            case "perContainer": basis = .perContainer
            case "prepared": basis = .prepared
            case "unprepared": basis = .unprepared
            default: basis = .perServing
            }
            var column = columns[basis] ?? LabelColumn(basis: basis)
            column.nutrients[key] = ExtractedLabelValue(
                amount: nutrient.amount.map { Decimal($0) },
                dailyValuePercent: nutrient.dailyValuePercent.map { Decimal($0) },
                sourceText: nutrient.sourceText,
                confidence: .medium
            )
            columns[basis] = column
        }
        guard !columns.isEmpty else { return base }
        var draft = base
        draft.productName = generated.productName ?? base.productName
        draft.servingsPerContainer = generated.servingsPerContainer.map { Decimal($0) } ?? base.servingsPerContainer
        draft.servingDescription = generated.servingDescription ?? base.servingDescription
        draft.servingMassG = generated.servingMassG.map { Decimal($0) } ?? base.servingMassG
        draft.servingVolumeML = generated.servingVolumeML.map { Decimal($0) } ?? base.servingVolumeML
        draft.columns = Array(columns.values)
        draft.extractionSource = .foundationModelInterpretation
        return draft
    }
}
#endif
#endif
#endif
