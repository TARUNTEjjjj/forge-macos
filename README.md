# Forge for Mac

Source repository: https://github.com/TARUNTEjjjj/forge-macos

A native SwiftUI study workspace for the Forge coding curriculum. Read the complete
50-module curriculum offline, plan a daily focus, keep lesson notes, record practice
sessions, and return to the hosted coding labs from a Mac app. The midnight and
crimson design follows the live [Forge website](https://forge-learning-academy.pages.dev/).

This repository targets **macOS 14 or later**. It is a Mac app, not an iPhone build.
The shared `ForgeCore` models can support a later iOS interface.
The current app version is **0.2.0 (build 2)**.

## Run on your Mac

Install Apple's Xcode Command Line Tools or full Xcode, with Swift 5.9 or later.
This project has no third-party Swift dependencies. Python 3 stages the checked-in
resource catalog for the command-line build wrapper.

```sh
./scripts/test.sh
./scripts/swift-command.sh run ForgeMac --check-native
./scripts/swift-command.sh run ForgeMac --check-lab-unload
./scripts/swift-command.sh run ForgeMac --check-resource-refresh
./scripts/build-app.sh debug
open build/Forge.app
```

`build-app.sh` builds for the current Mac's architecture and assembles a local,
ad-hoc-signed app. It doesn't publish to the Mac App Store or create a distribution
signature. Use `./scripts/build-app.sh release` for an optimized local build. Both
debug and release assembly passed the 4 November 2026 Apple Silicon review.
Build caches and the generated app stay inside this checkout.
The resource-refresh checks use temporary cache files, controlled clocks and
fixture downloads to exercise periodic checks, offline restarts and recovery.
The lab unload check drives the labs browser in WebKit with a local fixture page and
a non-persistent website store, answering its alerts as a learner would; its last step
quits through AppKit, so it ends the process. `--check-lab-unload-live` runs the same
questions against the live labs site with real project edits, with website storage
working, denied and full. It needs internet and is not part of CI.

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

## GitHub resource library

The Library includes a searchable, category-filtered collection of relevant
open-source projects alongside the original official learning references. It
shows collection dates, verified star counts where available and source licenses.
On launch, the app checks the latest public catalog from this repository's `main`
branch on GitHub. It checks again every 15 minutes while running, measured from
the previous request's completion. Returning to the app or waking the Mac also
checks when that interval is due. **Refresh resources** requests an immediate
check; only one request can run at a time.

Validated downloads are saved separately from learning progress so the collection
remains available after an offline restart. The bundled edition remains the
fallback when no saved copy can be used. An older downloaded catalog does not
replace a newer displayed or saved collection. A failed refresh keeps the current
snapshot. The Library identifies downloaded, saved and bundled editions and
distinguishes the app's last successful check from the source's collection date. Metadata
older than 24 hours is still marked stale; downloading it again does not make the
underlying observations newer. GitHub's source collection normally updates daily.

No token, progress, notes, search text, cookies or account credentials are sent.
The fixed HTTPS download rejects redirects, uses request and total-resource
timeouts, and stops at 2 MB before validating the catalog.

The server-side resource refresh writes `resources/catalog.json`. Run
`python3 scripts/sync-resource-catalog.py` after refreshing to update the native
bundle before an Xcode build. The Swift command wrapper does this automatically.
A damaged catalog leaves the original learning library and progress available.

## Where the data lives

The practice journal can search reflections and lesson titles, filter by lesson
or the last 7/30 local calendar days, and show matching session/minute totals.
History loads 50 rows at a time; filtering does not change your saved data.

The native curriculum is bundled with the app. Progress, lesson notes, daily focus,
and study sessions use a local JSON file in the app's Application Support location.
The app supports user-selected JSON backups. The file and each backup can hold up to
50 MB: the 20,000-session limit with reflections averaging about 2 KB, plus every
lesson note at its limit. A failed or invalid load must be repaired or restored before
saving so the original data is preserved. If two copies of the app are open at once,
such as an Xcode build beside `build/Forge.app`, each change is saved on top of the
newest saved progress, and switching to a copy shows what the other saved. If both copies
edit the same note, or the daily focus, at the same time, the copy that saves last keeps
its text. Saves and restores share a file lock, so overlapping writes from updated
copies also preserve separate edits. Older builds without that lock should be closed
while using this version. Before a restore replaces
saved progress, the app keeps that file as a dated `progress-before-restore-…` copy
beside it; choose **File > Show Recovery Copies in Finder** to find these copies. Text
typed but not yet saved stays in its editor through a restore. Progress for a lesson
that a later curriculum renames or removes, and fields added by another Forge version,
are kept rather than rejected or dropped.
The saved public resource catalog uses a separate file in Application Support.
Learning backups do not include this replaceable catalog cache.

The online labs open the existing Forge website in a dedicated WebKit window with
a native toolbar, and require an internet connection.
Lab work the page keeps only in memory, such as a running focus timer, is kept when
you open the section already showing. Links the site opens in a new window, such as
the complete field guide, open in your default browser.

The labs page reports unsaved work, such as project edits that website storage was
denied or too full to hold, through its `beforeunload` guard. WebKit shows that guard's
prompt only to apps using a private method, which Mac App Store apps may not use, so
Forge asks the page itself, by dispatching a cancelable `beforeunload` event, before:

- the toolbar's Reload;
- a same-window link on the site, such as Data & privacy, a form submission, or going
  back or forward to another page;
- the page's own `location.reload()` or a script change of `location` to another page;
- quitting Forge, which macOS also asks for before logging out or restarting, even when
  the labs window is closed, because a closed window keeps its page until Forge quits.

If the page objects, Forge asks first, with keeping the work as the default: **Stay on
page**, **Cancel** or **Keep working** keeps the page and its edits, so you can download a
project ZIP or save in the lab; keeping work when quitting also shows the labs window.
Choosing **Leave page**, **Reload** or **Quit** is an intentional discard: work held only
in memory is gone and nothing recovers it. Another lab section, going back to one, and the
Python runner's sandboxed frame stay in the same page and don't ask. A page that doesn't
answer within two seconds is treated as having nothing to keep, so a frozen page can still
be reloaded or left.

Crashes are different: if the lab's web content stops, or Forge itself is force-quit or
crashes, there is no chance to ask. Forge's "Forge labs stopped" alert says work may be
lost, and the site's own recovery restores only drafts that website storage held.
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
| `Benchmarks/JournalSearchBenchmark` | Release-build journal search timing on a synthetic 20,000-session history (`scripts/swift-command.sh run -c release JournalSearchBenchmark`) |
| `Config` | App metadata, entitlements, privacy manifest, icon |
| `Forge.xcodeproj` | macOS app target for Xcode signing and archiving |
| `scripts` | Local build/test scripts and reproducible icon source |

## Development

Make one useful change at a time. Describe the behavior, add a regression check when
it protects a real failure case, and explain the result in the commit. Keep source
under the owner's **TARUNTEjjjj** account. The repository is public. Never commit keys, profiles, certificates,
user exports, or build products.

The learning plan is a practice budget, not a guarantee of job level, contest rating,
or pay. Lesson resources and contest tasks remain attributed to their original sites.

## Current validation

On 19 November 2026 (macOS 27.2.1, Apple Silicon, Swift 6.4 Command Line Tools),
41 core checks, 17 native editor/navigation checks, 4 journal search checks, 7 lab
unload checks and 10 resource-refresh checks passed, and the debug app assembled and passed signature
verification. The lab unload checks ran in WebKit both through `swift run` and from the
packaged, sandboxed `build/Forge.app`. With the live labs site, `--check-lab-unload-live`
started a project in the project workshop and typed into its editor three times, each in
a fresh non-persistent website store. With working storage, the page saved the edit and its
Data & privacy link left without a question. With storage denied (`localStorage` throwing
a SecurityError, as WebKit does when storage is blocked) and with storage filled until
WebKit refused more (QuotaExceededError), the page said it couldn't save the edit; the site's
Data & privacy link, `location.reload()`, a script change of `location`, the toolbar Reload and
quitting each asked, and staying kept the typed edit. Switching lab sections kept it without
asking, and leaving asked once and followed the site's `/privacy.html` redirect. Denied
storage was simulated by a user script, not by a system setting. The alerts were the app's
real alerts, answered by pressing their buttons from the check, not by hand; no screenshot
was taken, and VoiceOver was not tested.

On 15 November 2026, after the overview-map and read-only journal fixes were
merged with the resource library, 31 core checks, 6 native editor/navigation
checks and 10 resource-refresh integration checks passed, and the debug app
assembled and passed signature verification. The two added native checks cover
the overview map when lessons are reviewed out of order and the journal's focus
field while progress is read-only. Like the other native checks, they use
temporary files and never request the resource catalog.

On 14 November 2026, 31 core checks, 4 native editor/navigation checks and
10 resource-refresh integration checks passed. The new checks cover automatic
timers, overlapping requests, cancellation and late responses, offline restarts,
cache recovery and failed writes, newer saved data, and backward clock changes.
The timer checks include a real elapsed-time refresh with a shortened test interval.

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

## GitHub resource collection

Explore the project-specific [resource catalog](resources/README.md): curated references, star-ranked discovery, dated source metadata, cached failure recovery and an optional read-only server API. The daily refresh workflow updates the public catalog. The native Library checks on launch and every 15 minutes while running, retains a validated copy for offline restarts, and keeps its bundled fallback. App-code updates require a new build.
