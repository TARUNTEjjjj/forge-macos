#!/bin/bash
# Assemble an ad-hoc-signed local app. This is not an App Store archive.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIGURATION="${1:-release}"
case "$CONFIGURATION" in debug|release) ;; *) printf 'Choose debug or release.\n' >&2; exit 2 ;; esac
"$ROOT/scripts/swift-command.sh" build -c "$CONFIGURATION" --product ForgeMac
BIN_PATH="$("$ROOT/scripts/swift-command.sh" build -c "$CONFIGURATION" --show-bin-path)"
APP="$ROOT/build/Forge.app"
STAGING="$ROOT/build/Forge-staging.app"
mkdir -p "$ROOT/build"
if [ -e "$STAGING" ]; then rm -rf "$STAGING"; fi
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"
cp "$BIN_PATH/ForgeMac" "$STAGING/Contents/MacOS/ForgeMac"
cp "$ROOT/Config/Info.plist" "$STAGING/Contents/Info.plist"
cp "$ROOT/Config/PrivacyInfo.xcprivacy" "$STAGING/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$ROOT/Config/AppIcon.icns" "$STAGING/Contents/Resources/AppIcon.icns"
RESOURCE_BUNDLE="$BIN_PATH/ForgeMac_ForgeCore.bundle"
if [ ! -d "$RESOURCE_BUNDLE" ]; then
  printf 'Missing curriculum bundle: %s\n' "$RESOURCE_BUNDLE" >&2
  exit 1
fi
# SwiftPM's Bundle.module resolves resources beside Bundle.main.bundleURL.
cp -R "$RESOURCE_BUNDLE" "$STAGING/Contents/Resources/"
PLIST="$STAGING/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable ForgeMac' "$PLIST"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.taruntejjjj.forge.mac' "$PLIST"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.1.0' "$PLIST"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 1' "$PLIST"
/usr/libexec/PlistBuddy -c 'Set :LSMinimumSystemVersion 14.0' "$PLIST"
/usr/bin/codesign --force --sign - --options runtime --entitlements "$ROOT/Config/Forge.entitlements" "$STAGING"
/usr/bin/codesign --verify --deep --strict "$STAGING"
if [ -e "$APP" ]; then rm -rf "$APP"; fi
mv "$STAGING" "$APP"
printf '\nBuilt local app: %s\nOpen with: open "%s"\n' "$APP" "$APP"
printf 'This ad-hoc build is for this Mac. Use the Xcode project for distribution signing.\n'
