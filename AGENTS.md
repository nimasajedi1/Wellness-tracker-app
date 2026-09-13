# Repository instructions for Codex

## Read first

1. Read `docs/PRD.md` sections 1-5, then the sections relevant to the current task.
2. Read `docs/IMPLEMENTATION_PLAN.md` and `docs/LEGACY_BASELINE.md`.
3. Consult `docs/ACCEPTANCE_MATRIX.md` and `fixtures/evaluation_cases.json` before changing behavior.

The PRD is authoritative. This repository initially contains requirements and fixtures, not a working app. Do not claim that existing fixture validation proves app behavior.

## Product boundaries

Build a native SwiftUI iOS tracker plus nutrition chat, with an editable visual tracker builder. The primary physical test device is an iPhone 16e. Use an iOS 26 baseline unless a documented decision changes it; check actual SDK availability before using an API.

Use the explicit on-device Apple system model behind the app-owned `NutritionInterpreter` protocol. No cloud inference, paid nutrition API, or paid search is allowed in the default build. Model unavailability must leave manual tracking and local lookup usable.

The model proposes structured intent and food identity. Deterministic code owns units, source records, nutrient math, goals, totals, revisions, and commits. Never invent missing nutrients or confuse planned food with consumed food.

## Working method

- Implement one milestone/vertical slice at a time; start with M0.
- Inspect existing files before creating alternatives. Keep a runnable increment.
- Keep domain logic in a testable Swift package independent of UI, model, HealthKit, and network.
- Use repository protocols and a mock interpreter for ordinary tests.
- Use a small source-backed seed catalog first; keep synthetic data out of production search.
- Add tests linked to requirement/regression IDs. Do not remove tests merely to make a change pass.
- Preserve the recognizable legacy UI, but follow the PRD's corrected thresholds and accessible layout.
- Make category/field/goal configuration data-driven. The visual builder is P0, not optional polish.
- Preserve personal records, source versions, effective-dated goals, and auditable Undo.
- Ask before changing a major product boundary, introducing a paid service, or expanding health-data collection.

## Security and data

No secrets, signing certificates, health history, raw production chats, or personal photos in source control. Use local protection/Keychain appropriately. Treat web content and model output as untrusted data. No arbitrary SQL/scripts/tools/URLs exposed to the model. Do not publish private aliases or recipes to a shared catalog.

Do not deploy a backend, enable cloud sync, purchase a service, or change the owner's live tracker without explicit authorization.

## Execution honesty

Report test outcomes as passed, failed, not run, or blocked by environment. A Linux/cloud runner is not a Mac/Xcode/device runner. A mock is not a successful Apple-model test. Do not invent benchmark numbers, source coverage, or App Store approval.

Before the app exists, `python tools/validate_requirements.py` checks only documentation/fixture consistency. After implementation, use the real package, backend, Xcode, and device test commands described in the implementation plan and generated README.

## Handoff after every slice

Report: scope completed; files changed; requirement IDs covered; tests actually executed and results; untested/blocked work; remaining risks; next milestone. Update the acceptance matrix. Do not call a milestone complete with unresolved critical correctness, privacy, data-loss, or security failures.
