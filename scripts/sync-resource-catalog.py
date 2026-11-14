#!/usr/bin/env python3
"""Copy the public catalog into the native bundle without copying private cache."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / "resources/catalog.json"
target = root / "Sources/ForgeCore/Resources/resource-catalog.json"
if not source.exists():
    raise SystemExit("Missing resources/catalog.json; generate the resource snapshot first.")
raw = source.read_bytes()
if len(raw) > 2_000_000:
    raise SystemExit("Resource catalog exceeds the native bundle limit.")
doc = json.loads(raw)
if doc.get("schemaVersion") != 1 or doc.get("project") != "forge-macos" or not isinstance(doc.get("items"), list):
    raise SystemExit("Invalid Forge resource catalog.")
# The server cache is never required by a native application.
doc.pop("sourceCache", None)
encoded = (json.dumps(doc, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
if not target.exists() or target.read_bytes() != encoded:
    target.write_bytes(encoded)
    print("Updated bundled GitHub resource catalog.")
