# Legacy tracker baseline and porting notes

**Reference:** `nima-wellness-tracker-calorie-balance-v19.html` from the user's File Library, saved 2026-09-07. Relevant source snippets were inspected while preparing the PRD. The complete original HTML is not included here. The live domain was not successfully inspected; these notes do not claim to document the currently deployed website byte-for-byte.

The source is a design/behavior reference, not a SwiftUI implementation. The PRD controls when these notes and legacy behavior differ.

## Front end to preserve

- Light blue/white cards, dark navy theme, rounded corners, bold values, blue goal hints.
- Sections for Sleep & Fasting, calculated durations, Nutrition, Activity, Supplements, and Success.
- Protein, fiber, water, calories, and activity counters, with an exact-value editor added in the native port.
- Workout completion and a configurable activity label; original label is Apple Fitness+.
- Workout type options originally Cardio and Strength.
- AM and PM supplement toggles that visibly update immediately and persist.
- Six success indicators arranged as two rows of three, with calorie balance as a seventh full-width bottom row.
- Active-calorie area showing Out and Net without duplicating the intake value there.
- Readable date and preceding-day labels for overnight intervals.
- Auto-save feedback and a deliberate reset action.

The old HTML uses very small controls for single-screen fit. The native app must instead preserve compact summaries and use accessible hit targets/detail sheets. One-screen preference is not permission to clip content or shrink essential text.

## Color reference

| Token | Light | Dark |
|---|---|---|
| Background | `#f7fbff` | `#071522` |
| Card | `#ffffff` | `#0b1d2d` |
| Primary text | `#10233d` | `#f4f8fc` |
| Secondary text | `#6f7f92` | `#9eb0c3` |
| Accent | `#2f80ed` | `#3b9cff` |
| Border | `#dbe8f5` | `#223b52` |

Use semantic status colors with textual labels. Adjust contrast for accessibility. Exact legacy hex values are starting tokens, not mandatory inaccessible colors.

## Field mapping

The localStorage key is `nimaWellnessTrackerCompactV2`. The source stores one date's state rather than a historical event ledger.

| Legacy field | Native concept | Migration caution |
|---|---|---|
| `date` | Assigned log day | Preserve the supplied day; do not use today's date automatically. |
| `sleepStart`, `sleepEnd` | Dated sleep interval | Clock-only values require date review. |
| `fastStart`, `fastEnd` | Dated optional fasting interval | Do not blindly add 24 hours for every negative difference. |
| `protein` | Manual protein adjustment/observation | No meal decomposition can be reconstructed from a daily total. |
| `fiber` | Manual fiber adjustment/observation | Default zero may mean missing. |
| `water` | Water volume | Legacy input is liters; native canonical volume is mL. |
| `calories` | Manual energy adjustment | Preserve as legacy manual data, not a fabricated source-backed meal. |
| `steps` | Manual daily step total | Must not later be added to the same imported daily total. |
| `activeCalories` | Manual daily active-energy total | Includes the user's entered steps/exercise burn; no extra step formula. |
| `exerciseDone` | Workout completion observation | False/default and unrecorded need review. |
| `exerciseType` | Workout classification | Preserve the text/enum without claiming HealthKit origin. |
| `morningPills`, `eveningPills` | Supplement AM/PM checklist | UI uses Supplements, not an inferred medication regimen. |
| `theme` | Appearance preference | Map to light/dark; add system preference in native settings if desired. |

Import only the payload actually available. The native app cannot silently read Safari localStorage. A user-initiated export/share/import must bridge the two applications.

## Legacy evaluation behavior

The old shared function maps deviation to green at <=5%, yellow at <=25%, otherwise red. Many field calculations then feed this shared function, which creates thresholds different from their displayed labels.

| Metric | Observed legacy calculation | Native requirement |
|---|---|---|
| Sleep | Shortfall relative to 480 minutes; above 480 is green | Preserve explicitly visible 456-minute green boundary unless edited. |
| Fasting | Absolute deviation from 960 minutes | Preserve explicit band, no extra reward for longer fasting. |
| Protein | Shortfall from 130 g, then shared 5% green tolerance | **Fix:** green starts at exactly 130 g, not 123.5 g. Display 140-150 g. |
| Fiber | Shortfall from 35 g, then shared tolerance | Preserve explicit green threshold 33.25 g unless edited. |
| Calories | Outside 2,000-2,200 band divided by midpoint 2,100; shared tolerance | Preserve explicit initial band 1,895-2,305, editable and explained. |
| Water | Shortfall from 2 L, then shared tolerance | **Fix:** green starts at exactly 2 L, not 1.9 L. |
| Exercise | Workout done and steps >=7,500 green; workout alone/adequate steps yellow | Preserve the custom combination; step overshoot stays green. |
| Supplements | Red until both AM/PM are true | **Fix:** use scheduled, incomplete, partial, and complete states. |
| Net calories | `(intake - (1883 + active)) / out`; below -5% green, within +/-5% yellow, above +5% red | Preserve optional legacy comparison with provisional/completeness handling and configurable modes. |

The source's prior v17 balance behavior is not the target. v19 already has the intended weight-loss orientation.

## Energy details

The legacy constant is `1883`, noted in source as an estimate for 93 kg, 178 cm, age 33, male equation. The exact formula gives 1,882.5 before display rounding. The native application must make the profile/estimate configurable and reviewed, not embed the owner's profile for everyone.

"Out" under this method is estimated resting energy plus logged active energy. It is not a measured total expenditure. No activity multiplier, imported resting energy, or duplicated workout energy is added on top.

## Native improvements that deliberately differ

1. Effective-dated configuration instead of hardcoded goals.
2. An event/revision-backed diary rather than one mutable daily localStorage object.
3. Missing versus explicit zero, and source coverage versus completed-day status.
4. Dated intervals, correct DST handling, and stable historical day attribution during travel.
5. Accessible controls rather than copying the old tiny touch targets.
6. Scheduled supplement status instead of automatic morning failure.
7. Provisional energy comparison and no reward for extreme deficits.
8. Shared deterministic state across chat, dashboard, history, and builder preview.
9. Explicit arithmetic/source provenance instead of recycling prior conversational estimates.
10. Visual, code-free configuration of fields, targets, layouts, and composites.

## Reference screen structure

```text
Today header: title | selected date | theme/settings

Sleep / optional fasting summary     Nutrition summary
Hydration and quick add              Activity and quick add
Supplements: AM [ ]  PM [ ]

[ Sleep ] [ Fasting ]   [ Nutrition ]
[ Water ] [ Exercise ]  [ Supplements ]
[       Calorie balance: full width        ]

Today       Chat       History       Builder
```

Use a device preview to check actual safe areas. Expanded editors may scroll. Hidden/disabled categories modify the layout transparently through the builder rather than leaving blank required panels.
