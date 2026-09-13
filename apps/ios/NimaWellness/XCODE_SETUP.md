# Importing NimaWellness into Xcode

These sources were written on a Linux environment, so no `.xcodeproj` is committed.
Two ways to get a buildable project on your Mac; both take a few minutes.

## Prerequisites

- A Mac with Xcode that includes the iOS 26 SDK.
- Your Apple developer account signed into Xcode (Settings → Accounts).
- iPhone 16e paired, with Developer Mode enabled
  (Privacy & Security → Developer Mode) — see Apple's device-development docs.
- For chat interpretation: Apple Intelligence enabled on the phone and the
  system model finished downloading. The tracker works without it.

## Option A: XcodeGen (fastest)

```bash
brew install xcodegen
cd apps/ios/NimaWellness
xcodegen generate
open NimaWellness.xcodeproj
```

Then select your signing team under Signing & Capabilities and run on the 16e.

## Option B: Manual project creation

1. Xcode → File → New → Project → iOS → App.
   - Product name: `NimaWellness`
   - Interface: SwiftUI, Language: Swift, Storage: **None** (SwiftData models
     are already defined in code; do not let the template generate its own).
   - Save it anywhere **outside** this repo, or into `apps/ios/NimaWellness/`
     letting Xcode create the project file next to the `NimaWellness/` sources
     folder.
2. Delete the template's `ContentView.swift` and `<App>App.swift`.
3. Drag the `NimaWellness/` folder (App/, Features/, Infrastructure/) from this
   repo into the project navigator → "Copy items if needed" **off**, "Create
   groups" on, target membership: NimaWellness.
4. File → Add Package Dependencies → Add Local… → select
   `packages/WellnessCore` from this repo. Add the `WellnessCore` library to
   the NimaWellness target.
5. Target settings:
   - iOS Deployment Target: 26.0
   - Signing: your team (kept local, never committed)
6. Select your iPhone 16e (or an iPhone 16e simulator, 390×844 class) and Run.

## Running the domain tests

Product → Test with the `WellnessCore` scheme, or from Terminal on the Mac:

```bash
swift test --package-path packages/WellnessCore
```

These tests cover the PRD regression cases that are pure-domain
(goal boundaries, portion arithmetic, ledger idempotence/undo, DST intervals,
config validation, legacy-import dedup). They do not need a device or model.

## M0 device smoke test (from the implementation plan)

1. Build and run on the physical 16e with Apple Intelligence ready.
2. In Chat, send: `I had 112 g cooked pinto beans` — expect a structured
   preview (or an honest clarification), never invented nutrition.
3. Enable Airplane Mode and repeat with a seeded food
   (`I had 112 g of my ham`) — interpretation and logging must work offline.
4. If the model is off/not ready, the chat shows the availability notice and
   Today's manual controls keep working — that state is part of the test.

## What is intentionally NOT here yet

- No web resolver, HealthKit, barcode/OCR, widgets, or USDA catalog (M4/M5/P1).
- No cloud inference or paid APIs anywhere — verify with a network inspector;
  the only model calls are Apple's on-device Foundation Models framework.
