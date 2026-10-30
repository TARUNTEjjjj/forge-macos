#!/bin/bash
# The assertion runner works with Command Line Tools; XCTest also needs Xcode.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/scripts/swift-command.sh" run ForgeCoreChecks "$@"
