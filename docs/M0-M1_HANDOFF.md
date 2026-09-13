# Handoff: M0 scaffolding + M1 tracker slice (+ early M2/M3 contracts)

**Milestone / slice:** M0 (repository scaffolding, interpreter boundary, Apple
adapter, mock, availability UI) plus the M1 deterministic tracker slice
(domain types, goal evaluator, energy engine, owner template, SwiftData
persistence, Today/History UI) and the earliest M2/M3 contracts (configuration
schema + builder slice, food/portion/recipe/ledger engines, chat preview flow).

**Requirements addressed (implemented in code; device acceptance pending):**
ARCH-001..005, UI-001..013 (partial 009/013), UI-015..017 (partial), BUILD-003/
004/006/007/008/010/011/012/013/014/015 (partial slices), GOAL-001..010,
ENERGY-001/002/005/006/007/008 (double-count guard, provisional bands),
FOOD-001..002/005..009/011/015..017/019/020, CHAT-001 (preview-first)/003
(ledger revisions)/005/011 (single generation)/013/014/015 (validation)/016/
017/018, STORE-001..010, STORE-011..015 (import module), PRIV-001/002 (local
store, cloudKitDatabase: .none), SAFE-002/003 (labels, no deficit reward),
A11Y-001/003 (44-pt targets, non-color status).

**Files changed:** `packages/WellnessCore/**` (domain package + 5 test files),
`apps/ios/NimaWellness/**` (SwiftUI app sources, project.yml, XCODE_SETUP.md),
`docs/`, `fixtures/`, `tools/` (requirements pack), `README.md`, `.gitignore`.

**Behavior demonstrated:** requirements-pack validation only (45/45 checks
pass via `python3 tools/validate_requirements.py`).

**Tests executed with commands and outcomes:**
- `python3 tools/validate_requirements.py` → 45/45 PASS.

**Tests not run and why:**
- `swift test --package-path packages/WellnessCore` — NOT RUN: no Swift
  toolchain in this Linux environment (download.swift.org blocked by the
  network policy). The suite encodes REG-001..017 (evaluator/energy/time),
  REG-021/025/026/029/030 (portions/recipes), REG-031..034/054 (ledger),
  REG-039/048 (config/import), REG-018/020/023/042 (mock interpreter). Run it
  first on the Mac; failures there are expected to be small syntax-level fixes,
  not design gaps.
- Xcode build, UI tests, physical-device inference — BLOCKED BY ENVIRONMENT
  (TEST-012): requires Mac/Xcode and the iPhone 16e.

**Device evidence, if actually collected:** none — nothing on-device is claimed.

**Remaining correctness/privacy/security risks:**
- Swift sources are unverified by a compiler; expect minor fixes on first build.
- The M0 exit gate (one validated on-device structured extraction with
  networking disabled) is open until the owner runs the smoke test in
  XCODE_SETUP.md.
- Chat correction flow (reviseMeal via conversation) and observation logging
  via chat are directed to manual UI in this slice (M3 work).
- Builder import/export UI, preview scenarios, and template library are
  partial; the schema, validator, and versioned publish path are in place.
- Energy settings (resting input, balance mode, completed days) persist via
  UserDefaults in this slice; move into the versioned store with M2.

**Next slice:** run domain tests + first build on the Mac, fix compiler
findings, complete M1 exit-gate screenshots (seven indicators, full-width
balance in all states), then M2 builder preview scenarios and import/export UI.
