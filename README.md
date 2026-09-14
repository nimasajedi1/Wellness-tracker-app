# Nima Wellness — local-first tracker and nutrition assistant

Native iOS app per `docs/PRD.md`: a compact personal tracker with a
conversational nutrition log, a visual builder, deterministic goal/energy/food
math, and on-device-only model interpretation.

## Repository layout

| Path | Contents |
|---|---|
| `docs/` | PRD, implementation plan, legacy baseline, acceptance matrix, validation report |
| `fixtures/` | Seed evaluation cases, catalog fixtures, owner-template example |
| `tools/validate_requirements.py` | Requirements-pack consistency checker (`python3 tools/validate_requirements.py`) |
| `packages/WellnessCore/` | Pure Swift domain package: units, goals, energy, portions, recipes, meal ledger, interpreter contract, owner template, tests |
| `apps/ios/NimaWellness/` | SwiftUI app target sources + `project.yml` (XcodeGen) + `XCODE_SETUP.md` |

## Status

M0 scaffolding plus the M1 tracker slice and early M2/M3 slices, as code:

- **WellnessCore** (no SwiftUI/model/network dependencies, ARCH-001):
  goal evaluator with the owner's exact thresholds (130 g protein and 2 L water
  are exact green boundaries), owner exercise truth table, energy engine
  (Mifflin-St Jeor, no double counting, provisional balance), decimal portion
  engine (oz = 28.349523125 g), recipe/batch math, revision-based meal ledger
  with idempotent mutations and persisted Undo, configuration schema with
  cycle/reference validation, legacy v19 import with dedup, and the
  `NutritionInterpreter` contract with a deterministic mock.
- **App target**: Today dashboard (legacy palette, seven indicators, full-width
  calorie balance, AM/PM supplements, quick increments, exact-value editor),
  Chat (preview-first result cards, availability handling, cancellation),
  History (30-day strip with missing-day markers, revisions, adjustments),
  Builder (draft/save versions, reorder without drag, typed custom fields),
  Settings (opt-in energy profile, day completion), SwiftData persistence,
  and the explicit `SystemLanguageModel` adapter gated behind availability.

- **P1 features** (second commit): read-only HealthKit integration with
  per-type opt-in, exclusive source policies and idempotent imports; HealthKit
  and fixed-total energy methods; barcode scanning with GS1 checksum
  validation; label capture (on-device OCR + explicit review); hydration and
  status widgets plus Shortcuts quick actions through the same idempotent
  commands; local reminders with quiet hours; Busy workday and Travel day
  templates. See `docs/P1_HANDOFF.md`.

Not yet built (by design, per the milestone plan): web resolver and restaurant
adapters (M4), USDA catalog packs (M5), Developer Lab/beta evidence (M6).

## Building

See `apps/ios/NimaWellness/XCODE_SETUP.md`. Domain tests:

```bash
swift test --package-path packages/WellnessCore
```

Written and validated for structure in a Linux environment; Xcode build,
device inference, and UI acceptance require a Mac and the iPhone 16e
(TEST-012 — those results are recorded separately, never assumed).
