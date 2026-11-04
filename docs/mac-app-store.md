# Mac App Store release

Status: a native macOS source project and local app build; **not submitted or approved**.
The current development environment has Command Line Tools, not full Xcode. Keep the
live website and source repository independent of any App Store submission.

## Product boundaries

Forge's native value is an offline curriculum reader, lesson notes, progress tracking,
daily planning, and a practice journal with portable backups. Online labs supplement
those features. Describe the offline and online parts accurately in screenshots and
metadata. This release is macOS only; an iOS app needs its own target, interface,
device testing, signing, and review.

Apple requires Mac App Store apps to use App Sandbox and Xcode packaging (2.4.5).
Educational execution has a limited exception with user-viewable, editable source
(2.5.2). A website wrapper alone is insufficient (4.2). The current native features
provide additional utility, but approval remains Apple's decision.
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

## Build and sign in Xcode

1. Install a current Xcode version accepted for submission and select its command-line
   tools. Open `Forge.xcodeproj`, select **Forge → My Mac**, and build the app.
2. In Signing & Capabilities, select the owner's Apple Developer team. Register an
   available bundle identifier; the initial identifier is `com.taruntejjjj.forge.mac`.
   Keep App Sandbox enabled with outgoing network access and user-selected file access.
3. Run `./scripts/test.sh`. Test the app on supported macOS releases and both Apple
   Silicon and Intel if both architectures will be advertised. Verify VoiceOver,
   keyboard navigation, larger text, offline startup, backup restore, and error states.
4. Choose a unique version/build number, select a distribution destination, and create
   an archive. Validate the archive in Organizer and inspect the embedded resources,
   signature, entitlements, and privacy report.
5. Use App Store Connect to create the app record, upload the signed build, and complete
   its metadata. TestFlight and review use the uploaded build. An ad-hoc `build/Forge.app`
   from the script is not a substitute for that archive.

[Apple's build upload workflow](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)

## Release evidence to record

| Check | Initial state |
| --- | --- |
| Native core tests | 16/16 passed, 2026-10-30 |
| SwiftUI compilation | Passed: Swift 6.4, Apple Silicon, debug |
| Local `.app` assembly and signature verification | Passed: `scripts/build-app.sh debug`, local ad-hoc signature |
| Full Xcode target build and archive | Pending full Xcode |
| Provisioned distribution signature | Pending owner team configuration |
| Launch from a moved copy with original build folder unavailable | Release resource/native checks passed, 2026-11-04; debug GUI lesson navigation passed |
| Backup export/import with malformed-file handling | Core + 4 native regression checks passed; full dialog QA pending |
| Online Python in WebKit | Starter example execution verified; sandbox iframe navigation repaired |
| Git, project editing, export, and all twelve Python missions | Further release QA required |
| Intel and Apple Silicon, offline, VoiceOver | Required release-device QA |
| Privacy manifest and App Store privacy answers | Owner review required |
| App Store screenshots, contact, review notes | Prepare from the actual release build |
| TestFlight and App Review | Not submitted |

## Review notes draft

Explain where the native offline curriculum, study journal, and JSON backup commands
are located. State that the online labs use WebKit and require network access. Learners
can read and edit the educational Python code they run. Identify the runtime download
and its purpose; demonstrate that no native command runner or filesystem bridge is
exposed. Explain the separate native/web storage. Provide a complete path through a
lesson, save, restart, and restore, plus the hosted lab's Python test flow.

The Python-runtime policy needs explicit review before submission. Confirm runtime
source visibility, download disclosure, and all remote behavior against the current
guidelines. Do not hide the feature or claim the educational exception guarantees
approval. All advertised functions must be working during review.

[Current App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)


## 3 November 2026 pull-request review

The debug app assembled and passed ad-hoc signature verification locally. All 16 core checks and all four native regression checks passed. A new read-only GitHub Actions workflow runs these checks and builds the debug app on macOS for pull requests and `main` pushes. This does not archive, upload, or publish an App Store release. The download-replacement path still needs a signed, sandboxed GUI save-panel test before distribution.

## 4 November 2026 native product review

All 16 core and four native checks passed on macOS 27.2, Apple Silicon, with Swift
6.4.2 Command Line Tools. Both debug and optimized release apps assembled and passed
ad-hoc signature verification. The release copy ran its resource and native checks
from a path containing spaces while the original `.build` folder was unavailable,
loading all 50 modules. The relocated debug app also opened its dashboard and an
offline lesson through the native UI, without changing learner data.

The earlier release dSYM limitation did not recur. Full Xcode archiving, distribution
signing, Intel/macOS 14 devices, VoiceOver, live lab downloads and save-panel testing
remain unverified in this review. No App Store upload or publication was performed.
