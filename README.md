# Forge for Mac

Source repository: https://github.com/TARUNTEjjjj/forge-macos

A native SwiftUI study workspace for the Forge coding curriculum. Read the complete
50-module curriculum offline, plan a daily focus, keep lesson notes, record practice
sessions, and return to the hosted coding labs from a Mac app. The midnight and
crimson design follows the live [Forge website](https://forge-learning-academy.pages.dev/).

This repository targets **macOS 14 or later**. It is a Mac app, not an iPhone build.
The shared `ForgeCore` models can support a later iOS interface.

## Run on your Mac

Install Apple's Xcode Command Line Tools or full Xcode, with Swift 5.9 or later.
This project has no third-party Swift dependencies.

```sh
./scripts/test.sh
./scripts/swift-command.sh run ForgeMac --check-native
./scripts/build-app.sh debug
open build/Forge.app
```

`build-app.sh` builds for the current Mac's architecture and assembles a local,
ad-hoc-signed app. It doesn't publish to the Mac App Store or create a distribution
signature. Use `./scripts/build-app.sh release` for an optimized local build. Both
debug and release assembly passed the 4 November 2026 Apple Silicon review.
Build caches and the generated app stay inside this checkout.

## Use full Xcode

Open `Forge.xcodeproj` in Xcode 16 or later, choose the **Forge** scheme and **My Mac**,
then run. The app target links the local `ForgeCore` Swift package. Configure your
Apple Developer team in Signing & Capabilities; no team or signing certificate is
stored in this repository. The shared app scheme builds the app; run core tests with
`./scripts/test.sh`. This uses the same assertions through a command-line runner,
so it also works with Command Line Tools. Full Xcode additionally supports
`./scripts/swift-command.sh test` or the package test scheme.

The release steps and remaining verification are in [Mac App Store release](docs/mac-app-store.md).
The project includes App Sandbox entitlements, a privacy manifest, and a custom
vector-generated icon. These are preparation for distribution, not Apple approval.

## Where the data lives

The practice journal can search reflections and lesson titles, filter by lesson
or the last 7/30 local calendar days, and show matching session/minute totals.
History loads 50 rows at a time; filtering does not change your saved data.

The native curriculum is bundled with the app. Progress, lesson notes, daily focus,
and study sessions use a local JSON file in the app's Application Support location.
The app supports user-selected JSON backups. A failed or invalid load must be repaired
or restored before saving so the original data is preserved.

The online labs open the existing Forge website in a dedicated WebKit window with
a native toolbar, and require an internet connection.
Their website storage is separate from the native progress file and from Chrome's
storage. A completion in one area does not automatically mark a module complete in
another. Download or export important work before clearing any app or browser data.
See [privacy](docs/privacy.md) for the native and online data boundaries.

## Source layout

| Path | Purpose |
| --- | --- |
| `Sources/ForgeMac` | SwiftUI app, native study screens, online labs |
| `Sources/ForgeCore` | Curriculum models and validated local persistence |
| `Sources/ForgeCore/Resources/curriculum.json` | Original Forge lessons and source links |
| `Tests/ForgeCoreTests` | Curriculum and persistence regression tests |
| `Config` | App metadata, entitlements, privacy manifest, icon |
| `Forge.xcodeproj` | macOS app target for Xcode signing and archiving |
| `scripts` | Local build/test scripts and reproducible icon source |

## Development

Make one useful change at a time. Describe the behavior, add a regression check when
it protects a real failure case, and explain the result in the commit. Keep source
under the owner's **TARUNTEjjjj** account. The repository is private; keep it private unless the owner explicitly
requests a visibility change. Never commit keys, profiles, certificates,
user exports, or build products.

The learning plan is a practice budget, not a guarantee of job level, contest rating,
or pay. Lesson resources and contest tasks remain attributed to their original sites.

## Current validation

On 5 November 2026, the debug and optimized release builds passed 19 core checks,
4 native editor/navigation checks, and local app assembly/signature verification.
The journal now aggregates its seven-day chart in one pass through session history
and creates session rows lazily while scrolling. Regression checks cover a full
20,000-session history, empty/repeated days, local midnight, and both daylight-saving
transitions. These are local data/build checks; interactive scrolling, VoiceOver,
and distribution signing still need release-device testing.

On 30 October 2026, Apple Silicon with Swift 6.4 Command Line Tools passed
16 core regression checks and 4 native editor/navigation checks. The debug app
compiled, assembled, passed code-signature verification, and launched through
the desktop UI. Native dashboard and lab-window layout were visually inspected. Python executed
the original starter in WebKit and reported the expected 0/2 example results
(the starter intentionally returns zero). No lesson completion was manufactured.
The checks cover restart persistence, malformed backups, preserving corrupt data,
shared drafts, failed writes, restore safety, and the sandboxed Python frame policy.


The initial environment has Command Line Tools but no full Xcode. Swift package
compilation/tests and app assembly can be checked there. Xcode archive validation,
provisioned signing, TestFlight, both Mac architectures, VoiceOver, and App Store
review are separate release checks. Record their actual results before publishing.
