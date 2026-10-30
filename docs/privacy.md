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
