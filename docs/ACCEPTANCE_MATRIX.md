# Acceptance and verification matrix

The normative acceptance criteria are in `PRD.md`. This index makes their implementation/test coverage trackable. Suggested verification methods are not claims that tests exist or have passed. The regression IDs refer to the PRD and seed JSON; the implementation must provide executable harnesses/manual procedures.

**Initial status for every requirement:** not implemented / not run. Pack validation does not change that status.

After each coding slice, replace the final column with the implementation/test reference, actual outcome, environment, and date. P1/P2 remain explicitly deferred until scheduled. Combined P0/P1 requirements are implemented for their P0 manual path first and their P1 integration path later.

| Requirement | Priority | Contract | Suggested verification | Seed regression links | Evidence / status |
|---|---|---|---|---|---|
| OUT-001 | P0 | Daily usability | UI / integration / pilot | Add implementation-specific case | Not implemented / not run |
| OUT-002 | P0 | Local-first operation | UI / integration / pilot | REG-040, REG-041 | Not implemented / not run |
| OUT-003 | P0 | Testable improvement | UI / integration / pilot | Add implementation-specific case | Not implemented / not run |
| OUT-004 | P0 | Configurability without code | UI / integration / pilot | Add implementation-specific case | Not implemented / not run |
| SCOPE-001 | P0 | Codex MUST implement one milestone at a time and leave the project runnable | Milestone review | Add implementation-specific case | Not implemented / not run |
| SCOPE-002 | P0 | Disabled or deferred functionality MUST be labeled or absent | Milestone review | Add implementation-specific case | Not implemented / not run |
| SCOPE-003 | P0 | Requirements needed for builder extensibility are P0 even when a particular data source, such as HealthKit, is P1 | Milestone review | Add implementation-specific case | Not implemented / not run |
| ARCH-001 | P0 | Pure domain boundary | Architecture / unit / device | Add implementation-specific case | Not implemented / not run |
| ARCH-002 | P0 | Model abstraction | Architecture / unit / device | REG-042 | Not implemented / not run |
| ARCH-003 | P0 | Explicit local provider | Architecture / unit / device | Add implementation-specific case | Not implemented / not run |
| ARCH-004 | P0 | Availability and failure states | Architecture / unit / device | REG-042 | Not implemented / not run |
| ARCH-005 | P0 | Bounded execution | Architecture / unit / device | Add implementation-specific case | Not implemented / not run |
| ARCH-006 | P0 | Native port, not a remote page wrapper | Architecture / unit / device | Add implementation-specific case | Not implemented / not run |
| ARCH-007 | P2 | Web parity boundary | Architecture / unit / device | Add implementation-specific case | Not implemented / not run |
| UI-001 | P0 | No sign-in wall | UI / accessibility / persistence | Add implementation-specific case | Not implemented / not run |
| UI-002 | P0 | Shared state | UI / accessibility / persistence | Add implementation-specific case | Not implemented / not run |
| UI-003 | P0 | Preserve state | UI / accessibility / persistence | Add implementation-specific case | Not implemented / not run |
| UI-004 | P0 | Compact and expanded modes | UI / accessibility / persistence | REG-049 | Not implemented / not run |
| UI-005 | P0 | Seven owner indicators | UI / accessibility / persistence | REG-010 | Not implemented / not run |
| UI-006 | P0 | Values and controls | UI / accessibility / persistence | Add implementation-specific case | Not implemented / not run |
| UI-007 | P0 | Supplement controls | UI / accessibility / persistence | Add implementation-specific case | Not implemented / not run |
| UI-008 | P0 | Activity alignment | UI / accessibility / persistence | Add implementation-specific case | Not implemented / not run |
| UI-009 | P0 | Dates and duration | UI / accessibility / persistence | Add implementation-specific case | Not implemented / not run |
| UI-010 | P0 | Save state and reset | UI / accessibility / persistence | REG-054 | Not implemented / not run |
| UI-011 | P0 | Non-destructive preview | UI / accessibility / persistence | REG-018 | Not implemented / not run |
| UI-012 | P0 | Corrections | UI / accessibility / persistence | REG-034 | Not implemented / not run |
| UI-013 | P0 | Keyboard behavior | UI / accessibility / persistence | Add implementation-specific case | Not implemented / not run |
| UI-014 | P0 | Minimal questioning | UI / accessibility / persistence | Add implementation-specific case | Not implemented / not run |
| UI-015 | P0 | History | UI / accessibility / persistence | REG-035, REG-055 | Not implemented / not run |
| UI-016 | P0 | Settings | UI / accessibility / persistence | Add implementation-specific case | Not implemented / not run |
| UI-017 | P0 | Neutral language | UI / accessibility / persistence | Add implementation-specific case | Not implemented / not run |
| BUILD-001 | P0 | Template entry points | Builder UI / schema / unit | Add implementation-specific case | Not implemented / not run |
| BUILD-002 | P0 | Three builder areas | Builder UI / schema / unit | Add implementation-specific case | Not implemented / not run |
| BUILD-003 | P0 | Layout editing | Builder UI / schema / unit | REG-010 | Not implemented / not run |
| BUILD-004 | P0 | Field inspector | Builder UI / schema / unit | REG-037 | Not implemented / not run |
| BUILD-005 | P0 | Preview scenarios | Builder UI / schema / unit | Add implementation-specific case | Not implemented / not run |
| BUILD-006 | P0 | Safe drafts | Builder UI / schema / unit | Add implementation-specific case | Not implemented / not run |
| BUILD-007 | P0 | Versioned publishing | Builder UI / schema / unit | REG-035 | Not implemented / not run |
| BUILD-008 | P0 | Distinguish visibility from collection | Builder UI / schema / unit | REG-036 | Not implemented / not run |
| BUILD-009 | P0 | Dependencies | Builder UI / schema / unit | REG-039 | Not implemented / not run |
| BUILD-010 | P0 | Typed custom fields | Builder UI / schema / unit | Add implementation-specific case | Not implemented / not run |
| BUILD-011 | P0 | Named calculations | Builder UI / schema / unit | Add implementation-specific case | Not implemented / not run |
| BUILD-012 | P0 | Configuration portability | Builder UI / schema / unit | Add implementation-specific case | Not implemented / not run |
| BUILD-013 | P0 | Multiple templates, one fact stream | Builder UI / schema / unit | REG-036 | Not implemented / not run |
| BUILD-014 | P0 | No hardcoded metric ceiling | Builder UI / schema / unit | Add implementation-specific case | Not implemented / not run |
| BUILD-015 | P0 | Tracking-only defaults | Builder UI / schema / unit | REG-038 | Not implemented / not run |
| BUILD-016 | P0 | Screen-fit feedback | Builder UI / schema / unit | Add implementation-specific case | Not implemented / not run |
| GOAL-001 | P0 | Pure evaluator | Pure unit / boundary / property | Add implementation-specific case | Not implemented / not run |
| GOAL-002 | P0 | Typed status | Pure unit / boundary / property | REG-001, REG-002, REG-038 | Not implemented / not run |
| GOAL-003 | P0 | Inclusivity | Pure unit / boundary / property | REG-003, REG-004, REG-005, REG-011 | Not implemented / not run |
| GOAL-004 | P0 | Overshoot semantics | Pure unit / boundary / property | REG-003, REG-004, REG-037 | Not implemented / not run |
| GOAL-005 | P0 | Progress is not a reward score | Pure unit / boundary / property | Add implementation-specific case | Not implemented / not run |
| GOAL-006 | P0 | Nutrition group | Pure unit / boundary / property | Add implementation-specific case | Not implemented / not run |
| GOAL-007 | P0 | Exercise compatibility rule | Pure unit / boundary / property | REG-006, REG-007, REG-008 | Not implemented / not run |
| GOAL-008 | P0 | General composites | Pure unit / boundary / property | Add implementation-specific case | Not implemented / not run |
| GOAL-009 | P0 | Weekly schedules | Pure unit / boundary / property | REG-009 | Not implemented / not run |
| GOAL-010 | P0 | Known totals versus completeness | Pure unit / boundary / property | REG-029, REG-055 | Not implemented / not run |
| ENERGY-001 | P0 | Legacy-compatible method | Pure unit / integration | Add implementation-specific case | Not implemented / not run |
| ENERGY-002 | P0 | Configurable resting input | Pure unit / integration | REG-014 | Not implemented / not run |
| ENERGY-003 | P1 | HealthKit method | Pure unit / integration | Add implementation-specific case | Not implemented / not run |
| ENERGY-004 | P1 | Fixed total-expenditure mode | Pure unit / integration | Add implementation-specific case | Not implemented / not run |
| ENERGY-005 | P0/P1 | Exclusive energy source selection | Pure unit / integration | REG-013 | Not implemented / not run |
| ENERGY-006 | P0 | Missing versus zero | Pure unit / integration | REG-012 | Not implemented / not run |
| ENERGY-007 | P0 | Completeness and bounded alternatives | Pure unit / integration | REG-011, REG-012 | Not implemented / not run |
| ENERGY-008 | P0 | No deficit maximization | Pure unit / integration | REG-056 | Not implemented / not run |
| ENERGY-009 | P0 | Goal changes | Pure unit / integration | Add implementation-specific case | Not implemented / not run |
| FOOD-001 | P0 | Versioned facts | Pure unit / source fixture / persistence | REG-051 | Not implemented / not run |
| FOOD-002 | P0 | Unknown is not zero | Pure unit / source fixture / persistence | REG-029 | Not implemented / not run |
| FOOD-003 | P0 | Evidence labels | Pure unit / source fixture / persistence | Add implementation-specific case | Not implemented / not run |
| FOOD-004 | P0 | Identity strictness | Pure unit / source fixture / persistence | REG-022, REG-028 | Not implemented / not run |
| FOOD-005 | P0 | Canonical units | Pure unit / source fixture / persistence | REG-026, REG-027 | Not implemented / not run |
| FOOD-006 | P0 | Valid transformations | Pure unit / source fixture / persistence | REG-025, REG-027, REG-028 | Not implemented / not run |
| FOOD-007 | P0 | Preserve precision | Pure unit / source fixture / persistence | REG-025 | Not implemented / not run |
| FOOD-008 | P0 | Label serving versus exact weight | Pure unit / source fixture / persistence | REG-025, REG-026 | Not implemented / not run |
| FOOD-009 | P0 | Energy consistency | Pure unit / source fixture / persistence | Add implementation-specific case | Not implemented / not run |
| FOOD-010 | P0 | Food ranges | Pure unit / source fixture / persistence | Add implementation-specific case | Not implemented / not run |
| FOOD-011 | P0 | Entry states | Pure unit / source fixture / persistence | Add implementation-specific case | Not implemented / not run |
| FOOD-012 | P0 | Personal aliases | Pure unit / source fixture / persistence | Add implementation-specific case | Not implemented / not run |
| FOOD-013 | P0 | Alias ambiguity | Pure unit / source fixture / persistence | Add implementation-specific case | Not implemented / not run |
| FOOD-014 | P0 | Favorites | Pure unit / source fixture / persistence | Add implementation-specific case | Not implemented / not run |
| FOOD-015 | P0 | Recipe versioning | Pure unit / source fixture / persistence | REG-030 | Not implemented / not run |
| FOOD-016 | P0 | Cooked yield | Pure unit / source fixture / persistence | REG-030 | Not implemented / not run |
| FOOD-017 | P0 | Portions | Pure unit / source fixture / persistence | REG-030 | Not implemented / not run |
| FOOD-018 | P0 | Unknown mixed dishes | Pure unit / source fixture / persistence | REG-021 | Not implemented / not run |
| FOOD-019 | P0 | No parallel competing totals | Pure unit / source fixture / persistence | REG-033 | Not implemented / not run |
| FOOD-020 | P0 | Absolute total edit | Pure unit / source fixture / persistence | REG-033 | Not implemented / not run |
| CHAT-001 | P0 | Separate question from consumption | Interpretation / command integration | REG-018, REG-019 | Not implemented / not run |
| CHAT-002 | P0 | Review-first default | Interpretation / command integration | Add implementation-specific case | Not implemented / not run |
| CHAT-003 | P0 | Correction targeting | Interpretation / command integration | REG-022, REG-024 | Not implemented / not run |
| CHAT-004 | P0 | Discarded food | Interpretation / command integration | REG-019, REG-020 | Not implemented / not run |
| CHAT-005 | P0 | Unit ambiguity | Interpretation / command integration | REG-021, REG-023 | Not implemented / not run |
| CHAT-006 | P0 | Same-food memory | Interpretation / command integration | REG-023, REG-032 | Not implemented / not run |
| CHAT-007 | P0 | Multiple items | Interpretation / command integration | Add implementation-specific case | Not implemented / not run |
| CHAT-008 | P0 | Observation logging | Interpretation / command integration | Add implementation-specific case | Not implemented / not run |
| CHAT-009 | P0 | Goal edits require approval | Interpretation / command integration | Add implementation-specific case | Not implemented / not run |
| CHAT-010 | P0 | Read-only model tools | Interpretation / command integration | Add implementation-specific case | Not implemented / not run |
| CHAT-011 | P0 | Bounded loop | Interpretation / command integration | Add implementation-specific case | Not implemented / not run |
| CHAT-012 | P0 | Small context | Interpretation / command integration | Add implementation-specific case | Not implemented / not run |
| CHAT-013 | P0 | Numbers rendered by code | Interpretation / command integration | Add implementation-specific case | Not implemented / not run |
| CHAT-014 | P0 | Failure handling | Interpretation / command integration | REG-041 | Not implemented / not run |
| CHAT-015 | P0 | Validation before commit | Interpretation / command integration | REG-024, REG-045 | Not implemented / not run |
| CHAT-016 | P0 | Idempotence | Interpretation / command integration | REG-031, REG-032 | Not implemented / not run |
| CHAT-017 | P0 | Optimistic concurrency | Interpretation / command integration | Add implementation-specific case | Not implemented / not run |
| CHAT-018 | P0 | Cancellation | Interpretation / command integration | REG-050 | Not implemented / not run |
| CHAT-019 | P0 | Prompt versioning | Interpretation / command integration | Add implementation-specific case | Not implemented / not run |
| CHAT-020 | P0 | General advice boundary | Interpretation / command integration | Add implementation-specific case | Not implemented / not run |
| LOOKUP-001 | P0 | Cache-first routing | Adapter / network / security / live smoke | REG-040 | Not implemented / not run |
| LOOKUP-002 | P0 | Known-source registry | Adapter / network / security / live smoke | Add implementation-specific case | Not implemented / not run |
| LOOKUP-003 | P0 | Discovery is a separate capability | Adapter / network / security / live smoke | Add implementation-specific case | Not implemented / not run |
| LOOKUP-004 | P0 | Direct source retrieval | Adapter / network / security / live smoke | Add implementation-specific case | Not implemented / not run |
| LOOKUP-005 | P0 | P0 source coverage gate | Adapter / network / security / live smoke | Add implementation-specific case | Not implemented / not run |
| LOOKUP-006 | P0 | Market-specific identity | Adapter / network / security / live smoke | REG-046 | Not implemented / not run |
| LOOKUP-007 | P0 | Portion specificity | Adapter / network / security / live smoke | REG-045, REG-052 | Not implemented / not run |
| LOOKUP-008 | P0 | Supported modifications only | Adapter / network / security / live smoke | Add implementation-specific case | Not implemented / not run |
| LOOKUP-009 | P0 | Evidence is not a probability | Adapter / network / security / live smoke | REG-046 | Not implemented / not run |
| LOOKUP-010 | P0 | Fetch the underlying source | Adapter / network / security / live smoke | Add implementation-specific case | Not implemented / not run |
| LOOKUP-011 | P0 | Per-field provenance | Adapter / network / security / live smoke | Add implementation-specific case | Not implemented / not run |
| LOOKUP-012 | P0 | Extraction validation | Adapter / network / security / live smoke | REG-044 | Not implemented / not run |
| LOOKUP-013 | P0 | Conflicts | Adapter / network / security / live smoke | Add implementation-specific case | Not implemented / not run |
| LOOKUP-014 | P0 | Menu availability versus nutrition | Adapter / network / security / live smoke | Add implementation-specific case | Not implemented / not run |
| LOOKUP-015 | P0 | Parser fixtures | Adapter / network / security / live smoke | Add implementation-specific case | Not implemented / not run |
| LOOKUP-016 | P0 | Fail closed on parser changes | Adapter / network / security / live smoke | REG-044 | Not implemented / not run |
| LOOKUP-017 | P0 | Source evidence display | Adapter / network / security / live smoke | Add implementation-specific case | Not implemented / not run |
| LOOKUP-018 | P0 | No label-photo requirement | Adapter / network / security / live smoke | REG-052 | Not implemented / not run |
| LOOKUP-019 | P0 | Network isolation | Adapter / network / security / live smoke | Add implementation-specific case | Not implemented / not run |
| LOOKUP-020 | P0 | SSRF and content limits | Adapter / network / security / live smoke | Add implementation-specific case | Not implemented / not run |
| LOOKUP-021 | P0 | Untrusted document handling | Adapter / network / security / live smoke | REG-043 | Not implemented / not run |
| LOOKUP-022 | P0 | Access restrictions | Adapter / network / security / live smoke | Add implementation-specific case | Not implemented / not run |
| LOOKUP-023 | P1 | Image-only source fallback | Adapter / network / security / live smoke | Add implementation-specific case | Not implemented / not run |
| CAT-001 | P0 | Small initial seed | Importer / pack / cache integration | Add implementation-specific case | Not implemented / not run |
| CAT-002 | P0 | Catalog tiers | Importer / pack / cache integration | Add implementation-specific case | Not implemented / not run |
| CAT-003 | P0 | Bulk USDA ingestion | Importer / pack / cache integration | Add implementation-specific case | Not implemented / not run |
| CAT-004 | P0 | Serving and nutrient mapping | Importer / pack / cache integration | Add implementation-specific case | Not implemented / not run |
| CAT-005 | P0 | Conservative deduplication | Importer / pack / cache integration | Add implementation-specific case | Not implemented / not run |
| CAT-006 | P0 | Search | Importer / pack / cache integration | Add implementation-specific case | Not implemented / not run |
| CAT-007 | P0 | Build-time size measurement | Importer / pack / cache integration | Add implementation-specific case | Not implemented / not run |
| CAT-008 | P0 | Versioned cache | Importer / pack / cache integration | Add implementation-specific case | Not implemented / not run |
| CAT-009 | P0 | Explicit staleness | Importer / pack / cache integration | Add implementation-specific case | Not implemented / not run |
| CAT-010 | P0 | Conditional refresh | Importer / pack / cache integration | Add implementation-specific case | Not implemented / not run |
| CAT-011 | P0 | Stale/offline behavior | Importer / pack / cache integration | Add implementation-specific case | Not implemented / not run |
| CAT-012 | P0 | Bounded miss caching | Importer / pack / cache integration | Add implementation-specific case | Not implemented / not run |
| CAT-013 | P0 | Private versus global | Importer / pack / cache integration | REG-053 | Not implemented / not run |
| CAT-014 | P0 | Atomic updates | Importer / pack / cache integration | REG-047 | Not implemented / not run |
| CAT-015 | P0 | Rollback and cancellation | Importer / pack / cache integration | REG-047 | Not implemented / not run |
| CAT-016 | P0 | Historical preservation | Importer / pack / cache integration | REG-051 | Not implemented / not run |
| CAT-017 | P1 | Delta distribution | Importer / pack / cache integration | Add implementation-specific case | Not implemented / not run |
| CAT-018 | P1 | Hundred-restaurant coverage | Importer / pack / cache integration | Add implementation-specific case | Not implemented / not run |
| CAT-019 | P0 | Data rights metadata | Importer / pack / cache integration | Add implementation-specific case | Not implemented / not run |
| CAT-020 | P0 | Provider boundaries | Importer / pack / cache integration | Add implementation-specific case | Not implemented / not run |
| STORE-001 | P0 | Schema-versioned persistence | Persistence / migration / time tests | Add implementation-specific case | Not implemented / not run |
| STORE-002 | P0 | Typed values | Persistence / migration / time tests | REG-002 | Not implemented / not run |
| STORE-003 | P0 | Local transactions | Persistence / migration / time tests | REG-031 | Not implemented / not run |
| STORE-004 | P0 | Source-of-truth rules | Persistence / migration / time tests | Add implementation-specific case | Not implemented / not run |
| STORE-005 | P0 | Persisted Undo | Persistence / migration / time tests | REG-034 | Not implemented / not run |
| STORE-006 | P0 | Explicit log day | Persistence / migration / time tests | REG-017 | Not implemented / not run |
| STORE-007 | P0 | Intervals use actual dates | Persistence / migration / time tests | REG-015, REG-016 | Not implemented / not run |
| STORE-008 | P0 | No arbitrary modulo-24 fix | Persistence / migration / time tests | Add implementation-specific case | Not implemented / not run |
| STORE-009 | P0 | Daily reset is not deletion | Persistence / migration / time tests | REG-054 | Not implemented / not run |
| STORE-010 | P0 | Clock changes | Persistence / migration / time tests | Add implementation-specific case | Not implemented / not run |
| STORE-011 | P0 | Honest import boundary | Persistence / migration / time tests | Add implementation-specific case | Not implemented / not run |
| STORE-012 | P0 | Legacy mapping | Persistence / migration / time tests | Add implementation-specific case | Not implemented / not run |
| STORE-013 | P0 | Missing-history warning | Persistence / migration / time tests | Add implementation-specific case | Not implemented / not run |
| STORE-014 | P0 | Zero interpretation | Persistence / migration / time tests | Add implementation-specific case | Not implemented / not run |
| STORE-015 | P0 | Deduplicate imports | Persistence / migration / time tests | REG-048 | Not implemented / not run |
| STORE-016 | P0 | Stable food identities | Persistence / migration / time tests | Add implementation-specific case | Not implemented / not run |
| STORE-017 | P2 | Future inventory boundary | Persistence / migration / time tests | Add implementation-specific case | Not implemented / not run |
| API-001 | P0 | Transport and credentials | Contract / service / security | Add implementation-specific case | Not implemented / not run |
| API-002 | P0 | Minimal request data | Contract / service / security | Add implementation-specific case | Not implemented / not run |
| API-003 | P0 | Complete outcome vocabulary | Contract / service / security | Add implementation-specific case | Not implemented / not run |
| API-004 | P0 | Contract validation | Contract / service / security | Add implementation-specific case | Not implemented / not run |
| API-005 | P0 | Retry safety | Contract / service / security | Add implementation-specific case | Not implemented / not run |
| API-006 | P0 | No infinite synchronous crawl | Contract / service / security | Add implementation-specific case | Not implemented / not run |
| API-007 | P0 | Operational controls | Contract / service / security | Add implementation-specific case | Not implemented / not run |
| API-008 | P0 | Self-hosting instructions | Contract / service / security | Add implementation-specific case | Not implemented / not run |
| HEALTH-001 | P1 | Just-in-time permissions | Permission / device integration | Add implementation-specific case | Not implemented / not run |
| HEALTH-002 | P1 | Read-state honesty | Permission / device integration | Add implementation-specific case | Not implemented / not run |
| HEALTH-003 | P1 | Source reconciliation | Permission / device integration | Add implementation-specific case | Not implemented / not run |
| HEALTH-004 | P1 | Active-energy deduplication | Permission / device integration | Add implementation-specific case | Not implemented / not run |
| HEALTH-005 | P1 | Sleep overlap | Permission / device integration | Add implementation-specific case | Not implemented / not run |
| HEALTH-006 | P1 | Read-only initial release | Permission / device integration | Add implementation-specific case | Not implemented / not run |
| HEALTH-007 | P1 | Revocation/deletion | Permission / device integration | Add implementation-specific case | Not implemented / not run |
| DEVICE-001 | P1 | Barcode scanning | Device / permission / integration | Add implementation-specific case | Not implemented / not run |
| DEVICE-002 | P1 | Optional label capture | Device / permission / integration | Add implementation-specific case | Not implemented / not run |
| DEVICE-003 | P1 | Widgets and shortcuts | Device / permission / integration | Add implementation-specific case | Not implemented / not run |
| DEVICE-004 | P1 | Local reminders | Device / permission / integration | Add implementation-specific case | Not implemented / not run |
| DEVICE-005 | P0/P1 | Text and speech | Device / permission / integration | Add implementation-specific case | Not implemented / not run |
| DEVICE-006 | P2 | Alternative local models | Device / permission / integration | Add implementation-specific case | Not implemented / not run |
| DEVICE-007 | P2 | iOS 27 native nutrition-label understanding | Device / vision / model / unit validation | Add implementation-specific case | Not implemented / not run |
| PRIV-001 | P0 | Local by default | Privacy review / deletion / network | REG-053 | Not implemented / not run |
| PRIV-002 | P0 | No implicit sync | Privacy review / deletion / network | Add implementation-specific case | Not implemented / not run |
| PRIV-003 | P0 | Storage protection | Privacy review / deletion / network | Add implementation-specific case | Not implemented / not run |
| PRIV-004 | P0 | Export and deletion | Privacy review / deletion / network | Add implementation-specific case | Not implemented / not run |
| PRIV-005 | P0 | Logging | Privacy review / deletion / network | Add implementation-specific case | Not implemented / not run |
| PRIV-006 | P0 | Resolver consent | Privacy review / deletion / network | Add implementation-specific case | Not implemented / not run |
| PRIV-007 | P0 | Data minimization | Privacy review / deletion / network | Add implementation-specific case | Not implemented / not run |
| SEC-001 | P0 | No remote execution | Adversarial / configuration review | Add implementation-specific case | Not implemented / not run |
| SEC-002 | P0 | Safe import | Adversarial / configuration review | REG-039 | Not implemented / not run |
| SEC-003 | P0 | Secrets and dependency hygiene | Adversarial / configuration review | Add implementation-specific case | Not implemented / not run |
| SEC-004 | P0 | Health isolation from web content | Adversarial / configuration review | REG-043 | Not implemented / not run |
| SEC-005 | P0 | Safe production configuration | Adversarial / configuration review | Add implementation-specific case | Not implemented / not run |
| SAFE-001 | P0 | Not a medical decision engine | Safety fixture / UI review | Add implementation-specific case | Not implemented / not run |
| SAFE-002 | P0 | No false precision | Safety fixture / UI review | Add implementation-specific case | Not implemented / not run |
| SAFE-003 | P0 | No unsafe reward loop | Safety fixture / UI review | REG-056 | Not implemented / not run |
| SAFE-004 | P0 | Ambiguous targets | Safety fixture / UI review | Add implementation-specific case | Not implemented / not run |
| SAFE-005 | P0 | No supplement advice by inference | Safety fixture / UI review | REG-009 | Not implemented / not run |
| A11Y-001 | P0 | Touch targets | VoiceOver / Dynamic Type / UI | Add implementation-specific case | Not implemented / not run |
| A11Y-002 | P0 | Dynamic Type | VoiceOver / Dynamic Type / UI | REG-049 | Not implemented / not run |
| A11Y-003 | P0 | Noncolor status | VoiceOver / Dynamic Type / UI | Add implementation-specific case | Not implemented / not run |
| A11Y-004 | P0 | Accessible builder | VoiceOver / Dynamic Type / UI | Add implementation-specific case | Not implemented / not run |
| A11Y-005 | P0 | Locale-aware display | VoiceOver / Dynamic Type / UI | Add implementation-specific case | Not implemented / not run |
| A11Y-006 | P0 | Appearance | VoiceOver / Dynamic Type / UI | Add implementation-specific case | Not implemented / not run |
| TEST-001 | P0 | Repeatable fixture suite | Evaluation harness / evidence review | Add implementation-specific case | Not implemented / not run |
| TEST-002 | P0 | Stable and held-out sets | Evaluation harness / evidence review | Add implementation-specific case | Not implemented / not run |
| TEST-003 | P0 | Critical-invariant gate | Evaluation harness / evidence review | Add implementation-specific case | Not implemented / not run |
| TEST-004 | P0 | Initial quality targets | Evaluation harness / evidence review | Add implementation-specific case | Not implemented / not run |
| TEST-005 | P0 | Deterministic numeric gate | Evaluation harness / evidence review | Add implementation-specific case | Not implemented / not run |
| TEST-006 | P0 | On-device evaluation runner | Evaluation harness / evidence review | Add implementation-specific case | Not implemented / not run |
| TEST-007 | P0 | Privacy-aware exports | Evaluation harness / evidence review | Add implementation-specific case | Not implemented / not run |
| TEST-008 | P0 | Network assertions | Evaluation harness / evidence review | Add implementation-specific case | Not implemented / not run |
| TEST-009 | P0 | Model migration regression | Evaluation harness / evidence review | Add implementation-specific case | Not implemented / not run |
| TEST-010 | P0 | Seven-day personal pilot | Evaluation harness / evidence review | Add implementation-specific case | Not implemented / not run |
| TEST-011 | P0 | Requirement coverage | Evaluation harness / evidence review | Add implementation-specific case | Not implemented / not run |
| TEST-012 | P0 | Honest execution reporting | Evaluation harness / evidence review | Add implementation-specific case | Not implemented / not run |
| PERF-001 | P0 | Separate timing stages | Device / operational measurement | Add implementation-specific case | Not implemented / not run |
| PERF-002 | P0 | Resource-aware execution | Device / operational measurement | Add implementation-specific case | Not implemented / not run |
| PERF-003 | P0 | Cost dashboard | Device / operational measurement | Add implementation-specific case | Not implemented / not run |
| PERF-004 | P0 | Graceful limits | Device / operational measurement | Add implementation-specific case | Not implemented / not run |
| PERF-005 | P0 | Device reports | Device / operational measurement | Add implementation-specific case | Not implemented / not run |
| PERF-006 | P0 | Search scalability | Device / operational measurement | Add implementation-specific case | Not implemented / not run |

Total indexed requirements: 228.
