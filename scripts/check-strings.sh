#!/usr/bin/env bash
# Checks that Resources/it.lproj/Localizable.strings translates every localizable text in the code, and
# nothing else. The compiler lists the texts (String(localized:), SwiftUI literals) while building.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swift build --build-system native --scratch-path .build/strings \
  -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$OUT" >/dev/null

plutil -convert json -o "$OUT/it.json" Resources/it.lproj/Localizable.strings

/usr/bin/python3 -I - "$OUT" <<'PY'
import glob, json, sys

out = sys.argv[1]
used = {}
for path in glob.glob(f"{out}/*.stringsdata"):
    data = json.load(open(path))
    for entry in data.get("tables", {}).get("Localizable", []):
        used.setdefault(entry["key"], data["source"])
used.pop("", None)
translated = json.load(open(f"{out}/it.json"))

missing = sorted(set(used) - set(translated))
unused = sorted(set(translated) - set(used))
for key in missing:
    print(f"missing translation: {key!r} ({used[key]})")
for key in unused:
    print(f"unused translation: {key!r}")
print(f"{len(used)} texts, {len(missing)} missing, {len(unused)} unused")
sys.exit(1 if missing or unused else 0)
PY
