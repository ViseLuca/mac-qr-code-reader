#!/usr/bin/env bash
# Runs the test suite. With only the Command Line Tools installed (no Xcode),
# swift-testing lives outside the default search paths, so add them explicitly.
set -euo pipefail

cd "$(dirname "$0")/.."

CLT=/Library/Developer/CommandLineTools/Library/Developer
EXTRA=()
if [[ -d "$CLT/Frameworks/Testing.framework" ]]; then
  EXTRA=(-Xswiftc -F -Xswiftc "$CLT/Frameworks"
         -Xlinker -F -Xlinker "$CLT/Frameworks"
         -Xlinker -rpath -Xlinker "$CLT/Frameworks"
         -Xlinker -rpath -Xlinker "$CLT/usr/lib")
fi

# The default (swift-build) backend fails with CLT-only setups: "Unknown error parsing property list".
swift test --build-system native "${EXTRA[@]}" "$@"
