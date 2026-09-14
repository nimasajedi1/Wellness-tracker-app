# Handoff: P1 feature slice

**Milestone / slice:** P1 — HealthKit read integration, HealthKit/fixed-total
energy methods, barcode scanning, label capture (OCR + review), widgets and
Shortcuts quick actions, local reminders, and the remaining starter templates
(Busy workday, Travel day). Built on the P0 codebase from the previous commit.

**Requirements addressed (implemented in code; device acceptance pending):**
- HEALTH-001 just-in-time per-type permission with stated purposes;
  HEALTH-002 honest no-data states (denied reads never claimed);
  HEALTH-003 statistics-based dedup, stable external sample IDs, exclusive
  per-metric source policies, idempotent reimports;
  HEALTH-004/ENERGY-005 no double-counted workout/active energy;
  HEALTH-005 asleep-only sleep import with union aggregation;
  HEALTH-006 read-only (no HealthKit writes anywhere);
  HEALTH-007 disconnect stops imports, never deletes health-store data.
- ENERGY-003 HealthKit energy method (no formula added to sampled resting;
  partial-day never final); ENERGY-004 fixed daily total (active shown, not
  added unless explicitly additional).
- DEVICE-001 barcode: VisionKit scanning + manual digits, GS1 checksum
  validation, catalog-only resolution, honest not-found fallback.
- DEVICE-002 label capture: on-device Vision OCR → deterministic parser →
  explicit review form; absent fields stay unknown; saved food is evidence-
  labeled userEnteredLabel; nothing auto-commits.
- DEVICE-003 widgets/Shortcuts: hydration and status widgets from a coarse
  snapshot (no sensitive lock-screen detail), interactive +250 mL via App
  Intents through the same commands/idempotence, favorites with saved
  portions (FOOD-014); unresolvable favorites refuse rather than guess.
- DEVICE-004 reminders: user-created only, explicit permission on first
  enable, quiet hours (shift to window end), neutral wording, "delivered ≠
  done".
- BUILD-001 all five template entry points now exist and validate; templates
  remain views over canonical metric IDs (BUILD-013).
- DEVICE-005: intentionally NOT built as a dedicated feature — P0/P1 use
  typed input and the system keyboard's dictation, per the PRD's default.

**Files changed:**
- `packages/WellnessCore`: `Energy/ExpenditureMethod.swift`,
  `Health/HealthImport.swift`, `Reminders/ReminderRule.swift`,
  `Food/LabelTranscription.swift`, `Food/Barcode.swift`, barcode lookup in
  `Repositories.swift`, new templates in `OwnerTemplate.swift`, plus
  `Tests/WellnessCoreTests/P1FeatureTests.swift` (expenditure methods, health
  import mapping, reminder scheduling/quiet hours, label parsing, GTIN
  validation and lookup, template validation).
- `apps/ios/NimaWellness`: `Infrastructure/HealthKit/HealthKitService.swift`,
  `Infrastructure/Reminders/ReminderService.swift`,
  `Infrastructure/Persistence/PersistenceFactory.swift` (+ shared/app-group
  container), persistence v2 (externalSampleID column, user foods, aliases),
  `Infrastructure/Shared/WidgetSnapshot.swift`,
  `AppIntents/QuickActionIntents.swift`,
  `Features/Scanner/{BarcodeScannerView,LabelCaptureView}.swift`,
  Health/Reminders settings views, energy-method picker in Settings, chat
  scanner entry points + Save favorite, Builder template menu, entitlements,
  `project.yml` with the widget extension target.
- `apps/ios/NimaWellnessWidgets/`: widget bundle (hydration + status).

**Behavior demonstrated:** requirements-pack validation only
(`python3 tools/validate_requirements.py` → 45/45 PASS, unchanged).

**Tests executed with commands and outcomes:**
- `python3 tools/validate_requirements.py` → 45/45 PASS.

**Tests not run and why:**
- `swift test --package-path packages/WellnessCore` — NOT RUN: no Swift
  toolchain in this Linux environment (swift.org blocked by network policy).
- Xcode build, HealthKit/permission flows, widget/intent execution, physical
  scanning — BLOCKED BY ENVIRONMENT (TEST-012): Mac/Xcode/iPhone required.

**Device evidence, if actually collected:** none — nothing on-device is claimed.

**Remaining correctness/privacy/security risks:**
- All Swift remains compiler-unverified; HealthKit/VisionKit/AppIntents API
  surfaces are the most likely to need small signature fixes on first build.
- The app-group store move (existing install → group container) is documented
  but not automated; reinstall is the simple path during personal testing.
- Health import runs on demand for the selected day (no background delivery);
  same-day HealthKit energy is correctly provisional but the "covers full
  day" heuristic is day-passed-based, not sample-coverage-based.
- Reminder settings and P1 preferences live in UserDefaults pending the M2
  versioned-config store.
- P1 items deliberately deferred to the M4/M5 backend: additional restaurant
  adapters, offline packs, delta catalog updates (CAT-017/018, LOOKUP-023).

**Next slice:** run `swift test` + first build on the Mac, fix compiler
findings, walk the HealthKit permission/import flow and widget setup on the
16e, then continue the M2 builder work (preview scenarios, import/export UI).
