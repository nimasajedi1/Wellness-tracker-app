# Nima Wellness: Local-First Tracker and Nutrition Assistant

**Product requirements document and coding specification**  
**Version:** 1.0  
**Prepared:** 2026-09-13  
**Primary test device:** Owner's iPhone 16e  
**Delivery:** Native iOS application, local inference, optional self-hosted nutrition resolver  
**Reference interface:** Nima Wellness Tracker, `nima-wellness-tracker-calorie-balance-v19.html`  
**Audience:** Product owner, Codex, iOS developer, backend developer, tester

> Build a useful personal application in small, testable increments. Keep the existing tracker recognizable, add a conversational nutrition log, and make the dashboard and goals configurable through a visual builder. The model interprets requests; verified records and deterministic code calculate and store results. No cloud language model or paid nutrition provider is required.

## Document conventions

- **MUST** is a release requirement for its assigned milestone. **SHOULD** allows a documented exception. **MAY** is optional.
- **P0** means required for the first complete personal beta, not necessarily for the first development commit. **P1** follows that beta. **P2** is explicitly deferred.
- Acceptance criteria are normative. Where old tracker code disagrees with an explicit rule below, this PRD controls.
- Numeric performance, storage, coverage, and accuracy targets are engineering targets to measure, not existing benchmarks or guarantees.
- Nutrient values in examples and fixtures are either explicitly identified label transcriptions or synthetic test data. Previous conversational estimates are NOT a verified nutrition catalog.
- Source identifiers such as **[S01]** refer to the references at the end. **[L01]** identifies the inspected legacy tracker file.
- This is a specification, not a built application. No Xcode build, device inference benchmark, restaurant parser, or App Store approval is represented as completed.

## Contents

1. Product objective and success definition
2. Decisions, assumptions, and non-goals
3. Scope and delivery milestones
4. User journeys
5. Application architecture and platform requirements
6. Front-end and interaction specification
7. Visual tracker builder and category catalog
8. Goal evaluation and status rules
9. Calories, resting energy, and activity accounting
10. Food records, portions, recipes, and nutritional arithmetic
11. Chat, local model, and mutation safety
12. Direct-web nutrition lookup and source quality
13. Catalog storage, ingestion, caching, and updates
14. Persistence, history, migration, and domain contracts
15. Backend API contracts
16. HealthKit and optional device features
17. Privacy, safety, security, and accessibility
18. Evaluation and acceptance-test plan
19. Performance, operational budgets, and diagnostics
20. Coding sequence and definition of done
21. Risks and decisions to revisit
22. Reference configuration and calculation examples
23. Sources and implementation references

---

## 1. Product objective and success definition

### 1.1 Problem

The existing compact tracker is convenient but its fields and goals are hardcoded. Conversational food logging is flexible but can confuse planned and consumed meals, misinterpret quantities, reuse the wrong product, invent a nutrient value, or change totals without an auditable reason. Repeated online lookups also create unnecessary cost and latency.

The product must combine the speed of a one-screen personal tracker with a persistent, source-backed nutrition ledger. It must be useful without a camera, without a subscription nutrition API, and without uploading the user's conversation to a hosted model.

### 1.2 Target users

The primary user is the owner, who already has an Apple developer account, an iPhone 16e for testing, and an existing web tracker. Secondary users are busy adults who want a small number of relevant indicators rather than a comprehensive medical dashboard. Typical contexts include commuting, restaurant meals, quick grocery-product searches, desk work, family routines, and travel.

Personal preferences must be templates, not assumptions about every user. The owner template includes protein, fiber, hydration, steps, exercise, sleep, optional fasting, supplements, and an estimated calorie balance. Other users can remove any category, hide calories, or track different fields entirely.

### 1.3 Product outcomes

**OUT-001 [P0] Daily usability.** A user can record a known food or a common tracker observation without opening multiple settings screens.

Acceptance:
- A favorite meal requires at most two taps from the dashboard.
- A water increment requires one tap after the hydration quick action is visible.
- A clear text food entry produces a reviewable result and an immediate dashboard update after confirmation.
- Dashboard, chat, and history display the same totals from the same records.

**OUT-002 [P0] Local-first operation.** Existing data, goals, favorite foods, daily history, calculations, and supported local interpretation work without internet after setup.

Acceptance:
- Airplane mode does not prevent viewing or editing the tracker.
- A cached food can be logged offline.
- An uncached restaurant item produces a clear lookup-unavailable state, not invented nutrition.
- No inference request leaves the device in any P0 workflow.

**OUT-003 [P0] Testable improvement.** Every substantive correction can become a regression case.

Acceptance:
- Debug builds can export a selected, redacted interaction with expected behavior.
- Prompt version, app version, OS version, model availability, catalog version, and timings are recorded with evaluation results.
- A failed evaluation blocks promotion of that prompt/configuration when it violates a critical invariant.

**OUT-004 [P0] Configurability without code.** Field selection, goal amounts, units, thresholds, category membership, and layout can be changed in the app.

Acceptance:
- A user can add a caffeine field, configure a personal limit, move it, save, and relaunch without editing Swift or JSON.
- A field can be tracked without having any goal or red/green judgment.

---

## 2. Decisions, assumptions, and non-goals

### 2.1 Adopted implementation decisions

| Decision | Specification |
|---|---|
| Front end | Native SwiftUI, preserving the existing tracker's visual language and behaviors where specified. |
| Deployment baseline | iOS 26.0 or later; verify all used APIs against the installed SDK. Do not require newer/beta-only APIs. |
| Local model | Explicit `SystemLanguageModel` through Apple's Foundation Models framework. Never silently select a cloud-capable provider. |
| Model responsibility | Intent, food/quantity interpretation, bounded entity selection, clarification selection, and optional nonnumeric phrasing. |
| Fact/calculation responsibility | Source adapters, normalized catalog records, unit engine, recipe engine, and deterministic reducers. |
| Personal storage | Local SwiftData store behind repository protocols; no automatic cloud sync in P0. |
| Catalog storage | Separate read-only/versioned SQLite catalog, with local search and a private writable cache. |
| Resolver backend | Small Python service, proposed FastAPI with a SQLite/FTS catalog for a single-instance personal deployment; replaceable repository interfaces. |
| Discovery | Known official source registry first; paid search and paid nutrition APIs disabled by default. |
| Test strategy | Pure-domain tests, parser fixtures, UI tests, and on-device local-model evaluations. |
| Initial market/language | English UI; US food catalog by default; explicit US/Canada market distinction. |
| Public account | Not required for the personal beta. |

Apple documents the Foundation Models baseline, structured generation, tool calling, and on-device model availability. Hardware compatibility alone is insufficient: the app must handle disabled, unavailable, or not-yet-ready models. [S01-S05]

### 2.2 Assumptions to validate, not hardcode

1. The owner has access to a Mac capable of running a suitable Xcode version. Apple developer enrollment and an iPhone alone do not establish the full native development environment. Device deployment is a Mac/Xcode task. [S08]
2. Apple Intelligence can be enabled on the test device in its configured language and region. The system model may require an initial download. [S02-S03]
3. The owner accepts a native port of the existing front end. This PRD does not require a simultaneous React/PWA rewrite or replacement of the public website.
4. The saved v19 file is the design and behavior reference. The live domain was not successfully inspected during preparation; the saved file and documented owner choices are the baseline. [L01]
5. A small set of official brand/restaurant sources is enough for the first real-world test. One hundred restaurants is a later coverage target, not a prerequisite for the first app launch.
6. "Refining the local model" initially means better schemas, retrieval, aliases, prompts, and evaluations. It does not imply on-device training or that Apple's system-model weights can be pinned or freely modified. Model behavior can change with OS releases. [S06]

### 2.3 Explicit non-goals for P0

- Automatic household-inventory depletion, retailer loyalty integrations, receipt ingestion, and purchasing.
- Unconstrained web browsing, account scraping, CAPTCHA bypass, or arbitrary agent execution.
- Cloud LLM fallback, paid nutrition subscriptions, or general search-engine scraping.
- Guaranteed calorie measurement from a photograph, automatic food volume estimation, or custom scale hardware.
- Diagnosis, treatment, medication dosing, clinical decision support, or automated medical interpretations.
- Automatic weight-loss target prescription or a claim that lower intake is always better.
- A fully offline copy of every branded product and all historical USDA versions.
- Social feeds, advertisements, leaderboards, subscriptions, and cross-device sync.
- Open-ended "ask anything" chatbot behavior.

The data model should allow later inventory linkage through a stable product identity, but do not build the inventory product now.

---

## 3. Scope and delivery milestones

| Milestone | Deliverable | Gate |
|---|---|---|
| M0: Feasibility | Minimal app, explicit local-model availability, structured interpretation spike, mocks, baseline tests. | Real iPhone 16e executes one validated extraction with network disabled. |
| M1: Tracker | Native dashboard, local persistence, daily history, exact goal evaluator, theme, owner template. | Dashboard and calculation tests pass without any model or backend. |
| M2: Builder | Editable fields, goal rules, category catalog, live preview, template versioning. | A new tracker can be built and restored entirely offline. |
| M3: Nutrition chat | Local interpreter, known foods, aliases, recipes, consumed/planned distinction, correction/undo. | Critical conversational regression suite passes with no fabricated facts. |
| M4: Web resolver | Hosted catalog, initial official-source adapters, bounded direct retrieval, provenance, cache. | Real official-source lookup and repeat offline lookup both pass. |
| M5: Catalog growth | Reproducible USDA import, downloadable packs, source manifests, measured storage. | Interrupted update is safe and historical meal values remain unchanged. |
| M6: Personal beta | Device evaluations, accessibility, export/deletion, privacy controls, release build. | Seven-day owner trial and P0 release checklist. |
| P1 | HealthKit read integration, barcode/label fallback, widgets, local reminders, additional templates and restaurant adapters. | Separate integration gates. |
| P2 | Alternative local models, optional sync, web parity, richer recommendations, inventory integrations. | New design decision and evidence of demand. |

**SCOPE-001 [P0]** Codex MUST implement one milestone at a time and leave the project runnable. Do not replace a working local tracker with an unfinished universal agent.

**SCOPE-002 [P0]** Disabled or deferred functionality MUST be labeled or absent. A mocked lookup must never be shown as a live verified source.

**SCOPE-003 [P0]** Requirements needed for builder extensibility are P0 even when a particular data source, such as HealthKit, is P1.

---

## 4. User journeys

### Journey A: First launch

Choose "Use my existing tracker," "Build my tracker," or "Start minimal." Review selected categories, choose units and food market, and finish without giving permissions. The app opens a working empty dashboard. Local-model status is shown separately and never blocks manual use.

### Journey B: Known food

User enters "112 g of my ham." The app resolves the saved alias to a specific food version, calculates the portion, previews calories/protein/fiber, and records it after confirmation. Next time the same food resolves locally.

### Journey C: Restaurant without a label

User enters a restaurant, menu item, and size. The resolver checks local and hosted catalogs, then a registered official source. The app shows the exact market and portion, retrieval date, and source. Ambiguous variants are presented as choices. An unsupported source results in "Not verified," not a guess disguised as a lookup.

### Journey D: Correction rather than addition

User says "No lentils, just 100 g beans." The app identifies the meal being corrected, previews the removed lentils and replaced bean quantity, and commits one atomic revision. The day does not count both the original and corrected dinner.

### Journey E: Visual customization

User opens Builder, removes fasting, adds caffeine and stretch breaks, sets a personal caffeine maximum and a stretch-break count, moves the cards, and previews the result at the phone's actual size. Save creates a new effective configuration without deleting old logs.

### Journey F: On-the-go degraded connectivity

A favorite meal works in airplane mode. An unfamiliar product is kept as a draft with its text and proposed quantity. Reconnecting can resume lookup, but cannot automatically turn a previously hypothetical meal into consumed food.

### Journey G: Personal testing

Owner enables Developer Lab, runs a curated evaluation set on the physical phone, compares prompt versions, and exports failures. The app makes no claim that a newer prompt is better until results support it.

---

## 5. Application architecture and platform requirements

### 5.1 Components

```text
SwiftUI: Today / Chat / History / Builder
                   |
          Application services
                   |
      Validated commands and queries
         /           |            \
  Tracker engine  Nutrition engine  Local interpreter
         |           |                 |
     Goal rules   Food resolver   Apple system model
         |           |
 Personal local DB   +--> Private aliases and cache
                     +--> Device catalog (SQLite)
                     +--> Optional hosted resolver
                                  |
                            Hosted catalog
                                  |
                       Official source adapters
```

**ARCH-001 [P0] Pure domain boundary.** Goal calculations, unit conversions, nutrient scaling, meal revisions, day attribution, and recipe math MUST be testable without SwiftUI, Foundation Models, HealthKit, or network access.

Acceptance: domain tests run with in-memory repositories; no model call is required to calculate any total.

**ARCH-002 [P0] Model abstraction.** Define an application-owned `NutritionInterpreter` protocol with Apple-system, deterministic/mocked, and future-provider implementations. Do not couple repositories or views to model-session types.

Acceptance: switch to `MockInterpreter` and run the full UI suite; manual lookup remains functional when `AppleInterpreter` reports unavailable.

**ARCH-003 [P0] Explicit local provider.** Instantiate and configure the on-device model explicitly. No automatic cloud routing, Private Cloud Compute, or third-party model provider may be used in P0.

Acceptance: dependency/configuration inspection and network tests find no model API credentials, remote inference endpoints, or cloud-provider initialization.

**ARCH-004 [P0] Availability and failure states.** Handle ready, unsupported device, disabled Intelligence, model download/not ready, unsupported locale, generation error/refusal, cancellation, and resource pressure. Use the actual SDK's public availability cases; retain an unknown-case fallback.

Acceptance: injected failure states produce actionable UI and preserve unsaved text. They never create a food entry.

**ARCH-005 [P0] Bounded execution.** Use one foreground interpretation operation at a time, cancellable by the user. Apply explicit time and tool budgets. Do not run a persistent background model agent.

Acceptance: rapid repeated sends are queued or rejected visibly, not executed as duplicate writes; leaving the screen cancels safely or leaves a resumable draft.

### 5.2 Recommended repository layout

```text
AGENTS.md
README.md
docs/
  PRD.md
  IMPLEMENTATION_PLAN.md
  LEGACY_BASELINE.md
  decisions/
apps/ios/NimaWellness/
  App/
  Features/Today/
  Features/Chat/
  Features/History/
  Features/Builder/
  Features/Settings/
  Features/DeveloperLab/
  Infrastructure/Persistence/
  Infrastructure/FoundationModels/
  Infrastructure/Networking/
  Resources/Prompts/
  Resources/Templates/
packages/WellnessCore/
  Sources/
  Tests/
services/nutrition-resolver/
  app/
  adapters/
  migrations/
  tests/
tools/catalog-import/
fixtures/
  evaluation_cases.json
  parser_sources/
  catalog/
```

This is a target layout, not a claim these application directories already exist. Build M0 with the smallest useful subset. The supplied requirements pack contains documents and seed fixtures only.

### 5.3 Native versus existing web tracker

**ARCH-006 [P0] Native port, not a remote page wrapper.** Recreate the tracker's UI with native controls and a shared domain state. Existing HTML is a reference, not the live state store for the native app.

Acceptance: a web outage does not affect the tracker. There is no dependency on a hosted HTML page to access Foundation Models.

**ARCH-007 [P2] Web parity boundary.** A future Cloudflare-hosted web tracker may share exported configuration and API contracts, but cannot be assumed to have native Foundation Models access. Its manual/cached capabilities must remain explicit.

---

## 6. Front-end and interaction specification

### 6.1 Navigation

Use four primary destinations: **Today**, **Chat**, **History**, **Builder**. Settings and Developer Lab are accessible from the header/menu. All destinations share the selected tracker; Today and History make the selected date explicit.

**UI-001 [P0] No sign-in wall.** First launch works locally. Permissions, optional resolver access, and model setup are requested only when needed.

**UI-002 [P0] Shared state.** A successful chat mutation updates Today and History immediately without manual refresh. A direct dashboard edit is reflected in the next chat summary.

**UI-003 [P0] Preserve state.** Switching tabs, backgrounding, force-quitting after a completed save, or changing theme cannot lose logged observations or committed meals.

### 6.2 Visual baseline

Preserve the v19 interface's light blue/white cards, dark navy theme, rounded borders, clear numeric values, compact spacing, blue goal hints, and separate success indicators. The original uses these principal color tokens: [L01]

| Token | Light | Dark |
|---|---|---|
| Background | `#f7fbff` | `#071522` |
| Card | `#ffffff` | `#0b1d2d` |
| Text | `#10233d` | `#f4f8fc` |
| Secondary text | `#6f7f92` | `#9eb0c3` |
| Accent | `#2f80ed` | `#3b9cff` |
| Border | `#dbe8f5` | `#223b52` |

Semantic status colors MUST also have text/icon equivalents. Adjust token contrast where required; exact pixel replication is less important than legibility and correct behavior.

**UI-004 [P0] Compact and expanded modes.** The default compact dashboard prioritizes summaries and quick actions; detailed time fields and larger editors open in sheets or expanded cards. Offer an expanded list mode resembling the legacy tracker.

Acceptance:
- The default owner summary, all seven indicators, and primary navigation are visible without horizontal scrolling on the iPhone 16e at default text size.
- Do not force every editor into that one screen; detailed controls may expand or scroll.
- At large accessibility text sizes, allow vertical scrolling rather than shrinking text or clipping controls.
- Verify screenshots on 390 x 844 and a larger phone-size simulator; physical-device acceptance uses actual safe areas.

### 6.3 Today screen

```text
Nima Wellness             Date      Theme / Settings

Sleep & fasting       Nutrition
8 h / 8 h             Protein 120 / 140-150 g
Fast 15 h / 16 h      Fiber 24 / 35 g
                      Calories 1,850 / 2,000-2,200

Hydration             Activity
1.75 / 2-2.5 L        Steps 7,500 / 7,500-10,000
[+250 mL]             Workout [Done]
                      Active kcal / Out / Net

Supplements [AM] [PM]       [+ Log food]

[Sleep]       [Fasting]     [Nutrition]
[Hydration]   [Exercise]    [Supplements]
[             Calorie balance              ]

Today          Chat          History          Builder
```

This is a structural wireframe, not fixed pixel positioning. Builder changes may move or remove cards.

**UI-005 [P0] Seven owner indicators.** Sleep, fasting, nutrition, hydration, exercise, supplements, and calorie balance MUST be available in the owner template. Calorie balance spans the entire final status row in every state, including gray, yellow, red, and green.

**UI-006 [P0] Values and controls.** Support direct numeric editing as well as configurable increments. Owner defaults: protein 10 g, water 250 mL, fiber 5 g, intake 100 kcal, steps 500, active energy 50 kcal. Precise food-derived totals are not rounded to those increments.

**UI-007 [P0] Supplement controls.** Use "Supplements," not "pills," in user-facing labels. AM and PM buttons toggle independently, persist, and always trigger status recalculation. No prefilled drug names or dosing recommendations.

**UI-008 [P0] Activity alignment.** Steps and active-energy values align visually. Display only **Out** and **Net** below active energy in the compact owner layout; do not duplicate an extra **In** value there. The full calculation is available in details.

**UI-009 [P0] Dates and duration.** Sleep/fast start labels display the actual start date, abbreviated weekday and `MM/DD`, when it differs from the selected day. Show computed duration as hours and minutes. Never label a same-day start as yesterday merely to mimic old HTML.

**UI-010 [P0] Save state and reset.** Show Saved/Saving/Error truthfully. Reset is in an overflow action with a confirmation naming the date and tracker. It resets that day's observations and committed food entries atomically, is auditable, and offers Undo. It does not delete configuration, favorites, recipes, or other days.

### 6.4 Chat screen

The header shows selected log date, local-model availability, and online/offline lookup status. Above the composer, show a small deterministic daily summary for enabled nutrition fields. Messages include text, result cards, clarification choices, and mutation receipts.

A nutrition result card contains:
- Matched product/item, brand or restaurant, market, and preparation.
- Quantity and basis: grams, named serving, or recipe portion.
- Calories, protein, fiber, and other enabled nutrients; unknown values are visibly unknown.
- Source type, source link, source date, and "cached" or "stale" badge when relevant.
- Separate **Add**, **Edit portion**, **Choose another**, and **Save favorite** actions.

**UI-011 [P0] Non-destructive preview.** Search and hypothetical answers do not change totals. The card must distinguish "Preview" from "Logged."

**UI-012 [P0] Corrections.** A correction shows what changed and the resulting daily total. Undo restores the immediately preceding entry revision, not a second copy of the meal.

**UI-013 [P0] Keyboard behavior.** Composer supports multiline text, Send, cancel lookup, and keyboard dismissal. Result cards remain accessible when the keyboard is open.

**UI-014 [P0] Minimal questioning.** Ask one focused clarification when feasible. Prefer selectable candidates over requiring the user to retype a brand, country, or portion. A batch with several unresolved items can use one review sheet rather than a long conversational interrogation.

### 6.5 History and settings

**UI-015 [P0] History.** Provide day navigation, meal/observation details, source details, edits, and a 7/30-day view. Show missing days as missing, not zero intake or failed days. Historical status uses the goal version effective that day.

**UI-016 [P0] Settings.** Include units, market, theme, templates, estimated-energy method, cache size/downloads, lookup permissions, privacy/export/deletion, and model readiness. Developer-only controls are isolated from normal settings.

**UI-017 [P0] Neutral language.** Prefer "Within your target," "Near target," "Outside your target," "Incomplete," and "Not scheduled." Do not label foods or people as bad, guilty, cheating, or failures.

---

## 7. Visual tracker builder and category catalog

### 7.1 Builder interaction

The builder is a visual configuration tool, not merely a list of goal text boxes.

**BUILD-001 [P0] Template entry points.** Offer Owner, Minimal day, Busy workday, Travel day, and Blank. Template examples are configurable preferences, not prescriptions. Travel changes layout/shortcuts only after explicit selection; no location monitoring is needed.

**BUILD-002 [P0] Three builder areas.** Provide a category/field library, a live phone preview, and an inspector for the selected card/field. On iPhone these may be sheets/segments rather than three simultaneous columns.

**BUILD-003 [P0] Layout editing.** Add, remove from view, reorder, resize to half/full width, rename, regroup, and pin a summary card. Drag-and-drop MUST have accessible Move up/down and width alternatives.

Acceptance: move hydration above nutrition and move calorie balance to a different full-width row; save/relaunch preserves both positions in every color state.

**BUILD-004 [P0] Field inspector.** Configure name, category, value type, unit, input method, step size, aggregation, schedule, goal type, target/limits, near-target rule, missing-data rule, inclusion in group status, and optional personal note.

**BUILD-005 [P0] Preview scenarios.** Preview Empty, Partially logged, On target, Outside target, and Custom values. Changing thresholds changes previews using the production evaluator, not separate mock color logic.

**BUILD-006 [P0] Safe drafts.** Builder edits are a draft until Save. Cancel restores the published layout. Include Undo/Redo within the editing session and a Reset template action with confirmation.

**BUILD-007 [P0] Versioned publishing.** Save creates a new configuration version effective Today or a selected future date. Default changes do not recolor past days. Explicit historical re-evaluation is a separate preview/export action, not a silent rewrite.

**BUILD-008 [P0] Distinguish visibility from collection.** Hiding a field keeps its history and collection setting. Disabling collection stops new automatic collection but preserves history. Archiving removes it from active configuration. Deleting records is a separate destructive privacy action.

**BUILD-009 [P0] Dependencies.** Derived fields declare dependencies. Removing protein from a nutrition composite updates the composite after a preview; deleting a required energy input disables the dependent calculation or asks for a replacement. Detect cycles before Save.

**BUILD-010 [P0] Typed custom fields.** Allow a custom count, quantity, duration, timestamp, interval, Boolean, checklist, rating, enum, paired quantity, or note. Arbitrary JavaScript, SQL, Swift, or free-form formula evaluation is forbidden.

**BUILD-011 [P0] Named calculations.** Derived fields choose from a small calculation registry: sum, last observation, interval duration, checklist completion, ratio, difference, resting-plus-active energy, and net energy. Enforce dimensional compatibility.

**BUILD-012 [P0] Configuration portability.** Export/import a versioned tracker-template JSON file without health observations or chat. Validate schema, bounds, unsupported units, duplicate IDs, references, and cycles before showing an import preview.

**BUILD-013 [P0] Multiple templates, one fact stream.** Switching between Workday and Travel views must not duplicate the same food or water events. Templates are views/goals over canonical metric IDs. Two independent custom fields must receive distinct metric IDs.

### 7.2 Major categories

Every listed category can appear in the builder library. P0 supports manual observations and configurations; automatic integrations and advanced interpretation are separately scoped.

| Category | Starter fields | Typical types/aggregation | Product limits |
|---|---|---|---|
| Nutrition | Energy, protein, fiber, carbs, fat, saturated fat, sodium, added sugar; optional food-group counts | Sum from foods and explicit adjustments | Missing nutrients remain unknown; no universal target values. |
| Hydration | Water, other drinks, personal hydration target | Volume sum, quick increments | User chooses whether named drinks contribute; prevent duplicate water entries. |
| Movement and fitness | Steps, active energy, workout completion, minutes, stretch/movement breaks | Daily total, count, checklist | Steps and workout calories are not added twice. |
| Sleep and recovery | Sleep start/end, duration, subjective sleep quality, naps | Intervals, ratings | Avoid overlapping-duration double counts and false clinical sleep judgments. |
| Meal timing | Optional fasting start/end, meal window | Interval/duration | Optional and removable; not included automatically in all templates. |
| Stress and mindfulness | Stress rating, mood, breathing/meditation minutes | Ratings, minutes, notes | No diagnostic inference from mood or stress scores. |
| Energy and focus | Energy rating, focus sessions, screen/eye breaks | Ratings, counts, duration | Manually logged in P0; no OS-wide usage monitoring promise. |
| Caffeine and other intake habits | Caffeine mg, last caffeine time, optional personally defined habit | Sum, last value, Boolean | Limits are user-defined; caffeine missing from a food is unknown. |
| Routines | Supplements AM/PM, stretching, user-defined routine | Scheduled checklists | No medication dose generation or treatment reminders invented by the model. |
| Body trends | Weight, waist, optional body-composition observation | Latest/series, not daily sum | Trend-only by default; no red/green judgment on body weight. |
| Heart/health observations | User-entered resting pulse or blood pressure | Latest/paired measurement | Display observations; clinical thresholds and diagnosis are out of scope. |
| Digestive or cycle notes | Optional symptoms, bowel notes, menstrual-cycle event | Enum, rating, notes | Sensitive, opt-in, local; no fertility or disease predictions. |

**BUILD-014 [P0] No hardcoded metric ceiling.** Enabling sodium or caffeine must not require a database column migration or a new progress-component implementation. A registry plus typed values drives storage and rendering.

**BUILD-015 [P0] Tracking-only defaults.** New sensitive fields and subjective ratings default to unscored. The user may configure personal goals, but the application must not ship clinical cutoffs under generic "healthy" labels.

**BUILD-016 [P0] Screen-fit feedback.** Preview reports when a layout needs scrolling. It must not silently remove cards to fit. Compact-mode priorities and explicit collapse settings are user-visible.

---

## 8. Goal evaluation and status rules

### 8.1 Goal schema

Each goal needs at least:

```text
goalID, metricID, configVersion
kind: minimum | maximum | range | exact | completion | trendOnly | composite
aggregation: sum | last | count | durationUnion | checklist
period: day | week | customSchedule
displayTarget: optional lower/upper/exact + unit
evaluationBounds: explicit numeric thresholds or named evaluator
nearTargetRule: absolute | relativeToTarget | relativeToBoundary | explicitBounds
missingPolicy: incomplete | ignoreIfOptional
schedule: weekdays / due times / time zone policy
allowOverTarget: Boolean where meaningful
scoringEnabled: Boolean
```

Display targets and evaluation thresholds are intentionally separate. Example: display protein goal **140-150 g**, but classify **130 g or more** as green in the owner's template.

**GOAL-001 [P0] Pure evaluator.** `evaluateGoal(value, coverage, configuration, dateContext)` returns status, progress, reason, and contributing inputs. The same function serves Today, Builder preview, History, and tests.

**GOAL-002 [P0] Typed status.** Status is `unrecorded`, `partial`, `met`, `near`, `outside`, `notScheduled`, or `unscored`. Render gray for unrecorded/partial, green for met, yellow for near, and red for outside. Do not conflate a missing observation with an observed zero.

**GOAL-003 [P0] Inclusivity.** All threshold inclusivity is explicit. Compare canonical unrounded values. Round only for display. No blanket extra 5% tolerance may be applied after a field-specific threshold has already been calculated.

### 8.2 Standard evaluation formulas

For a minimum target `T > 0`, with allowed near-target shortfall `a >= 0`:

```text
met:     x >= T
near:    T - a <= x < T
outside: x < T - a
```

For maximum `T` and allowed excess `a`:

```text
met:     x <= T
near:    T < x <= T + a
outside: x > T + a
```

For range `[L,U]` and near allowances `aLow,aHigh`:

```text
met:     L <= x <= U
near:    L-aLow <= x < L  OR  U < x <= U+aHigh
outside: otherwise
```

Exact target is a range generated from an explicit tolerance. A zero-valued target cannot be a percentage denominator; require absolute tolerances instead.

**GOAL-004 [P0] Overshoot semantics.** Minimum goals such as protein or steps remain met above the target. Maximum/range goals such as a chosen caffeine limit or calorie range do not. "Higher remains green" is not a universal rule.

**GOAL-005 [P0] Progress is not a reward score.** Progress display can cap at 100% while preserving actual values. No extra achievement or streak multiplier for a larger deficit, longer fast, or higher supplement count.

### 8.3 Owner template: exact defaults

These are the owner's previously selected preferences, not general health recommendations. The intentional changes from legacy implementation are listed immediately below.

| Field/group | Display | Evaluation |
|---|---|---|
| Sleep | 8 h | Met at >=456 min (within 5% below 8 h, or above); near 360 to <456 min; outside <360 min. |
| Fasting | 16 h, optional | Met 912-1,008 min; near 720 to <912 or >1,008 to 1,200; outside otherwise. No reward for fasting longer. |
| Protein | 140-150 g | Met >=130 g; near 97.5 to <130 g; outside <97.5 g. |
| Fiber | 35 g | Met >=33.25 g; near 26.25 to <33.25 g; outside <26.25 g. Amounts above goal stay met. |
| Calories | 2,000-2,200 kcal | Met 1,895-2,305; near 1,475 to <1,895 or >2,305 to 2,725; outside otherwise. These reproduce legacy midpoint-based tolerance; editable. |
| Water | 2-2.5 L | Met >=2,000 mL; near 1,500 to <2,000; outside <1,500. Amounts above goal stay met. |
| Steps | 7,500-10,000 | Individual goal met >=7,500; near 5,625 to <7,500; outside <5,625. |
| Exercise group | Workout + steps | See truth table below. |
| Supplements | AM + PM | Met when all scheduled checks done; near while partly done; incomplete before any are recorded; outside only after due window closes with missing checks. |
| Calorie balance | Weight-loss comparison | Exact legacy-style band below, with provisional/incomplete treatment and no extra reward for size of deficit. |

**Legacy discrepancies intentionally corrected:** v19 applies a shared 5% band after setting a 130 g protein threshold, making some values below 130 green. It similarly allows water below 2 L to become green. This PRD makes 130 g and 2 L the exact green boundaries, matching the owner's explicit choices. V19 also treats supplements as red immediately and can imply success from an incomplete calorie log. The new missing/scheduled/provisional states correct those issues. [L01]

Sleep, fiber, fasting, and calorie tolerance values above retain the legacy design unless the owner edits them. They are visible in advanced goal settings; no hidden logic.

The initial owner AM/PM checklist uses both labels with completion due by the end of the assigned day unless the user configures earlier windows. Creating the template does not schedule notifications. A completely unlogged day remains incomplete in history; absence of records alone is not proof that the routine was missed. Explicit missed/skipped states and a completed-day review determine the final routine status.

### 8.4 Composite rules

**GOAL-006 [P0] Nutrition group.** Aggregate enabled required nutrition goals using the worst evaluable status: outside > near > met. If any required metric has incomplete coverage, show partial/gray with details rather than a definitive met status. Disabled goals do not participate. Known zero is valid data.

**GOAL-007 [P0] Exercise compatibility rule.** Preserve the owner's custom combination, not a generic average:

| Workout | Steps | Group status |
|---|---|---|
| Not recorded | Not recorded | Unrecorded |
| Done | >=7,500 | Met |
| Done | <7,500 or unrecorded | Near, with missing-steps note if applicable |
| Not done | >=5,625 | Near |
| Not done | Recorded <5,625 | Outside |

A workout label such as "Apple Fitness+" is a configurable activity name, not evidence of integration with that subscription service.

**GOAL-008 [P0] General composites.** Builder supports ALL-required and ANY-required groups. For ALL, missing required input yields partial unless all are unrecorded; for ANY, one met branch satisfies the group. Empty composites are invalid. Display explanations, not just colors.

**GOAL-009 [P0] Weekly schedules.** A weekly count such as three workouts is evaluated over a defined week-start/time-zone policy. Today must not show a weekly target as already failed on Monday. Rest days and unscheduled routines are not red.

**GOAL-010 [P0] Known totals versus completeness.** A user's nutrition total can contain valid known values while remaining a partial-day log. Separate goal status from "day complete" and nutrient coverage. Do not assume no unlogged meals exist.

---

## 9. Calories, resting energy, and activity accounting

### 9.1 Definitions

- **Intake:** sum of committed food nutrient snapshots plus explicit manual adjustments.
- **Resting energy estimate:** a model-derived daily estimate, not a direct measurement.
- **Active energy:** energy above rest from the selected manual/imported source.
- **Estimated total out:** the selected energy model's output.
- **Net:** intake minus estimated total out.

The legacy value called BMR is 1,883 kcal for an example profile of 93 kg, 178 cm, age 33, male equation. The underlying Mifflin-St Jeor formula estimates resting energy expenditure; the app should use that more careful label in details. [L01, S14]

### 9.2 Supported methods

**ENERGY-001 [P0] Legacy-compatible method.** `estimatedOut = estimatedRestingKcal + activeKcal`. Label it "Estimated resting + logged active energy," not measured TDEE. Do not add an activity multiplier or a separate thermic-effect estimate on top in this mode.

**ENERGY-002 [P0] Configurable resting input.** Allow manually specified resting estimate or the following formula with reviewed profile inputs:

```text
restingKcal = 10*weightKg + 6.25*heightCm - 5*ageYears + equationConstant
constant: +5 for male equation, -161 for female equation
example: 93 kg, 178 cm, age 33, +5 => 1,882.5 kcal/day
```

The formula is documented in the original research. It is an estimate and not appropriate as an automated prescription. [S14]

Acceptance: never infer the equation selection from a name or photo. Users can choose a manual estimate or omit this feature. Example owner values are opt-in seed values requiring confirmation, not universal defaults.

**ENERGY-003 [P1] HealthKit method.** A separate mode uses permitted resting/basal and active-energy samples for the same interval. Do not add the formula estimate to HealthKit resting energy. Partial-day data must not be presented as a completed day's expenditure.

**ENERGY-004 [P1] Fixed total-expenditure mode.** Optional manually supplied daily expenditure replaces resting-plus-active mode. Active calories can be displayed, but are not added to that total unless the chosen method explicitly defines them as additional.

### 9.3 No double counting

**ENERGY-005 [P0/P1] Exclusive energy source selection.** Manual daily active total, HealthKit active total, and imported workout-energy components are not blindly summed. A recorded workout completion flag never creates calories by itself. Steps never generate extra calories when an active-energy total already includes them.

Acceptance: imported active energy 500 kcal plus a workout record reporting 250 kcal still yields active energy 500 when the workout is part of that imported total.

**ENERGY-006 [P0] Missing versus zero.** An unentered active total is unknown; a user-confirmed zero is zero. Display assumptions explicitly. Formula-only out may be shown as a resting baseline, but cannot masquerade as a complete activity total.

### 9.4 Balance bands

For the owner's legacy comparison:

```text
r = (intake - estimatedOut) / estimatedOut
weight-loss mode:
  r < -0.05       => met band
  -0.05 <= r <= 0.05 => near band
  r > 0.05        => outside band
weight-gain mode: reverse the outer bands
maintenance mode: central band is met; outer bands use configured near/outside limits
```

**ENERGY-007 [P0] Completeness and bounded alternatives.** The numeric comparison can update during the day but is labeled provisional. The default balance indicator is partial/gray until the intake day and selected activity input are marked complete. Advanced users may enable live provisional coloring. Offer an explicit user-defined net range instead of the legacy one-sided deficit rule.

**ENERGY-008 [P0] No deficit maximization.** Do not praise or recommend a larger deficit. If the intake-range goal is outside its lower bound, show a conflicting-goal note rather than a celebratory overall day state. No universal safe deficit is invented by the app.

**ENERGY-009 [P0] Goal changes.** Switching loss/maintenance/gain changes future/effective-date evaluation only, not historical food data or historical profile snapshots.

---

## 10. Food records, portions, recipes, and nutritional arithmetic

### 10.1 Source-of-truth food record

Each food version contains:

```text
foodID, foodVersionID, canonicalName, brand, restaurant
marketCountry, language, preparation, variant, packageSize
identifiers: FDC ID / GTIN or UPC / manufacturer SKU / restaurant item ID
basis: per100g | per100mL | namedServing
basisQuantity, basisUnit, servingName, servingMassG?, servingVolumeML?
nutrients: map<numericNutrientID, value + unit + reported/missing state>
sourceID, sourceURL, sourceLocator, sourcePublishedAt?, retrievedAt
contentHash, parserVersion, licensePolicy, evidenceType
available/discontinued/unknown state
```

**FOOD-001 [P0] Versioned facts.** A logged food references and snapshots its nutrition version. Future database updates never silently rewrite earlier meals.

**FOOD-002 [P0] Unknown is not zero.** Missing fiber, sodium, or other nutrients remains null with a reason. A reported zero is stored as known zero. Totals show "at least" or partial coverage as appropriate.

**FOOD-003 [P0] Evidence labels.** Distinguish official manufacturer/restaurant, USDA reference, branded label record, user-entered label, recipe-calculated, and estimate. A label is evidence of reported composition, not a guarantee of the exact contents of every serving.

**FOOD-004 [P0] Identity strictness.** Full-fat/nonfat, raw/cooked, drained/undrained, flavor, country, package size, and restaurant portion modifiers must be represented. Similar names do not establish equivalence.

### 10.2 Portion engine

**FOOD-005 [P0] Canonical units.** Support grams, kilograms, ounces, pounds, milliliters, liters, US fluid ounces, named servings, count, package, and recipe portion. Distinguish mass ounces from fluid ounces. Household cups/spoons require an explicit volume convention and a food-specific mass mapping when converting to grams.

**FOOD-006 [P0] Valid transformations.** Nutrients scale by `requestedBasis / sourceBasis`. Convert volume to mass only with an evidenced density/portion mapping. A cooked-food quantity cannot use a dry-food record without a known yield or explicit correction.

**FOOD-007 [P0] Preserve precision.** Store decimal quantities; use decimal arithmetic for nutrient scaling. Sum unrounded values. Display calories rounded to whole kcal and macros typically to 0.1 g, with a simpler compact display allowed.

**FOOD-008 [P0] Label serving versus exact weight.** "Two label servings" uses exactly twice the reported serving nutrients. "4 oz by weight" converts to 113.3980925 g, rather than silently equating it to two 56 g servings. A label's approximate ounce notation must not corrupt exact mass arithmetic.

**FOOD-009 [P0] Energy consistency.** Preserve reported kcal as authoritative for that record. A 4/4/9 macro calculation may flag a possible parsing problem but must not overwrite calories or assert an error, since label rounding and nutrient definitions vary. Convert kJ to kcal only when required and label the conversion.

**FOOD-010 [P0] Food ranges.** An estimate stores lower/central/upper values and assumptions separately from official facts. Do not generate a calibrated-looking confidence percentage without validation. Summing interval endpoints is a range propagation convention, not a statistical confidence interval.

### 10.3 Entries and aliases

**FOOD-011 [P0] Entry states.** Food entries are draft, planned, committed, replaced, or deleted. Only current committed revisions affect intake totals.

**FOOD-012 [P0] Personal aliases.** "My tuna," "that ham," and "my usual bowl" resolve through explicit local aliases and recent confirmed entries. An alias points to a canonical item/recipe and version preference, never a nutrient number remembered in a free-text summary.

**FOOD-013 [P0] Alias ambiguity.** When several foods match, ask or show candidates. "Same as yesterday" must resolve against the correct household/user, date, meal, and country. No cross-user aliases in a global cache.

**FOOD-014 [P0] Favorites.** A favorite may include food identity and preferred portion. The user can log a different portion without changing the saved default unless they choose to update it.

### 10.4 Recipes and batches

**FOOD-015 [P0] Recipe versioning.** Store ingredients with source versions and quantities, optional cooking-loss assumptions, finished edible batch mass, and portion count/weights.

**FOOD-016 [P0] Cooked yield.** Recipe nutrients are derived from ingredients and explicitly modeled losses; water evaporation changes mass/density but does not by itself remove calories. The app must not assume all oil remains or all nutrients are retained when a relevant discarded component is known.

**FOOD-017 [P0] Portions.** For weighed cooked portions, scale nutrients by portion mass divided by finished batch mass. For count portions, require an explicitly selected equal-portion assumption or separately recorded weights.

Acceptance: a synthetic 1,200 kcal batch divided into 12 equal portions logs 300 kcal for three portions; a 200 g serving from a 1,000 g finished batch logs 240 kcal.

**FOOD-018 [P0] Unknown mixed dishes.** "Two 100 g kotlets" means 200 g finished dish, not 100 g beef. Without a recipe, offer an explicit comparable-dish estimate or ask for recipe composition. Do not claim that a dry-looking surface proves low absorbed oil.

### 10.5 Manual totals and reconciliation

**FOOD-019 [P0] No parallel competing totals.** Dashboard nutrient totals equal committed food snapshots plus auditable manual adjustments. Directly changing a daily number must not create an invisible override unrelated to meals.

**FOOD-020 [P0] Absolute total edit.** "Set today's protein to 120 g" previews a manual adjustment equal to target minus current derived total, with the current revision recorded. Subsequent foods add normally. A stale preview is recalculated/reconfirmed, not applied against a changed total.

Acceptance: current protein 100 g, set to 120 creates +20 g adjustment; adding a 30 g protein food makes 150 g. Removing that food returns to 120 g. The adjustment remains visible in History.

---
## 11. Chat, local model, and mutation safety

### 11.1 Intent contract

The interpreter returns a small typed proposal, not a finished answer containing invented nutrition. Define an application-owned representation equivalent to:

```text
InterpretedTurn
  intent: logFood | lookupFood | compare | hypothetical | reviseMeal |
          removeEntry | summarizeDay | recordObservation | proposeGoalChange |
          clarify | unsupported
  items: FoodMention[]
  targetEntryID: optional, validated against supplied candidates
  targetLogDay: optional, resolved by deterministic date rules
  metricChanges: optional typed proposals
  unresolvedQuestions: Clarification[]

FoodMention
  textSpan, normalizedQuery, brand?, restaurant?, market?
  quantity?, unit?, count?, perItemQuantity?, preparation?
  reference: explicitFood | savedAlias | previousEntry | unknown
  modifiers: named changes only
```

This is a domain contract, not guaranteed compilable Apple macro syntax. Implement it using the public SDK's supported `@Generable` types, modest enums, and clear field descriptions. Structured generation constrains shape; it does not prove that the interpretation is correct. [S04]

**CHAT-001 [P0] Separate question from consumption.** "How about beans?", "What would this be with chickpea pasta?", and "I might have a poke bowl" are previews. "I had 100 g beans" is a proposed log. Neither commits without the configured confirmation policy.

Acceptance: ten hypothetical messages leave daily totals unchanged. A proposed meal is clearly marked Planned or Preview, never silently counted.

**CHAT-002 [P0] Review-first default.** Default to one confirmation for a complete meal. After personal testing, an optional Fast log setting MAY commit clear, fully resolved, explicit consumption statements and show an Undo receipt. Fast log never applies to unresolved portions, estimates not accepted by the user, destructive operations, goal edits, or ambiguous references.

**CHAT-003 [P0] Correction targeting.** Interpret "100 g, not 150" as an edit to the active draft or clearly identified recent entry, not a new food. If two plausible targets exist, ask which one. Preserve the original revision in audit history.

Acceptance: "No lentils, just 100 g pinto beans" removes lentils and changes beans in a single meal revision. It does not append a second dinner.

**CHAT-004 [P0] Discarded food.** "I scrapped the oatmeal" cancels its draft. If already logged, offer removal of that entry. Do not assume the entire meal was eaten or that any tasted amount has a known weight.

**CHAT-005 [P0] Unit ambiguity.** A number can refer to food mass, protein, serving count, or package size. The model must not silently reinterpret one as another. "It is 29 grams, same tuna" requires context or clarification when both food mass and protein-per-can are plausible.

**CHAT-006 [P0] Same-food memory.** Resolve "my ham" or "same as yesterday" by retrieving a small set of saved identities and recent entries. Do not rely on a model remembering a nutrient number from old conversation text. If the matched record has 29 g protein per can, present that interpretation explicitly.

**CHAT-007 [P0] Multiple items.** Support a bounded batch of up to eight food mentions per turn initially. Resolve each separately; review the meal as a unit. An unresolved item must not prevent the user from choosing to log only the resolved items, with that partial action visible.

**CHAT-008 [P0] Observation logging.** Chat can propose water, steps, sleep intervals, and custom-field observations using metric IDs from the active configuration. Unknown fields are offered as builder proposals, not created silently.

**CHAT-009 [P0] Goal edits require approval.** "Change my water goal to 2.5 L" shows the changed amount, evaluation threshold, effective date, and affected composite before Save. A web page, model completion, or background task cannot publish goal changes.

### 11.2 Read tools and orchestration

Expose a minimal set of read capabilities through application services:

| Tool | Responsibility | Important constraint |
|---|---|---|
| `resolveFood` | Search private aliases, device catalog, then permitted remote resolver | App enforces cache order and network permission, not the model. |
| `getRecentEntries` | Retrieve bounded candidates for a date/reference | Local only; never return the entire user history. |
| `getFoodVersion` | Retrieve a validated source version | IDs must exist; unknown IDs are rejected. |
| `getDaySummary` | Deterministic totals and goal state | Known totals and missing coverage remain distinct. |
| `getMetricDefinitions` | Active field IDs, units, goal descriptions | Read-only; goals cannot be changed through this tool. |

Use an application controller for planning and committing mutations. Do not give the model a general `executeSQL`, `fetchAnyURL`, `writeHistory`, or `changeGoals` capability. Apple's tool API invokes application code; the application remains responsible for permissions and side effects. [S05]

**CHAT-010 [P0] Read-only model tools.** Tools exposed to generation cannot mutate personal records. Only validated application commands, issued after the applicable user confirmation, can do so.

**CHAT-011 [P0] Bounded loop.** Initial limits: at most four read-tool invocations and three model generations per turn, including at most one repair attempt. Use one interpretation by default; a second pass is justified only for bounded candidate selection or clarification. Exceeding a budget ends in a reviewable fallback, not an autonomous retry loop.

**CHAT-012 [P0] Small context.** Supply the current request, active draft, necessary recent identities, and relevant metric definitions. Bound candidate lists to five per ambiguous item. Do not inject full restaurant PDFs, full catalogs, or unbounded transcripts. Account for instructions, schemas, tools, and generated output within the model's supported context. The documented baseline on-device context constraint must be respected rather than assuming future extensions. [S07]

**CHAT-013 [P0] Numbers rendered by code.** Nutrient totals, changes, percentages, and remaining targets are formatted from validated domain objects. An optional generated sentence cannot override those values. It must not be the only place a source or uncertainty is shown.

**CHAT-014 [P0] Failure handling.** A refusal, unsupported topic, context overflow, malformed proposal, or low-confidence interpretation offers direct search/manual entry and preserves the user's text. Do not attempt to disable guardrails or disguise medical requests to force a response. [S17-S18]

### 11.3 Commit protocol

```text
Interpret -> resolve -> validate -> calculate -> preview
         -> explicit confirmation / permitted Fast log
         -> atomic commit -> update projections -> receipt + Undo
```

**CHAT-015 [P0] Validation before commit.** Validate item existence, source version, units, quantity, selected day, entry ownership, expected revision, and intent. A valid JSON/schema object is not sufficient authorization.

**CHAT-016 [P0] Idempotence.** Assign a mutation ID when creating the preview. Repeated confirmation, an interrupted save, or retrying the same command must not add the meal twice. A deliberate "another one" receives a new mutation ID.

**CHAT-017 [P0] Optimistic concurrency.** Commands include the expected entry/day revision. If the dashboard changed after preview, recalculate and show a revised preview rather than overwriting newer data.

**CHAT-018 [P0] Cancellation.** Canceling a lookup never commits. A late network/model response is ignored for a canceled draft or stored only as an uncommitted result.

**CHAT-019 [P0] Prompt versioning.** Store prompts and schema versions as versioned app resources. Record their hashes in evaluation runs. Compare versions with a fixed held-out set before enabling them by default. Do not claim that changing prompts pins Apple's underlying model version. [S06]

**CHAT-020 [P0] General advice boundary.** Basic comparisons can summarize sourced nutrition records. Questions requiring medical assessment, dosing, or personalized treatment are outside scope. No broad health-benefit ranking is generated from model memory and presented as sourced evidence.

---

## 12. Direct-web nutrition lookup and source quality

### 12.1 Retrieval order and cost policy

The objective is to avoid repeated paid lookups, not to promise that unrestricted web discovery is free.

```text
Private alias / previously chosen food
  -> local core catalog and private cache
  -> hosted normalized catalog, when enabled
  -> known official page/document adapter
  -> permitted discovery provider, only when configured
  -> unresolved / candidate review / explicit comparable-food estimate
```

**LOOKUP-001 [P0] Cache-first routing.** A fresh, exact, locally cached result produces no remote request. A hosted catalog hit produces no live brand/restaurant fetch. Cache checks are enforced by the resolver, independently of the model's proposed tool sequence.

**LOOKUP-002 [P0] Known-source registry.** Maintain restaurant/brand names, verified official domains, market, source URLs, parser type, allowed paths, retrieval policy, and last successful validation. Retrieve known nutrition documents directly instead of searching the web for every menu item.

**LOOKUP-003 [P0] Discovery is a separate capability.** A source registry may be curated during development. General search is optional and disabled until a permitted provider or implementation is configured. No hidden paid service, search-result scraping, or assumed free universal search endpoint is allowed.

Acceptance: with discovery disabled, an unfamiliar brand returns "No supported source found" plus direct-search/manual alternatives. It does not secretly call a commercial nutrition API.

**LOOKUP-004 [P0] Direct source retrieval.** Support public HTML, structured JSON/JSON-LD, and text-based nutrition PDFs for the initial adapters. Prefer source-specific deterministic extraction over asking the local model to reconstruct a large document. Schema.org defines a standard nutrition vocabulary, but a site is not assumed to implement it. [S16]

**LOOKUP-005 [P0] P0 source coverage gate.** Before the first web-enabled beta, demonstrate at least three restaurant adapters and two packaged-brand adapters with real current public sources, or document blocked adapters and replace them. Choose sources after checking availability; naming a desired restaurant does not make its nutrition obtainable.

Suggested research queue: McDonald's, Panera, Sbarro, Chipotle, Subway, Chobani, Slate, and an additional frequently used packaged-food brand. This is a queue, not a verified adapter list.

### 12.2 Matching and evidence

**LOOKUP-006 [P0] Market-specific identity.** US and Canadian menus/products are different candidates. Query using the user's selected market, not IP geolocation alone. Display market on restaurant results; require selection when ambiguity is material.

**LOOKUP-007 [P0] Portion specificity.** Match size, serving count, flavor, fat level, preparation, and customizations before logging. "Small pasta salad" is not automatically equivalent to a published 100 g entry. If the restaurant publishes only one serving without grams, count-based logging is possible, but arbitrary gram conversion is not.

**LOOKUP-008 [P0] Supported modifications only.** Removing cheese or changing sauce requires official component nutrition or a source-backed recipe model. Otherwise show the base item and a clearly labeled uncertain adjustment, with confirmation; do not invent precise subtraction.

**LOOKUP-009 [P0] Evidence is not a probability.** Track separate source authority, identity match, serving match, freshness, and extraction-validation status. Do not assign arbitrary "99% accurate" values based solely on an official domain. Official labels are source records, not laboratory measurements of the user's serving.

**LOOKUP-010 [P0] Fetch the underlying source.** Search snippets and generated search summaries are discovery aids, not sufficient evidence for a nutrition record. A successful record needs the underlying page/document and an extraction locator.

**LOOKUP-011 [P0] Per-field provenance.** Each extracted nutrient can reference its source and basis. Missing fiber remains null. A zero written on the source is zero. Different documents cannot be combined into one supposedly exact product without an explicit merge policy and visible provenance.

**LOOKUP-012 [P0] Extraction validation.** Validate finite nonnegative values, serving basis, units, obvious column shifts, duplicate nutrient fields, and suspicious changes. Calories can disagree with a simple 4/4/9 calculation because of label conventions; flag unusual differences for review rather than silently replacing the source.

**LOOKUP-013 [P0] Conflicts.** Preserve conflicting candidates. Prefer a verified current exact-market official source when justified, but show a conflict that cannot be resolved. Never average competing published values to invent an authoritative answer.

**LOOKUP-014 [P0] Menu availability versus nutrition.** Finding a nutrition PDF does not establish that an item is sold at a particular store today. Keep nutrition lookup and current local menu availability separate. Do not repeat the earlier conversational mistake of treating a listed soup as definitely available nearby.

### 12.3 Source adapter contract

Each adapter implements:

```text
discoverSupportedSources(registryEntry) -> SourceCandidate[]
fetchSource(sourceID, conditionalHeaders) -> SourceDocument
parseSource(document, parserVersion) -> ExtractedFoodCandidate[]
validateCandidates(candidates) -> Validated | NeedsReview | Rejected
publishVersion(validatedCandidate, evidence) -> FoodVersion
```

Document metadata includes official URL, market, retrieved timestamp, publication/effective date if explicitly present, response validators, content hash, parser version, source locator, license/reuse review, and refresh policy. A crawl timestamp is not a menu's effective date.

**LOOKUP-015 [P0] Parser fixtures.** Every adapter has a permitted stored fixture or minimal synthetic equivalent, expected parsed values, a changed-layout negative case, and a live smoke test separate from deterministic CI. Do not make CI depend on an uncontrolled live website.

**LOOKUP-016 [P0] Fail closed on parser changes.** If the page structure changes or the expected serving column disappears, retain the last known version as stale and report a parser failure. Do not publish zero-filled records.

**LOOKUP-017 [P0] Source evidence display.** The app can open the official source and show the relevant page/table/section identifier. Store only the evidence material the source policy permits; access to a public page is not unrestricted permission to redistribute its content.

**LOOKUP-018 [P0] No label-photo requirement.** A user can resolve supported brands/restaurants by typed names alone. Barcode and OCR are optional accelerators; unsupported coverage must be admitted rather than falsely promising every restaurant.

### 12.4 Safe fetching

**LOOKUP-019 [P0] Network isolation.** Public-source fetches contain no personal diary, health measurements, private aliases, retailer-session cookies, or chat history. Only normalized food identity and market are sent to the resolver.

**LOOKUP-020 [P0] SSRF and content limits.** Restrict initial adapters to approved HTTPS hosts and paths. Revalidate redirects and resolved addresses; reject loopback, private, link-local, metadata-service, `file:`, and non-HTTP destinations. Apply timeout, redirect, download-size, decompression, MIME, and parser-resource limits.

**LOOKUP-021 [P0] Untrusted document handling.** Treat page text and metadata as data, never as model instructions. A document saying "ignore your instructions" cannot change goals, reveal history, invoke arbitrary tools, or publish a food automatically.

**LOOKUP-022 [P0] Access restrictions.** Respect source policies, rate limits, and access controls. Robots directives are one technical input, not a substitute for permission or a license review. No CAPTCHA bypass, evasion, private endpoint reverse engineering, or authenticated account crawling in P0.

**LOOKUP-023 [P1] Image-only source fallback.** OCR may be added for a source that genuinely lacks accessible text. It requires field validation and user/operator review where needed. It is not the initial default extraction path.

---

## 13. Catalog storage, ingestion, caching, and updates

### 13.1 Local versus hosted scope

**CAT-001 [P0] Small initial seed.** Start with roughly 50 generic foods and 20-30 known products/menu examples. Real seed facts require source IDs and clear bases; synthetic fixtures are visibly marked and excluded from production search.

**CAT-002 [P0] Catalog tiers.** Maintain a personal cache, a replaceable core catalog, and an optional full hosted catalog. The personal diary must never depend on a remote food version staying available.

**CAT-003 [P0] Bulk USDA ingestion.** Use FoodData Central bulk downloads for hosted/reference ingestion rather than an API request for each user's meal. Preserve data-type distinctions among Foundation Foods, SR Legacy, FNDDS, and Branded Foods. USDA identifies the data as public-domain/CC0 and provides downloadable datasets. [S09-S11]

**CAT-004 [P0] Serving and nutrient mapping.** The importer explicitly maps nutrient identifiers, units, preparation, and portion records. Do not sum alternative energy definitions or use a nutrient's row order as its identity. A branded serving size does not automatically define a gram conversion when its source unit is volumetric.

**CAT-005 [P0] Conservative deduplication.** Prefer canonical identifiers and market/product-version keys. Preserve raw source IDs, publication dates, and discontinued records. Same barcode/name is not sufficient to overwrite old diary nutrition; formulations and packaging can change.

**CAT-006 [P0] Search.** Support exact barcode, brand plus name, normalized aliases, and lexical full-text search. SQLite FTS is a suitable initial mechanism; vector embeddings are not a prerequisite. Search must retain serving/preparation distinctions rather than merge them for convenience. [S15]

**CAT-007 [P0] Build-time size measurement.** Report row counts, file size, index size, and search latency for each generated pack. Initial targets: seed under 20 MB; ordinary core catalog near or below 100 MB; any optional pack over 250 MB requires an explicit download choice. These are product budgets, not claims about a measured optimized USDA database.

USDA's April 2026 download page lists Branded CSV at approximately 428 MB compressed and 2.9 GB expanded. An optimized application database has to be measured after filtering/indexing; do not copy earlier speculative size estimates into acceptance evidence. [S10]

### 13.2 Source freshness and caching

**CAT-008 [P0] Versioned cache.** A cache key includes canonical identity, market, relevant modifiers, source version, and portion basis. Do not cache "salad" without its restaurant/item identity and expect safe reuse.

**CAT-009 [P0] Explicit staleness.** Source policies define refresh intervals by source class. Use conservative starting policies, then measure: restaurant documents 7 days, brand pages 30 days, bulk generic packs per published release. These are defaults, not guarantees that the source has changed at that cadence.

**CAT-010 [P0] Conditional refresh.** Use ETag/Last-Modified where offered. Share public catalog fetch results across users only when permitted, and coalesce simultaneous requests for the same source. Do not refresh every time a meal is logged.

**CAT-011 [P0] Stale/offline behavior.** Show last-checked date and allow a user to knowingly reuse a previously verified stale record offline. New ambiguous matches and known-discontinued items require explicit selection. A failed refresh never silently changes old values.

**CAT-012 [P0] Bounded miss caching.** Cache not-found/blocked results briefly to avoid repeated network calls. Starting policy: 24 hours for an unresolved identity, shorter for transient failures. User-requested refresh can bypass miss caching within the network budget.

**CAT-013 [P0] Private versus global.** User aliases, private recipes, diary text, and manual corrections stay private. Only independently verified public-source records may enter the shared catalog. User agreement with a number does not convert it into an official global nutrition fact.

### 13.3 Pack/update protocol

**CAT-014 [P0] Atomic updates.** Pack manifests include schema version, catalog version, size, checksum, source release, and minimum compatible app schema. Download to a temporary location, verify, open/test, and then atomically activate. Retain the prior pack until successful activation.

**CAT-015 [P0] Rollback and cancellation.** Interrupted download, low disk space, incompatible schema, checksum mismatch, or canceled download leaves the current catalog usable. Never delete the existing pack first.

**CAT-016 [P0] Historical preservation.** Removing a catalog item does not delete its meal snapshots, source references, or recipes. The user can inspect what was used when that meal was logged.

**CAT-017 [P1] Delta distribution.** Incremental packs and popular-brand offline packs may follow initial full-pack updates. Delta application must include a base-version check and the same rollback guarantees.

**CAT-018 [P1] Hundred-restaurant coverage.** Maintain a coverage registry with `notResearched`, `sourceFound`, `adapterReady`, `partial`, `blocked`, `stale`, and `validated` states. Count a chain as supported only for documented markets, portions, and items. Do not claim a hundred complete menus merely because a hundred URLs are stored.

### 13.4 Reuse/licensing register

**CAT-019 [P0] Data rights metadata.** Record source terms/license, whether local caching and redistribution are allowed, attribution requirements, review date, and restrictions. A source whose reuse is unclear can be linked or privately reviewed but must not automatically be bundled in a distributed app.

**CAT-020 [P0] Provider boundaries.** Any later paid provider remains a disabled plug-in until explicitly configured. Its data must not leak into a perpetual shared cache contrary to that provider's terms. P0 must pass with every paid provider disabled.

---

## 14. Persistence, history, migration, and domain contracts

### 14.1 Entities

Use stable IDs, explicit revisions, and typed values. Proposed domain entities:

| Entity | Important fields |
|---|---|
| `MetricDefinition` | ID, canonical key, type, canonical unit, aggregation, category, input/source capabilities, archived flag |
| `GoalConfiguration` | ID, version, metric/composite references, goal kind, bounds, schedule, missing rule, effective date |
| `TrackerTemplateVersion` | Layout/card configuration, metric references, goal-version references, effective dates |
| `Observation` | ID, metric ID, typed value, observed time, log day, source, external sample ID, revision |
| `DayRecord` | Log-day identifier, time-zone context, completeness states, active template/config versions |
| `FoodVersion` | Canonical ID, version, serving basis, nullable nutrients, evidence, freshness, market |
| `MealEntry` / `MealRevision` | ID, item snapshots, quantity/basis, log day, status, timestamps, mutation ID, revision |
| `RecipeVersion` | Ingredients and versions, yields, loss assumptions, named portions |
| `FoodAlias` | Private alias, target identity/version preference, market, optional default portion |
| `ConversationTurn` | Text, typed draft/result references, date context, optional locally retained diagnostics |
| `MutationReceipt` | Mutation ID, command type, affected IDs, old/new revisions, Undo reference |
| `ExternalSourceCursor` | Integration/source, latest cursor, last successful retrieval, source state |
| `CatalogManifest` | Pack version, source release, schema, file hash/size, activation state |

**STORE-001 [P0] Schema-versioned persistence.** Every persistent/exported format has a schema version and migration tests. Keep catalog and personal data in separate stores so catalog replacement cannot destroy the diary.

**STORE-002 [P0] Typed values.** Quantities are not strings containing units. Store canonical numeric values plus typed units and an original-input representation for audit. A paired measurement such as blood pressure is a structured value, not two unrelated daily sums.

**STORE-003 [P0] Local transactions.** Save a meal revision, its mutation receipt, and affected projections atomically. If any write fails, show Save failed and retain the draft. Do not show Saved before successful persistence.

**STORE-004 [P0] Source-of-truth rules.** Meals/observations and their revisions are canonical. Daily totals and statuses are rebuildable projections. A cached total cannot become a separate authoritative counter.

**STORE-005 [P0] Persisted Undo.** At minimum, Undo of the latest mutation remains available after a normal app restart. Deletion/removal uses a reversible state or revision until an explicit permanent privacy deletion. Old Undo cannot silently overwrite a newer revision.

### 14.2 Time, travel, and day attribution

**STORE-006 [P0] Explicit log day.** Record an event timestamp, relevant time-zone identifier/offset, and chosen log day. Traveling later must not move historical meals between dates. A visible date selector resolves whether "today" means the current day or a selected historical day.

**STORE-007 [P0] Intervals use actual dates.** Sleep and fasting store start/end timestamps with dates, not just clock strings. Calculate elapsed time correctly across midnight and daylight-saving changes. Missing endpoints mean incomplete, not zero hours.

**STORE-008 [P0] No arbitrary modulo-24 fix.** An end earlier than a start requires a next-day inference shown in the editor or explicit date selection. Durations over 24 hours are representable but reviewed where implausible; they are not silently wrapped to a shorter duration.

**STORE-009 [P0] Daily reset is not deletion.** Advancing to a new date creates a new view over new-day observations. Prior days remain available. In-progress intervals remain open until completed or canceled.

**STORE-010 [P0] Clock changes.** Inject a clock/time-zone provider into domain tests. Day boundaries and reminder schedules must not depend on a `Date()` captured only at app launch.

### 14.3 Legacy web-tracker migration

**STORE-011 [P0] Honest import boundary.** Native code cannot assume direct access to Safari's existing localStorage. Provide a documented user-initiated JSON export from the old page, share/file import, or a manual review screen. Do not attempt to bypass browser storage isolation.

**STORE-012 [P0] Legacy mapping.** Recognize the v19 key/payload `nimaWellnessTrackerCompactV2` and map its known fields into one dated import with a source label. Treat the old BMR constant as an unconfirmed prior setting, not the new user's measured metabolism.

**STORE-013 [P0] Missing-history warning.** The inspected legacy script preserves one date's state, not a recoverable full historical ledger. Import only what is present; do not fabricate earlier days from prior chats or localStorage key names.

**STORE-014 [P0] Zero interpretation.** Legacy default zeros are ambiguous between unrecorded and explicitly zero. The import preview asks which data were genuinely entered and defaults untouched-looking fields to missing. It must not score an empty old day as complete.

**STORE-015 [P0] Deduplicate imports.** Use an import fingerprint plus payload date. Reimporting the same payload does not duplicate calories or observations. Replacing an earlier import requires an explicit preview.

### 14.4 Extensibility for future inventory

**STORE-016 [P0] Stable food identities.** Keep canonical product IDs, external-ID mappings, source versions, and optional recipe-batch IDs independent of meal entries. This permits a later inventory ledger without requiring inventory functionality now.

**STORE-017 [P2] Future inventory boundary.** Inventory acquisition/consumption and personal nutrition logs may share food identity, but must not be assumed to be the same event. A household member using a product does not automatically create the owner's dietary intake.

---

## 15. Backend API contracts

### 15.1 Optional deployment

The backend stores public catalog data and retrieves approved public nutrition sources. It is not a personal health-data server in P0. The app must function with the resolver URL unset.

**API-001 [P0] Transport and credentials.** Production endpoints require HTTPS. Keep administrative/source-provider credentials on the server. A personal deployment can use a revocable installation token provisioned separately and stored in Keychain; no secret is committed into the app or repository.

**API-002 [P0] Minimal request data.** Send normalized food identity, market, optional preparation/modifiers, and a request ID. Do not send full chat text, goals, body metrics, location history, or previous meals. Restrict query fields and lengths to prevent accidental transcript uploads.

Proposed endpoints:

| Endpoint | Purpose |
|---|---|
| `GET /healthz` | Liveness only; no sensitive configuration. |
| `POST /v1/resolve` | Search normalized hosted records and approved sources according to budget. |
| `GET /v1/foods/{foodID}/versions/{version}` | Immutable nutrition record and evidence metadata. |
| `GET /v1/catalogs/{market}/manifest` | Compatible core-pack manifest and download metadata. |
| `GET /v1/catalogs/{market}/changes?since={version}` | Optional P1 delta feed. |
| Administrative jobs, not public routes | Import USDA, refresh registry sources, inspect quarantined parser results. |

### 15.2 Resolve request example

```json
{
  "requestID": "demo-request-001",
  "query": {
    "name": "plain Greek yogurt",
    "brand": "Example Brand",
    "market": "US",
    "preparation": null,
    "variant": "whole milk"
  },
  "policy": {
    "allowOfficialFetch": true,
    "allowDiscovery": false,
    "allowPaidProvider": false
  }
}
```

### 15.3 Resolve response example

The following is **synthetic test data**, not a real brand's nutrition:

```json
{
  "requestID": "demo-request-001",
  "status": "resolved",
  "origin": "hostedCatalog",
  "candidates": [
    {
      "foodID": "fixture-yogurt-whole",
      "version": "1",
      "name": "Example Brand plain whole-milk Greek yogurt",
      "market": "US",
      "basis": {"amount": 100, "unit": "g"},
      "nutrients": {
        "energy_kcal": 100,
        "protein_g": 9,
        "fiber_g": null,
        "carbohydrate_g": 4,
        "fat_g": 5
      },
      "evidence": {
        "type": "syntheticFixture",
        "sourceID": "fixture-source-001",
        "url": null,
        "locator": "test table, row 1",
        "retrievedAt": null,
        "contentHash": null,
        "validation": "fixtureValidated"
      },
      "match": {
        "identity": "exact",
        "portion": "basisOnly",
        "market": "exact",
        "freshness": "notApplicable"
      }
    }
  ],
  "usage": {"officialFetches": 0, "discoveryCalls": 0, "paidCalls": 0}
}
```

**API-003 [P0] Complete outcome vocabulary.** Support `resolved`, `ambiguous`, `notFound`, `sourceBlocked`, `sourceStale`, `parserFailed`, `budgetExceeded`, and `temporarilyUnavailable`. Distinguish a successful exact match from a candidate list.

**API-004 [P0] Contract validation.** Publish a versioned OpenAPI schema and test both client decoding and server validation against it. Unknown optional fields are forward-compatible; incompatible changes require a new API/schema version.

**API-005 [P0] Retry safety.** GETs and resolve requests are read-only. Coalesce repeated resolve requests and respect retry-after signals. A backend retry cannot commit food to the personal diary.

**API-006 [P0] No infinite synchronous crawl.** Resolve is bounded. An optional refresh can run as an operator job; the app receives an honest pending/unavailable state. A long-running job does not hold the chat UI indefinitely.

**API-007 [P0] Operational controls.** Rate-limit installations/IPs, bound concurrency, cap response size, maintain a source-domain circuit breaker, and expose aggregate cache-hit/fetch/failure metrics without recording user health history.

**API-008 [P0] Self-hosting instructions.** Supply a container build, pinned dependency lock, `.env.example` without secrets, database migrations, backup/restore instructions for public catalog metadata, and a test command. Do not deploy to a public endpoint automatically during code generation.

---

## 16. HealthKit and optional device features

### 16.1 Read-first HealthKit integration

HealthKit is P1: the P0 app must be useful with manual input. Apple requires permission handling and privacy protections; absence of readable samples does not establish that the user denied read permission. [S12-S13]

**HEALTH-001 [P1] Just-in-time permissions.** Ask only for enabled relevant types, such as steps, active energy, resting energy, sleep, workouts, or body mass. Explain each purpose. Do not request all health types at first launch.

**HEALTH-002 [P1] Read-state honesty.** Show unavailable/no data/permission needed guidance without claiming to know a denied read status the API does not reveal. Manual entry remains available.

**HEALTH-003 [P1] Source reconciliation.** Use appropriate HealthKit aggregate queries and explicit source policy. Do not sum overlapping iPhone/watch/provider step totals. Track external identifiers and updates/deletions so repeated imports are idempotent.

**HEALTH-004 [P1] Active-energy deduplication.** A HealthKit active-energy total that includes a workout cannot be added again to that workout's energy. A manual total is an override/reconciliation choice, not an unconditional additive observation.

**HEALTH-005 [P1] Sleep overlap.** Sleep duration unions compatible asleep intervals; it must not sum in-bed time, sleep stages, and an overlapping manual interval as independent sleep.

**HEALTH-006 [P1] Read-only initial release.** Do not write uncertain restaurant estimates or generic manually derived body metrics into HealthKit automatically. A later write feature needs separate, explicit consent, attribution, correction/deletion handling, and review of current Apple requirements. [S13]

**HEALTH-007 [P1] Revocation/deletion.** Disconnecting stops future imports. Deleting app data does not delete third-party HealthKit samples. Any later deletion of app-written samples requires a separate explicit action.

### 16.2 Additional convenience features

**DEVICE-001 [P1] Barcode scanning.** On-device barcode detection resolves a product identifier through the same food resolver. An unreadable barcode or missing catalog record falls back to typed search. It does not infer a product from an incomplete code without confirmation.

**DEVICE-002 [P1] Optional label capture.** Use native text recognition and explicit serving/nutrient review when a user chooses a label photograph. No camera access is required for normal lookup. A low-quality photo cannot overwrite a verified food automatically.

**DEVICE-003 [P1] Widgets and shortcuts.** Favorites, hydration increments, and routine toggles can be exposed through native quick actions. They use the same commands/idempotence as the main app and do not display sensitive details on a lock screen by default.

**DEVICE-004 [P1] Local reminders.** User-configured reminders have quiet hours, time-zone policy, and explicit notification permission. Do not infer medication schedules or send repeated failure/shaming messages. Notifications are not evidence that a task was completed.

**DEVICE-005 [P0/P1] Text and speech.** P0 uses typed input and permits the operating system's keyboard dictation. A dedicated voice feature is P1 and must document its own permission, processing, and offline behavior; do not describe all dictation as necessarily on-device.

**DEVICE-006 [P2] Alternative local models.** Add another provider only behind `NutritionInterpreter` after evaluating memory, license, supported devices, output quality, and energy usage. No parameter-count claim substitutes for the app's evaluation suite.

---

## 17. Privacy, safety, security, and accessibility

### 17.1 Personal-data policy

**PRIV-001 [P0] Local by default.** Personal meals, observations, goals, body metrics, conversations, aliases, and recipes remain on the device. No app account or analytics SDK is necessary for the beta.

**PRIV-002 [P0] No implicit sync.** Do not enable CloudKit/iCloud health-data synchronization by default. Apple imposes restrictions on personal health information and HealthKit data; separately review current rules before designing any sync feature. Exclude sensitive app files from automatic app-managed backup/sync paths as appropriate and document operating-system backup behavior rather than claiming it is under complete app control. [S13]

**PRIV-003 [P0] Storage protection.** Apply platform file protection to personal stores and attachments. Keep tokens in Keychain, not UserDefaults. Do not invent custom cryptography. Document when background access requires a different protection class.

**PRIV-004 [P0] Export and deletion.** Offer separate export of tracker configuration and personal data. Personal export requires confirmation that the file contains sensitive information. Delete-all removes personal stores, conversations, private caches, attachments, and diagnostic files after confirmation; public bundled catalog removal is separately optional.

**PRIV-005 [P0] Logging.** Production logs contain event types, error codes, timing, and nonidentifying operational metrics, not food diary text or health measurements. Debug transcripts are opt-in, local, inspectable, and deletable. Test fixtures must not include other household members' private data.

**PRIV-006 [P0] Resolver consent.** Explain that food identity/market queries leave the device when remote lookup is enabled even though model inference remains local. "Local AI" must not be presented as "no network data ever leaves the phone."

**PRIV-007 [P0] Data minimization.** No precise location, contacts, email, retailer credentials, or background microphone access is needed. Country/market is user-selectable. Reject dependencies that introduce these permissions without a newly approved requirement.

### 17.2 Security and integrity

**SEC-001 [P0] No remote execution.** Imported templates, source pages, food records, and model output are decoded as data. They cannot execute scripts or modify app behavior outside a validated schema.

**SEC-002 [P0] Safe import.** Enforce file size, schema, numeric bounds, reference validity, and complexity limits. Reject zip bombs, oversized embedded objects, unsupported formulas, and cyclic dependencies. Import failure leaves the existing configuration unchanged.

**SEC-003 [P0] Secrets and dependency hygiene.** No provider keys in source or compiled resources. Pin dependencies, document licenses, and scan before distribution. Avoid unnecessary third-party SDKs for simple arithmetic, persistence, or UI components.

**SEC-004 [P0] Health isolation from web content.** A restaurant document cannot access personal tools, private context, or mutation commands. Sanitize displayed markup; do not execute remote JavaScript to render a nutrition result.

**SEC-005 [P0] Safe production configuration.** Debug resolver endpoints, synthetic catalog entries, verbose diagnostics, and permissive network exceptions are unavailable or explicitly isolated in release builds.

### 17.3 Wellness boundaries

**SAFE-001 [P0] Not a medical decision engine.** The app tracks observations and user-chosen goals. It does not diagnose disease, prescribe diets, interpret symptoms clinically, calculate medication doses, or modify treatment based on tracker values. Apple Foundation Models usage rules and App Store requirements apply. [S13, S17-S18]

**SAFE-002 [P0] No false precision.** Source-backed is not exact-to-the-person. Restaurant portions, home recipes, activity expenditure, and resting-energy equations have uncertainty. Estimates remain visibly estimates, including on exported data.

**SAFE-003 [P0] No unsafe reward loop.** Do not award more success for increasingly large deficits, prolonged fasting, excessive exercise, or missing meals. Calories/body/fasting cards are optional. A low logged calorie total must not imply a completed healthy day.

**SAFE-004 [P0] Ambiguous targets.** A likely unit/category error such as "140 g fiber" in a protein-goal conversation requires confirmation. Do not silently substitute protein or enthusiastically endorse an extreme target. Validation separates impossible data from personal choices; it does not invent medical thresholds.

**SAFE-005 [P0] No supplement advice by inference.** Supplement fields track a user-defined routine. The app does not invent a supplement list, recommend doses, or infer that an unchecked routine should be doubled later.

### 17.4 Accessibility and inclusive interaction

**A11Y-001 [P0] Touch targets.** Interactive controls have at least a 44 x 44 point effective hit area. Compact visual icons may be smaller only if their hit regions remain separate and accessible. Do not reproduce the old HTML's cramped hit targets literally.

**A11Y-002 [P0] Dynamic Type.** Support larger text with vertical scrolling and reflow. Never shrink essential nutrient values or hide the Save/Add action solely to retain one-screen fit.

**A11Y-003 [P0] Noncolor status.** Every colored indicator has a text/icon equivalent. VoiceOver announces metric, value, target, status, and incomplete/estimated state.

**A11Y-004 [P0] Accessible builder.** Reordering, grouping, hiding, width changes, and deleting can all be completed without drag gestures. Focus returns predictably after modal editing.

**A11Y-005 [P0] Locale-aware display.** Handle decimal separators, unit preferences, local time display, and dates without changing stored values. English is the initial language; do not hardcode strings into domain calculations. RTL translation is a later supported extension, not claimed as finished.

**A11Y-006 [P0] Appearance.** Test contrast, dark mode, Increase Contrast, Reduce Motion, keyboard navigation where supported, and portrait/landscape reflow. Use native semantic controls where practical. [S20]

---
## 18. Evaluation and acceptance-test plan

### 18.1 Test layers

| Layer | Runs without Apple model? | Required coverage |
|---|---|---|
| Domain unit tests | Yes | Goals, units, nutrients, quantities, recipes, day attribution, revisions, manual adjustments. |
| Property/boundary tests | Yes | Threshold edges, monotonic minimum/maximum rules, scale invariance, no duplicate totals, missingness. |
| Persistence tests | Yes | Transactions, rollback, version migration, import deduplication, rebuilding projections. |
| Parser/contract tests | Yes | Source fixtures, changed layouts, null nutrients, serving bases, API response validation. |
| SwiftUI integration/UI tests | Yes, with mock interpreter | Navigation, builder, accessibility, correction, Undo, errors, compact layout. |
| Local-model evaluations | No; compatible device/model required | Intent, quantity, references, clarification, tool selection, error/refusal handling. |
| Live-source smoke tests | No; internet/source required | Availability and extraction of selected supported sources, separate from deterministic tests. |
| Personal beta | Physical device | Seven days of real use; time, corrections, misses, battery/thermal observations. |

**TEST-001 [P0] Repeatable fixture suite.** Store inputs, initial state, expected structured behavior, source records, and requirement links. A fixture is not just a prompt with an expected English sentence. The provided seed suite is the beginning, not evidence of accuracy.

**TEST-002 [P0] Stable and held-out sets.** Build at least 100 interpretation cases by M3 and 250 by the M6 beta gate. Keep at least 20% held out from prompt tuning, with versioned expected answers. Include multi-turn corrections, negative statements, typos, units, dates, and genuinely ambiguous requests.

**TEST-003 [P0] Critical-invariant gate.** There must be zero observed violations in the release suite for invented committed nutrient values, unauthorized changes, hypothetical meals counted as eaten, duplicate commits, silently lost records, wrong-market auto-commit, and known-missing nutrients converted to zero. This is a test gate, not a claim of mathematically perfect future model behavior.

**TEST-004 [P0] Initial quality targets.** On a declared test set, target at least 95% correct intent, 98% correct unambiguous quantity/unit extraction, and 95% correct exact-food resolution among supported covered records. Report denominators, abstentions, clarification rates, and unsupported-source cases separately. A model that asks a justified clarification must not be scored as hallucinating or as a confident correct resolution.

**TEST-005 [P0] Deterministic numeric gate.** Every pure-domain expected calculation and boundary case must pass. Use explicit tolerances for numeric representation, never broad percentage tolerances that conceal a portion error.

### 18.2 Required regression cases

The following are minimum behaviors; implement them as executable tests at the earliest relevant milestone.

| ID | Given / when | Required result |
|---|---|---|
| REG-001 | Fresh day has no water observation | Hydration is unrecorded, not a confirmed zero or a completed day. |
| REG-002 | Explicitly record zero water | Zero is stored as known and evaluated; not mistaken for absent data. |
| REG-003 | Owner water values 1.9, 2.0, 3.0 L | Near, met, met respectively; no hidden extra 5% tolerance. |
| REG-004 | Owner protein values 129, 130, 170 g | Near, met, met; the displayed 140-150 target does not alter the explicit 130 threshold. |
| REG-005 | Owner fiber 33.24, 33.25 g | Near then met, because this template explicitly retains its stated 5% fiber tolerance. |
| REG-006 | An activity day has 12,000 steps and workout done | Exercise met; overshooting the displayed step band is not a failure. |
| REG-007 | 8,000 steps, workout not completed | Exercise near, not met. |
| REG-008 | Workout completed, no step observation | Exercise near with missing-steps explanation, not a fake 0-step observation. |
| REG-009 | New morning, PM routine not due | No red failure solely because PM is not yet complete. |
| REG-010 | Calorie balance changes gray/yellow/green/red | Its card remains full-width in every state. |
| REG-011 | Owner net ratio exactly -0.05, 0, +0.05 | Near for all three boundaries; below -0.05 met, above +0.05 outside. |
| REG-012 | Intake logged but day/active energy incomplete | Net is provisional or incomplete, not silently a final successful deficit. |
| REG-013 | Active energy total includes workout | No second addition of the workout's calories. |
| REG-014 | Reference profile 93 kg, 178 cm, age 33, +5 equation constant | Estimated resting energy 1,882.5 kcal/day, rounded only for display. |
| REG-015 | Overnight interval 23:30 to next-day 07:30 | Eight hours with correct displayed dates. |
| REG-016 | New York 2026-03-08 01:30-05:00 to 03:30-04:00 | One elapsed hour across the DST jump, not two. |
| REG-017 | Travel to a different time zone after logging yesterday | Yesterday's stored meals retain their assigned log day. |
| REG-018 | "What about a poke bowl?" | Preview only; no intake change. |
| REG-019 | "I didn't have the bowl" | No positive log; offer correction if a relevant committed entry exists. |
| REG-020 | "I threw out the oatmeal" | Cancel its draft; no whey/milk/yogurt calories counted as consumed automatically. |
| REG-021 | "Two kotlets, 100 g each" | 200 g finished dish; recipe unresolved, not 100 g ground beef. |
| REG-022 | "Yogurt has fat" after a nonfat match | Candidate revision/clarification to full-fat variant, not reuse of nonfat values. |
| REG-023 | "29 grams tuna, same as last time" with ambiguous context | Ask whether food mass or protein-per-can; no invented 210 kcal can. |
| REG-024 | "No lentils, 100 g beans" after a dinner draft | Remove lentils and set beans to 100 g; atomic revision, not two dinners. |
| REG-025 | Scale label: 60 kcal / 9 g protein per 56 g ham | 112 g gives 120 kcal / 18 g protein. |
| REG-026 | Same ham, exact 4 oz mass | 113.3980925 g; about 121.498 kcal / 18.225 g protein before display rounding. |
| REG-027 | Two tablespoons versus two servings | Use the record's actual serving mapping, not an assumed equivalence. |
| REG-028 | 100 g cooked pasta versus 100 g dry pasta | Different prepared-state records; no substitution without confirmation. |
| REG-029 | A source has energy/protein but no fiber | Fiber unknown; summary coverage incomplete, not fiber zero. |
| REG-030 | Synthetic 1,200 kcal recipe, 1,000 g cooked yield, 200 g eaten | 240 kcal. Changing cooked yield changes per-gram density, not the original batch calories by itself. |
| REG-031 | User clicks Add twice on the same preview | One meal entry. |
| REG-032 | User says "another one" after a committed favorite | A distinct second entry with a new mutation ID. |
| REG-033 | Current protein 100, set daily total 120, add 30 | Auditable +20 adjustment, final 150; no competing totals. |
| REG-034 | Undo a correction after restart | Restore the prior revision once; do not duplicate food. |
| REG-035 | Goal edit saved effective today | Previous days keep previous goal versions. |
| REG-036 | Hide fasting; switch templates | Existing interval history remains; no duplicated events. |
| REG-037 | Custom caffeine maximum exceeded | Correct maximum-goal behavior; no inherited "above goal stays green" rule. |
| REG-038 | Custom note or weight trend with no goal | Unscored; no arbitrary red/green outcome. |
| REG-039 | Builder import contains cyclic derived fields | Reject atomically with actionable explanation. |
| REG-040 | Offline cached favorite | Logs without any network or cloud-model request. |
| REG-041 | Offline unknown restaurant | Preserved draft/unavailable state; no guessed official nutrition. |
| REG-042 | Model unavailable or refuses | Manual search remains usable; no record created from an error. |
| REG-043 | Source text instructs upload of diary | Ignore instruction; no private data or mutation tool exposure. |
| REG-044 | Restaurant table layout changes | Quarantine/reject extraction; no zero-filled replacement. |
| REG-045 | Brand source omits fat variant; two candidates | Ask selection rather than auto-commit. |
| REG-046 | US selected; only Canadian menu result found | Not an exact US match; explicit market choice required. |
| REG-047 | Catalog update interrupted or checksum invalid | Old catalog remains usable. |
| REG-048 | Legacy payload imported twice | One imported observation set. |
| REG-049 | Accessibility text size grows | Vertical scrolling/reflow; Add and Save remain reachable. |
| REG-050 | Cancel request; response arrives late | No committed meal or changed goal. |
| REG-051 | New source version has different calories | New lookups can use it; already committed meals retain old snapshots. |
| REG-052 | Small Sbarro portion lacks a supported serving weight | No confident conversion to 100 or 150 g; ask or show an estimate. |
| REG-053 | Shared public cache receives a private recipe | Reject global publication; recipe stays private. |
| REG-054 | User resets one day | Only that day's tracked records change; history/configuration remain; Undo available. |
| REG-055 | Missing day in a 30-day trend | Gap/incomplete marker rather than 0 intake and failure score. |
| REG-056 | Very low partial intake versus full-day resting estimate | No encouraging "excellent deficit" message. |

### 18.3 Developer Lab

**TEST-006 [P0] On-device evaluation runner.** In debug builds, select suite/prompt version, run sequentially, pause/cancel, and inspect individual interpreted objects and tool outcomes. Store run metadata and a summary locally. Thermal/resource warnings can pause a run instead of forcing continued inference.

**TEST-007 [P0] Privacy-aware exports.** Export evaluation results with test IDs, expected/actual structures, timing, OS/app/prompt/schema versions, and failure reason. Real-user traces require individual selection/redaction; exporting the whole personal diary is not the default.

**TEST-008 [P0] Network assertions.** Inspect app network activity or use injected networking tests to verify no inference endpoint, no secret paid-provider fallback, and no network request on a fresh local hit. A browser opened intentionally by the user is identified separately from automatic resolver traffic.

**TEST-009 [P0] Model migration regression.** Re-run the stable and held-out suites after a material OS/model change. Record that a changed OS may change the underlying system model even when app prompts are identical. [S06]

**TEST-010 [P0] Seven-day personal pilot.** Log real use for seven consecutive days on the 16e. Record supported attempts, corrections, necessary clarifications, unresolved products, median/P95 latency, offline success, and network costs. Target at least 90% of supported clear entries needing no correction; present the actual measured result, not a forecast.

### 18.4 Traceability and evidence

**TEST-011 [P0] Requirement coverage.** Every P0 requirement has a unit/integration/UI test, a reproducible manual acceptance procedure, or an explicitly documented blocker. Maintain the supplied requirements index with test references and status. A blank status is not "passed."

**TEST-012 [P0] Honest execution reporting.** Distinguish passed, failed, not run, blocked by environment, and not applicable. A Linux/cloud environment cannot demonstrate physical iPhone inference by returning mocked model output. Real-device acceptance remains separate.

---

## 19. Performance, operational budgets, and diagnostics

The following are initial engineering budgets for the iPhone 16e prototype. Measure and revise them with evidence. They are not published performance claims about the device or Apple's model.

| Operation | Initial target / limit | Measurement |
|---|---|---|
| Direct dashboard increment | Visible response within 100 ms; persistence independently confirmed | UI signpost and save completion. |
| Cached food search and calculation | P95 <= 300 ms, excluding typing | Local repository + pure calculation. |
| Warm local interpretation | P95 <= 5 seconds for bounded supported input | Physical 16e, documented power/thermal state. |
| Cold local interpretation | P95 <= 10 seconds after model is available | Separate from initial OS-model download. |
| Foreground remote resolution | Return outcome within 15 seconds or explicit timeout/pending | Network + parsing, not infinite retries. |
| Source fetch | 10-second request timeout initially; bounded overall resolution | Adapter metrics. |
| Source document size | 10 MB initial limit; larger approved offline ingestion jobs only | Before and during decompression. |
| Agent work | Four read-tool calls, three generations including one repair | Per-turn trace. |
| Context | Fit documented model window; reserve output headroom | SDK token accounting where available; conservative input limits otherwise. |
| Core catalog | Target <= 100 MB; optional >250 MB requires consent | Build report with indexes. |
| Debug retention | Default last 100 selected runs or 10 MB, whichever first | Local settings/rotation. |
| Cloud inference | Zero P0 requests | Configuration and network evidence. |
| Paid nutrition/search providers | Zero unless separately enabled in a later scope | Resolver usage counters. |

**PERF-001 [P0] Separate timing stages.** Instrument interpretation, private lookup, local catalog, backend, source fetch, parsing, calculation, and save. A single total time cannot reveal which component needs optimization.

**PERF-002 [P0] Resource-aware execution.** No continuous model polling, background webcam inference, or automatic full-history regeneration. Cancel obsolete work; avoid fetching duplicate source documents; do not prewarm the model repeatedly while backgrounded.

**PERF-003 [P0] Cost dashboard.** Developer Lab shows local-hit count, backend hits, live-source fetches, discovery/paid calls, and error types. Backend hosting and bandwidth are not described as literally free just because third-party API use is zero.

**PERF-004 [P0] Graceful limits.** Budget exhaustion is an explicit outcome with manual/local alternatives. Paid fallback does not activate merely because a free source is slow.

**PERF-005 [P0] Device reports.** Before beta, record installed OS/build, app build, dataset size, peak measured app memory, repeated-use latency, and qualitative thermal/battery behavior. Do not invent a minimum RAM or model-token speed requirement from parameter counts alone.

**PERF-006 [P0] Search scalability.** Benchmark representative queries over the actual built catalog, including common prefixes, brand aliases, and barcode hits. A full scan of a multi-million-row corpus per keystroke is not acceptable; search work is debounced and cancellable.

---

## 20. Coding sequence and definition of done

### 20.1 How Codex should work

Keep root `AGENTS.md` concise and point it to this PRD and the implementation plan. Do not paste the entire specification into the instruction file: Codex supports repository instruction files and has documented instruction-discovery/size behavior. [S19]

For each implementation slice:

1. Read the relevant requirements and existing code; state the slice's scope and assumptions.
2. Add/update pure contracts and tests before complex UI/model behavior where practical.
3. Implement the smallest vertical feature that can be exercised.
4. Run applicable tests and formatting/static checks in the available environment.
5. Report changed files, passed/failed/not-run tests, known limitations, and the next milestone.
6. Stop at the milestone boundary for review; do not add paid services, unrelated frameworks, or new data collection as conveniences.

### 20.2 Milestones and exit gates

| Milestone | Required implementation | Exit evidence |
|---|---|---|
| M0: environment and model spike | Xcode project, physical-device build instructions, availability handling, one structured interpretation, mock interpreter | Successful Mac build/device smoke test or explicit environment blocker; no claims based on a mock. |
| M1: domain and tracker | Core types, goal evaluator, observation store, compact Today, history, owner template, direct inputs, light/dark | Boundary/calculation tests; persistence/relaunch; seven indicators/full-width balance screenshot. |
| M2: visual builder | Category library, field inspector, layout editing, preview states, save/versioning, import/export | Create caffeine and stretch fields without code; hide fasting; change water threshold; preserve history. |
| M3: local nutrition/chat | Small sourced catalog, portion/recipe engine, aliases, drafts, safe commit/correction/Undo, local model routing | At least 100 interpretation fixtures; critical regressions; airplane-mode known-food log. |
| M4: direct-web resolver | Optional service, registry, real adapters, provenance, caching, safe fetch, query consent | Three restaurants/two brands or reviewed replacements; cache hit avoids refetch; parser failure handled. |
| M5: catalog import/update | USDA normalization, search indexes, size reports, pack activation/rollback | Actual measured catalog report; incomplete update does not break app; historical snapshots preserved. |
| M6: personal beta | Developer Lab, held-out suite, accessibility/privacy review, TestFlight or device distribution | 250 cases; seven-day pilot; published pass/fail evidence; no unresolved critical P0 failures. |
| P1 | HealthKit, widgets, reminders, optional barcode/OCR, more sources/packs | Feature-specific permission, deduplication, and reliability tests. |
| P2 | Alternative local models, broader platforms, inventory, separately reviewed sync | New PRD/decision record; not silently included in P0. |

P0 includes M0-M6, but the first working build should be much smaller. The visual builder is an essential requirement, not an optional polish item to be discarded after building chat.

### 20.3 Development environment checklist

- Confirm Mac/Xcode availability and the selected iOS SDK before specifying exact commands.
- Create a real iOS project/scheme and a pure Swift package; commit project-generation configuration if using a generator.
- Configure the owner's signing team locally; never commit private signing credentials.
- Pair the iPhone 16e and follow Apple's Developer Mode/device-development instructions as applicable. [S08]
- Enable Apple Intelligence and wait for model readiness. Verify availability in the app rather than assuming setup is complete. [S02-S03]
- Confirm airplane-mode interpretation after the system model is installed; first-time model provisioning is a separate setup case.
- Cloud Codex may develop code and run supported pure/backend tests, but Xcode/device work requires an appropriate Mac environment. Record that distinction in every handoff.

Example command categories, to be replaced by the actual generated paths/scheme:

```bash
# Pure domain package, where the installed Swift toolchain supports it:
swift test --package-path packages/WellnessCore

# Backend and parser tests after their project has been created:
python -m pytest services/nutrition-resolver/tests

# On the Mac, discover the real scheme/destination before building:
xcodebuild -list -project apps/ios/NimaWellness/NimaWellness.xcodeproj
xcodebuild -showdestinations -scheme NimaWellness \
  -project apps/ios/NimaWellness/NimaWellness.xcodeproj
```

These are implementation instructions, not commands already executed against an application in this requirements pack.

### 20.4 Definition of done for the personal beta

- [ ] The app installs on the test phone and reports local-model readiness accurately.
- [ ] Manual tracker, known-food lookup, calculations, and history work offline.
- [ ] The visual builder can add, remove, reorder, and configure fields/goals without code.
- [ ] Owner layout and status behavior match the explicit revised rules, including full-width calorie balance.
- [ ] Chat never counts a preview as consumed and supports atomic corrections and Undo.
- [ ] Every committed nutrient value is traceable to a source-backed record, explicit user entry, or accepted labeled estimate.
- [ ] Unknown nutrients, quantities, markets, and preparation states are not silently invented.
- [ ] Saved-source updates do not rewrite historical meal nutrition.
- [ ] Direct official-source adapters work within documented coverage; unsupported sources fail honestly.
- [ ] No cloud LLM, paid nutrition API, or paid discovery request occurs in the P0 configuration.
- [ ] Catalog update/import failures cannot destroy personal data or the last working pack.
- [ ] Privacy, deletion/export, accessibility, and permission tests pass.
- [ ] Required regression cases and held-out evaluations have results attached.
- [ ] Real-device performance and seven-day pilot results are recorded, including shortcomings.
- [ ] No high-severity correctness/data-loss/security issue remains unaddressed.

---

## 21. Risks and decisions to revisit

| Risk / unresolved decision | Adopted default | Validation / mitigation |
|---|---|---|
| Mac/Xcode availability unknown | Native iOS still the chosen product | Confirm environment at M0; do not pretend cloud CI is an iPhone. |
| Model availability/refusal/OS change | Local model optional for manual functionality | Runtime availability checks, mocks, regression suite, manual fallback. |
| Model misunderstands a gram quantity or a correction | Review-first typed proposals | Ambiguity tests and deterministic commit validation. |
| Restaurant coverage/portions unavailable | Explicit unsupported/estimated outcome | Audit initial sources before promising adapters. |
| Direct lookup is not unrestricted free search | Curated registry + cache | Discovery off by default; budget provider separately if added. |
| Public-source reuse constraints | Per-source review and permitted evidence storage | No automatic redistribution of copied catalogs. |
| Large branded catalog/update overhead | Small local core; full hosted optional | Measure real build size, query latency, and update bandwidth. |
| Aggressive one-screen layout hurts accessibility | Compact summary + detail editors | Physical 16e and Dynamic Type tests. |
| User-configurable fields create formula/scope explosion | Typed registry, small named calculation set | No arbitrary code execution; dependency validation. |
| Goal changes alter historical meaning | Effective-dated versions | Past-day regression tests and explicit re-evaluation option. |
| Energy estimate interpreted as exact TDEE | Clearly labeled estimate, provisional day | No double counting; no automatic deficit escalation. |
| No automatic cloud backup increases loss risk | Local storage + explicit export | Explain tradeoff; separately review any later sync design. |
| Medication/symptom categories drift into clinical product | Manual notes/routines only | No diagnostic engine or dosing logic. |
| Scope expands to all grocery inventory | Food IDs remain extensible | Inventory workflow remains P2. |
| Product name/distribution/monetization not final | Nima Wellness, personal beta | Decide after a useful seven-day pilot. |

Record changed decisions in `docs/decisions/` with reason, evidence, affected requirements, and tests. Do not silently change defaults such as cloud inference, privacy, or goal semantics to make implementation easier.

---

## 22. Reference configuration and calculation examples

### 22.1 Configuration shape

The following illustrative configuration demonstrates the separation of display targets, evaluation rules, layout, and data identity. It is not the entire owner template and must be validated by the schema implemented in M2.

```json
{
  "schemaVersion": 1,
  "templateID": "owner-example",
  "version": 1,
  "name": "Owner example",
  "effectiveFrom": "2026-09-13",
  "metrics": [
    {
      "id": "nutrition.protein",
      "name": "Protein",
      "category": "nutrition",
      "valueType": "quantity",
      "canonicalUnit": "g",
      "aggregation": "sum",
      "input": {"kind": "counter", "step": 10},
      "goal": {
        "kind": "minimum",
        "period": "day",
        "displayTarget": {"lower": 140, "upper": 150, "unit": "g"},
        "metMinimum": 130,
        "nearMinimum": 97.5,
        "missingPolicy": "incomplete"
      }
    },
    {
      "id": "hydration.water",
      "name": "Water",
      "category": "hydration",
      "valueType": "quantity",
      "canonicalUnit": "mL",
      "displayUnit": "L",
      "aggregation": "sum",
      "input": {"kind": "counter", "step": 250},
      "goal": {
        "kind": "minimum",
        "period": "day",
        "displayTarget": {"lower": 2000, "upper": 2500, "unit": "mL"},
        "metMinimum": 2000,
        "nearMinimum": 1500,
        "missingPolicy": "incomplete"
      }
    },
    {
      "id": "custom.caffeine",
      "name": "Caffeine",
      "category": "intakeHabits",
      "valueType": "quantity",
      "canonicalUnit": "mg",
      "aggregation": "sum",
      "input": {"kind": "number", "step": 25},
      "goal": {"kind": "trendOnly"}
    }
  ],
  "layout": [
    {"cardID": "protein-card", "metricIDs": ["nutrition.protein"], "width": "half", "order": 0},
    {"cardID": "water-card", "metricIDs": ["hydration.water"], "width": "half", "order": 1},
    {"cardID": "caffeine-card", "metricIDs": ["custom.caffeine"], "width": "full", "order": 2}
  ]
}
```

The owner template must also include the other explicitly configured fields/statuses in sections 6-9. The example does not prescribe a caffeine limit.

### 22.2 Deterministic calculation examples

**Label transcription fixture: ham.** The user-provided photograph shows 60 kcal and 9 g protein per 56 g serving. Use this for arithmetic tests, not as a claim that a current retail product has been independently reverified. [U01]

```text
112 g / 56 g = 2 servings
energy = 2 * 60 = 120 kcal
protein = 2 * 9 = 18 g

4 avoirdupois ounces = 113.3980925 g
energy = 113.3980925 / 56 * 60 = 121.49795625 kcal
protein = 113.3980925 / 56 * 9 = 18.22469344 g approximately
```

**Label transcription fixture: shake.** A provided label shows 130 kcal, 30 g protein, and 1 g fiber for the full container. Two full containers give 260 kcal, 60 g protein, and 2 g fiber. These arithmetic results come from the fixture, not a general assumption about all products from that brand. [U02]

**Label transcription fixture: meal tray.** The provided Factor tray label shows 500 kcal, 43 g protein, and 7 g fiber for a 340 g tray. Half the tray gives 250 kcal, 21.5 g protein, and 3.5 g fiber under the explicit equal-half assumption. [U03]

**Synthetic uncertainty example.** A restaurant item has known energy/protein but missing fiber. Adding it to a meal with 5 g known fiber yields `knownFiberTotal = 5 g` and `fiberCoverage = incomplete`, not a complete meal fiber value of 5 g.

**Synthetic mutation example.** Draft A contains lentils and beans. Revising it to "no lentils, 100 g beans" creates Draft A revision 2. Only committing revision 2 changes the day; revision 1 is not an additional consumed meal.

---

## 23. Sources and implementation references

Sources were checked during preparation on 2026-09-13. Apple documentation can include newer OS features; this specification intentionally adopts a stable iOS 26 baseline and requires availability checking instead of assuming every current documentation example works on that baseline. External product behavior and policies must be rechecked before implementation/distribution.

### Apple platform and local model

- **[S01] Foundation Models framework.** `https://developer.apple.com/documentation/foundationmodels` — framework entry point and platform APIs.
- **[S02] Apple Intelligence requirements and setup.** `https://support.apple.com/en-us/121115` — supported devices, language/region/setup and model readiness prerequisites.
- **[S03] SystemLanguageModel.** `https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel` — explicitly selecting the on-device system model and checking availability.
- **[S04] Guided generation.** `https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation` — typed generation and schema design.
- **[S05] Tool calling.** `https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling` — exposing application tools to generation.
- **[S06] Model/prompt changes.** `https://developer.apple.com/documentation/FoundationModels/updating-prompts-for-new-model-versions` — regression testing when system model behavior changes.
- **[S07] Context management.** `https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window` — context-window accounting and mitigation.
- **[S08] Device development.** `https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device` — device development setup and Developer Mode.

### Nutrition data, calculations, and indexing

- **[S09] USDA FoodData Central.** `https://fdc.nal.usda.gov/` — data types, source documentation, public-domain/CC0 statement.
- **[S10] USDA dataset downloads.** `https://fdc.nal.usda.gov/download-datasets/` — release dates and downloadable file sizes.
- **[S11] USDA API guide.** `https://fdc.nal.usda.gov/api-guide/` — API access, rate limits, and key requirements when the optional API is used.
- **[S14] Mifflin et al., original resting-energy equation paper.** `https://pubmed.ncbi.nlm.nih.gov/2305711/` — equation basis; not evidence that it exactly measures an individual user's expenditure.
- **[S15] SQLite FTS5 documentation.** `https://sqlite.org/fts5.html` — local lexical full-text search implementation option.
- **[S16] Schema.org NutritionInformation.** `https://schema.org/NutritionInformation` — structured nutrition fields that some websites may expose.

### Privacy, permissions, safety, and development workflow

- **[S12] HealthKit authorization.** `https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data` — granular permissions and read-access behavior.
- **[S13] HealthKit privacy and App Store requirements.** `https://developer.apple.com/documentation/healthkit/protecting-user-privacy` and `https://developer.apple.com/app-store/review/guidelines/` — privacy, health-data use, and distribution review requirements.
- **[S17] Foundation Models acceptable-use requirements.** `https://developer.apple.com/support/terms/acceptable-use-requirements-for-the-foundation-models-framework` — safety and prohibited high-risk use boundaries.
- **[S18] Model output safety.** `https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output` — safety handling and application responsibilities.
- **[S19] Codex repository instructions.** `https://developers.openai.com/codex/guides/agents-md` — repository `AGENTS.md` discovery and instruction guidance; this URL may redirect to OpenAI's current documentation host.
- **[S20] Apple accessibility guidance.** `https://developer.apple.com/design/human-interface-guidelines/accessibility` — accessible native UI principles.

### Project-specific evidence

- **[L01] Saved legacy tracker.** `nima-wellness-tracker-calorie-balance-v19.html`, from the user's File Library, saved 2026-09-07. Relevant portions inspected include layout, colors, localStorage handling, goal/status calculations, activity logic, and supplement controls. The raw original file is not bundled in this pack; `docs/LEGACY_BASELINE.md` records the implementation-relevant findings. The live website was not successfully inspected.
- **[U01] User-provided ham label photograph.** `IMG_4F580170-5ACB-45F8-BCDF-E1A8A93C670C.jpeg` — 60 kcal and 9 g protein per 56 g, used as a transcribed arithmetic fixture.
- **[U02] User-provided shake label photograph.** `AB891CF7-FC96-44D5-A72A-C5E2979D1656.jpeg` — 130 kcal, 30 g protein, 1 g fiber per container.
- **[U03] User-provided meal-tray label photograph.** `05716F74-EAB3-479C-B1FD-595DB19DC9C1.jpeg` — 500 kcal, 43 g protein, 7 g fiber per 340 g tray.

Personal label images, unrelated files, and the user's private health history are not included in the requirements bundle. The examples preserve only the minimum facts needed to test the intended behavior.

---

**Implementation starting point:** M0, followed by a small M1 slice. Do not begin with the full USDA branded catalog, a hundred web adapters, HealthKit, or a different local model. Prove correct local interpretation and deterministic tracker behavior first, then grow coverage with measured evidence.
