#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 "$ROOT/scripts/sync-resource-catalog.py"
mkdir -p .build/cache .build/config .build/security .build/ModuleCache
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/ModuleCache"
if [ "$#" -eq 0 ]; then
  printf 'Usage: %s build|run|test [options]\n' "$0" >&2
  exit 2
fi
COMMAND="$1"
shift
exec /usr/bin/swift "$COMMAND" --disable-sandbox --cache-path "$ROOT/.build/cache" --config-path "$ROOT/.build/config" --security-path "$ROOT/.build/security" "$@"
