# Implementation plan: milestone-sized Codex work

**Authority:** `docs/PRD.md`. This plan sequences the requirements; it does not downgrade them. P0 is the complete personal beta, delivered incrementally through M0-M6. P1/P2 must not delay a useful core app.

## Working agreement

For each task, update the acceptance matrix with the actual test or manual procedure and execution result. Use small commits and preserve a runnable state. Record major architecture/API changes in `docs/decisions/`.

The requirements pack is not a compiled app. The included validation tool checks documents and fixtures only. Application test commands become executable only after the corresponding project/package/service is created.

## M0 - Environment and a real local-model spike

### Tasks

- **M0.1 Environment audit:** inspect available OS, Swift, Xcode, SDK, and device access. Confirm Mac access with the owner when unavailable. Write exact local setup steps rather than assuming an Apple developer account supplies a build machine.
- **M0.2 Repository scaffolding:** create a small iOS app/scheme, a pure `WellnessCore` Swift package, and an in-memory repository. Keep signing team configuration local.
- **M0.3 Typed interpreter boundary:** define `NutritionInterpreter`, availability states, interpretation request/result, and `MockInterpreter`. No nutrient arithmetic belongs in the interpreter.
- **M0.4 Explicit Apple adapter:** instantiate the on-device system model using APIs available on the selected baseline. Generate a small structured food mention, not free-form calorie advice.
- **M0.5 Availability UI:** show ready/unavailable/downloading-or-not-ready/unsupported/error as supported by the SDK, and provide a usable manual input path.
- **M0.6 Device smoke procedure:** run a request such as "112 g cooked pinto beans" on the physical 16e, then repeat with networking disabled after model provisioning. Capture actual interpretation and timings locally.
- **M0.7 Test reporting:** distinguish domain/mock tests from physical model tests. Record blockers precisely.

### Exit gate

Real app project exists; appropriate build passes on a Mac; unavailable model does not break manual input; one real-device structured interpretation is validated. When the environment cannot run these checks, mark the gate blocked rather than complete. Domain scaffolding may proceed while the owner performs the device test, but the thesis is not validated by a mock.

### Codex prompt

```text
Implement M0 only. Read the PRD's platform, architecture, and chat contracts.
Inspect the environment first. Keep Apple APIs behind an adapter and add a mock.
Do not implement a web resolver, large catalog, HealthKit, or a general chat bot.
Report exact build/test evidence and the physical iPhone setup steps.
```

## M1 - Deterministic tracker and owner template

### Tasks

- **M1.1 Domain value types:** canonical units, typed observations, explicit missingness, log-day/date context, revision IDs, and data-source metadata.
- **M1.2 Goal evaluator:** minimum, maximum, range, exact/tolerance, completion, trend-only, ALL/ANY composite, and owner exercise rule. Test inclusive boundaries and invalid configurations.
- **M1.3 Energy engine:** configurable resting estimate/formula, known versus unknown active energy, exclusive source selection, net calculation, provisional status, and goal modes.
- **M1.4 Data-driven owner template:** fields, goal/display bounds, quick-add steps, schedules, categories, and layout are data. Do not embed per-field business rules in SwiftUI views.
- **M1.5 Local storage:** SwiftData adapter, atomic mutations, projections, error states, relaunch persistence, and schema versioning.
- **M1.6 Today UI:** recognizable legacy palette, compact summary, expanded editing, AM/PM toggles, full-width balance indicator, exact-value editor, and light/dark mode.
- **M1.7 History/date behavior:** chosen day, fresh-day view without data deletion, prior-day values, in-progress intervals, daylight saving, and travel-safe attribution.
- **M1.8 Reset and Undo:** date-scoped confirmation, reversible reset, no deletion of configuration/favorites/other days.
- **M1.9 Baseline accessibility:** effective 44-point touch targets, noncolor status, VoiceOver labels, and Dynamic Type reflow.

### Tests

REG-001 through REG-017, REG-033 through REG-038 as supported by the slice, REG-049, REG-054 through REG-056. Add goal boundary/property tests. A custom maximum must not inherit the owner's minimum-goal overshoot behavior.

### Exit gate

The tracker functions offline without the model or backend. Exact 130 g protein and 2 L water boundaries are implemented, with explicit owner tolerances for the other fields. All seven default indicators are visible in compact mode; balance stays full-width for every state. Direct edits persist and have auditable Undo.

## M2 - Visual builder, not just settings

### Tasks

- **M2.1 Configuration schema:** field registry, category registry, value types, units, aggregation, inputs, goal definitions, schedules, layout cards, dependencies, and versions.
- **M2.2 Template library:** Owner, Minimal, Busy workday, Travel, Blank. Template selection changes configuration, not the underlying fact stream.
- **M2.3 Builder UI:** field/category library, live phone preview, field/card inspector; iPhone-friendly sheets/segments.
- **M2.4 Visual editing:** reorder, half/full width, grouping, labels, pinning, hide/archive, accessible move controls, draft Undo/Redo.
- **M2.5 Goal editing:** minimum/maximum/range/completion/trend rules, visible thresholds and tolerances, optional group membership, editable quick increments.
- **M2.6 Preview scenarios:** empty/partial/met/outside/custom values using the production evaluator.
- **M2.7 Publish/version:** Save/Cancel, effective date, past-day preservation, template switching, dependencies/cycle rejection.
- **M2.8 Import/export:** configuration only, schema/size validation, preview, duplicate/reference checks, atomic failure handling.

### Tests

Create caffeine with a user-defined maximum; create stretch-break count; create an unscored energy rating; remove fasting from view; move hydration; resize a card; change water threshold; relaunch; inspect yesterday. Inject a cyclic import and invalid units. Perform the same workflow without drag gestures.

### Exit gate

All of the above occurs without editing code or raw JSON. No migration is needed merely to enable sodium, caffeine, or a custom count field. Changes do not delete history or create duplicate food/water events.

### Codex prompt

```text
Implement M2 against the existing metric/goal registry. Build the visual library,
preview, inspector, layout controls, and versioned Save/Cancel flow. Use the same
goal evaluator as Today. Add UI tests for custom caffeine, hidden fasting,
reordered hydration, exact water thresholds, and preserved historical status.
Do not turn this into a static hardcoded goals form.
```

## M3 - Source-backed local nutrition and safe chat

### Tasks

- **M3.1 Food contracts:** versioned food identities, source evidence, portions, nullable nutrients, cooked/raw/drained states, market, and source match quality.
- **M3.2 Calculator:** decimal unit conversion, per-basis scaling, named servings, conservative volume mapping, recipe/batch yields, display rounding, and incomplete nutrient coverage.
- **M3.3 Seed catalog/search:** create a small sourced production catalog plus separate synthetic test fixtures; add exact/lexical lookup and private aliases.
- **M3.4 Meal ledger:** draft/planned/committed states, revision targeting, idempotent commands, atomic edits, persisted Undo, and daily projection rebuild.
- **M3.5 Chat presentation:** composer, result cards, source details, portion review, clarification chips, deterministic totals, Add/Edit/Undo, and date context.
- **M3.6 Local interpretation:** bounded schemas/tools, saved-food retrieval, correction reference resolution, plans versus consumption, explicit quantity ambiguity, and refusal/error fallback.
- **M3.7 Manual totals:** auditable adjustments for direct daily total edits; never maintain unrelated dashboard and chat totals.
- **M3.8 Evaluation runner:** start with supplied seed cases and expand to at least 100; record prompt/app/OS/schema versions and actual outputs.
- **M3.9 Offline proof:** cold-launch app with network disabled and log a known meal, adjust water, revise a meal, and inspect history.

### Tests

REG-018 through REG-034, REG-040 through REG-042, REG-045 through REG-046, REG-050 through REG-053. Tests must include a mislabeled fat variant, 29 g tuna ambiguity, exact four-ounce conversion, unknown fiber, cooked/dry pasta, and a discarded oatmeal draft.

### Exit gate

No nutrient fact originates from free-form model text. Confirmed known foods update the shared tracker correctly; questions/plans do not. Corrections replace rather than duplicate; retries are idempotent; manual operations work when the model is unavailable.

## M4 - Optional direct-web resolver with explicit coverage

### Tasks

- **M4.1 Service boundary:** versioned OpenAPI contract, normalized food query only, read-only responses, error vocabulary, installation access/rate limiting, and no personal diary upload.
- **M4.2 Source registry:** research current public official sources, market and portion coverage, source policy, parser type, refresh/reuse rules. Do not mark a desired source as supported before inspecting it.
- **M4.3 Safe fetcher:** approved HTTPS hosts/paths, redirect/address validation, SSRF defenses, size/time/decompression limits, no authentication scraping.
- **M4.4 Adapters:** implement real deterministic adapters for at least three restaurants and two brands or reviewed replacements. Preserve per-field basis/evidence.
- **M4.5 Cache and provenance:** canonical lookup keys, source versions, stale/blocked states, conditional requests, simultaneous miss coalescing, and no global publication of private recipes.
- **M4.6 App integration:** explicit network consent, online status, candidate review, selected-source detail, cancellation, retry-safe draft retention.
- **M4.7 Source regression tests:** static fixtures and changed-layout cases; separate opt-in live smoke tests. Quarantine suspicious extractions.
- **M4.8 Operational docs:** container, locked dependencies, example environment, initial registry seeding, refresh jobs, recovery, and cost counters.

### Tests

REG-029, REG-040 through REG-047, REG-050 through REG-053. Adversarial page text cannot invoke personal tools or write state. Unknown portions/countries never become a confident exact match. Repeated cached lookups cause no new source fetch.

### Exit gate

A real named brand/restaurant resolves without a label photo, shows a legitimate source and portion basis, and then works from local cache offline. Default paid-provider/discovery and cloud-inference counts are zero. Unsupported sources fail honestly.

### Codex prompt

```text
Implement the optional M4 resolver. Begin with a reviewed source registry and
safe deterministic adapters, not an autonomous browser agent. Keep all personal
history and model inference on-device. Every numeric result needs evidence and
a serving basis. Paid search/nutrition APIs remain disabled. Add source-format,
SSRF, prompt-injection, cache, stale-data, and wrong-market tests.
```

## M5 - Reproducible catalog ingestion and growth

### Tasks

- **M5.1 USDA importer:** support the selected releases/data types, typed nutrient-ID mapping, serving records, raw/cooked differences, and source provenance.
- **M5.2 Canonical identity:** preserve external IDs/versions, conservative product grouping, discontinued entries, and market-specific formulations.
- **M5.3 Search packaging:** build SQLite indexes/FTS, test representative queries, report exact size/row counts/index overhead.
- **M5.4 Local core pack:** select useful generic foods and documented brand/restaurant subset. Do not bundle all branded records by default.
- **M5.5 Distribution protocol:** manifests, checksums, size consent, temporary download, compatibility validation, atomic activation, rollback, and eviction independent of personal data.
- **M5.6 Catalog history:** preserve committed meal versions despite pack refresh/deletion; public source updates never rewrite the personal diary.
- **M5.7 Coverage report:** track restaurant/brand coverage honestly by market/item/portion; a hundred restaurants remains a staged target.

### Exit gate

Importer and pack generation are repeatable. Published storage/performance numbers come from the actual artifact. Update interruption leaves the old pack and diary usable. No provider key is shipped in the app.

## M6 - Personal beta and measured refinement

### Tasks

- **M6.1 Complete evaluation set:** at least 250 cases, held-out partition, ambiguity/abstention accounting, requirement traceability, critical-invariant gate.
- **M6.2 Developer Lab:** select prompt versions/suites, inspect structured failures, export selected redacted traces, record OS/model readiness and latency.
- **M6.3 Accessibility/security/privacy review:** noncolor statuses, large text, accessible builder, deletion/export, production logs, permission usage, disabled synthetic data, source reuse register.
- **M6.4 Legacy migration:** user-initiated export/import, explicit missing zeros, known fields, deduplication, no invented historical recovery.
- **M6.5 Physical device pilot:** seven consecutive days of personal logging; record exact clear/supported attempt denominators, corrections, source misses, latencies, and costs.
- **M6.6 Release candidate:** distribution instructions, change log, limitations, support coverage, known issues, and actual pass/fail report.

### Exit gate

All P0 acceptance evidence is recorded; unresolved critical failures block release. Prototype success does not imply full restaurant coverage, clinically accurate expenditure, or future model perfection.

## Deferred scope and approval rules

P1: HealthKit read integration, dedicated voice, barcode/OCR, widgets, scheduled reminders, more source adapters, optional larger offline packs. Each needs its own explicit permission, privacy, deduplication, and testing work.

P2: additional local models, Android/web parity, inventory/loyalty integrations, richer planning, and separately reviewed synchronization. Do not add these opportunistically during a P0 bug fix.

## Required handoff format

```text
Milestone / slice:
Requirements addressed:
Files changed:
Behavior demonstrated:
Tests executed with commands and outcomes:
Tests not run and why:
Device evidence, if actually collected:
Remaining correctness/privacy/security risks:
Next slice:
```

## Next action

Start at M0. The immediate question is whether the actual device/environment produces useful structured local interpretation while manual functionality remains independent. The visual builder then grows from the same typed tracker domain rather than becoming a separate incompatible subsystem.
