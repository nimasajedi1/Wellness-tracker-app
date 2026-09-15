# Handoff: P2 slice — DEVICE-007 iOS 27 native nutrition-label understanding

**Milestone / slice:** P2, DEVICE-007 only (the requirement text supplied by
the owner on 2026-09-15, now merged into `docs/PRD.md` §16.2 with sources
S21-S23 and an acceptance-matrix row).

**Requirements addressed (implemented in code; device acceptance pending):**
- DEVICE-007 structured schema: product name, servings per container, serving
  description/mass/volume, and the full nutrient list (calories, total fat,
  saturated fat, trans fat, cholesterol, sodium, total carbohydrate, dietary
  fiber, total sugars, added sugars, protein) plus declared vitamins/minerals,
  each carrying the normalized value AND the verbatim source text, confidence,
  and %DV separately from the absolute amount.
- Deterministic validation before anything can commit: unit normalization
  (g/mg/mcg, sodium-in-grams → mg), numeric plausibility bounds, %DV never
  substituted for grams/milligrams, conflicting readings blocked until
  corrected, component-arithmetic and 4/4/9 checks that flag for review but
  never rewrite printed values (FOOD-009), serving-basis checks.
- Multi-column labels (per serving / per container / prepared / unprepared)
  stay distinct until the user explicitly selects the basis.
- Review screen: captured image beside the values (tap to zoom), flagged
  low-confidence/ambiguous fields, every field correctable with immediate
  re-validation, explicit Create food / Save new version confirmation. A
  matching existing food is updated only as a NEW immutable version
  (FOOD-001); diary snapshots never change (REG-051 semantics).
- Degradation chain: Vision document path → DEVICE-002 line recognition →
  fully manual entry. Extraction failure, non-label images, model
  unavailability, or missing APIs never block food entry. Baseline OS is
  unchanged: below iOS 27 the existing DEVICE-002 sheet is used.
- On-device only: no label image or text leaves the phone on any path; no
  Private Cloud Compute or cloud model is referenced.

**Files changed:**
- `docs/PRD.md` (DEVICE-007 + acceptance criteria, S21-S23),
  `docs/ACCEPTANCE_MATRIX.md` (DEVICE-007 row).
- `packages/WellnessCore`: `Food/StructuredLabel.swift` (schema + DEVICE-002
  bridge), `Food/LabelDraftValidator.swift` (deterministic gate + FoodVersion
  snapshot builder), `Food/LabelRowParser.swift` (deterministic row/serving/
  barcode-row parsing used by the Vision reader),
  `Tests/WellnessCoreTests/StructuredLabelTests.swift`.
- `apps/ios/NimaWellness`: `Infrastructure/Vision/StructuredLabelExtractor.swift`
  (extractor protocol, iOS 27 `RecognizeDocumentsRequest` reader, line-parser
  fallback, optional Foundation Models interpreter compiled out behind
  `NIMA_FM_IMAGE_LABELS`), `Features/Scanner/EnhancedLabelCaptureSheet.swift`
  (DEVICE-007 review UI), routing in `ChatView`, `nextUserFoodVersionID` and
  latest-version resolution in `AppModel`, `XCODE_SETUP.md` P2 section.

**Behavior demonstrated:** requirements-pack validation
(`python3 tools/validate_requirements.py`) passes with the new requirement
integrated.

**Tests executed with commands and outcomes:**
- `python3 tools/validate_requirements.py` → all pack checks PASS (DEVICE-007
  present exactly once in PRD and matrix; fences balanced; bibliography
  superset intact).

**Tests not run and why:**
- `swift test --package-path packages/WellnessCore` — NOT RUN (no Swift
  toolchain in this environment). `StructuredLabelTests` encodes the
  pure-domain DEVICE-007 acceptance scenarios: clean single-column label;
  per-serving vs per-container distinctness; absolute + %DV on one row with
  %DV never substituted; missing/unsupported nutrients staying unknown;
  conflicting (blurred/duplicate) readings blocking until corrected;
  not-a-label rejection; implausible-value bounds; arithmetic flags without
  rewrites; correction-before-commit; rescan-creates-new-version; line-parser
  fallback bridge; unmatched bilingual rows staying out; barcode carried only
  when checksum-valid.
- Image-in/extraction-accuracy evaluation (real label photos, blurred labels,
  bilingual panels, Vision recognition languages) and the model-unavailable
  fallback on hardware — BLOCKED BY ENVIRONMENT: needs the iOS 27 SDK and a
  device. Per DEVICE-007, extraction accuracy is recorded separately from
  commit correctness; only the commit-correctness half is encodable here.

**Device evidence, if actually collected:** none — nothing on-device is claimed.

**Remaining correctness/privacy/security risks:**
- The Vision `RecognizeDocumentsRequest`/`DocumentObservation` traversal is
  written against the announced API shape and must be verified on the real
  iOS 27 SDK (property names may differ); the semantic work is all in the
  SDK-independent `LabelRowParser`, so adjustments should be mechanical.
- The Foundation Models image-prompting interpreter ([S22-S23]) is compiled
  out by default because that SDK surface could not be verified from this
  environment. Enabling `NIMA_FM_IMAGE_LABELS` requires checking image
  prompting and the `OCRTool`/`BarcodeReaderTool` types against the SDK.
  This is the MAY portion of DEVICE-007; the MUST portions do not depend on it.
- The row parser is English-first; bilingual labels contribute only rows the
  keyword table recognizes (correctly conservative but low recall for other
  languages until keyword sets are extended).
- Micronutrient rows are stored verbatim with unit text; they are not yet
  normalized to canonical micronutrient IDs.

**Next slice:** verify on the Mac/iOS 27 SDK (adjust the Vision traversal,
optionally enable the FM flag), photograph the U01-U03 labels for the
extraction-accuracy record, then return to the M2 builder work or the M4
resolver, whichever the owner schedules.
