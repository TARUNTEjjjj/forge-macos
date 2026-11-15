# Forge for Mac privacy

## Native workspace

The native app keeps lesson completion, notes, daily focus, and session reflections
on the user's Mac. It does not send those records to a Forge account, analytics
service, or GitHub. The bundled curriculum is readable offline. No native login,
advertising SDK, tracking identifier, microphone, camera, or location permission is
used. The privacy manifest describes this native implementation.

Export creates a JSON file at a location selected by the user. That file can contain
private notes and reflections; the user controls where it is stored or shared. Import
validates the file before replacing current progress. The app's normal macOS storage
is private to that app when running with App Sandbox.

## Public resource catalog

At launch, every 15 minutes while running, and when **Refresh resources** is
selected, Forge requests one public JSON catalog from the fixed URL
`https://raw.githubusercontent.com/TARUNTEjjjj/forge-macos/main/resources/catalog.json`.
Returning to the app or waking the Mac also checks when the interval is due.
The interval starts after the previous request completes, and overlapping
automatic or manual requests are not sent.
GitHub receives ordinary connection details such as the IP address and the
requested public path. The request contains no lesson progress, notes, search
text, cookies, access token or account credentials. Catalog searches run locally.
The ephemeral network session has no HTTP disk cache or credential store,
rejects redirects, limits the download to 2 MB and validates source URLs before
showing entries.

Forge saves the validated public catalog in a separate JSON file in the app's
Application Support location. This file contains public project metadata and
source observation dates; it contains no lesson progress, notes, search history,
cookies, request headers or account credentials. It is separate from native
progress storage and is not included in learning backups.

The saved catalog supports offline restarts. Failed checks preserve the current
collection and its previous saved copy, and an older downloaded snapshot does
not replace newer saved metadata. If no valid saved copy can be used, the bundled
offline edition remains available. The Library identifies the displayed edition,
the app's last successful check, source collection dates and stale-data notices. Checking
again does not change the source's observation dates.

## Online labs and source links

Loading the online labs contacts `forge-learning-academy.pages.dev`. The website and
its Python runtime may make requests to hosting and CDN providers. Those providers
receive ordinary connection information, including an IP address and request data.
Read the [website privacy page](https://forge-learning-academy.pages.dev/privacy.html)
for its current behavior. External learning links open the destination service and
are governed by that service's terms and privacy policy.

The website's learning progress, code drafts, and project exports use its web storage.
That store is separate from native progress and can also be separate from Chrome.
There is no implicit sync between these stores. The native app does not inject native
notes into the web page or expose a shell, filesystem bridge, or GitHub credential.

## Before App Store submission

Audit the live labs and current dependencies again. Verify that the App Store Connect
privacy answers describe the complete app, including the embedded website and any
hosting logs under the publisher's control. This document and the manifest do not
replace that audit. Publish an owner-approved support contact and privacy policy URL
before submission.
