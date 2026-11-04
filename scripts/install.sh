#!/usr/bin/env bash
# Installs (or updates) QR Reader from the latest GitHub release:
#   curl -fsSL https://raw.githubusercontent.com/ViseLuca/mac-qr-code-reader/main/scripts/install.sh | bash
# Files downloaded with curl carry no quarantine flag, so Gatekeeper does not block the unnotarized app.
# Installs into /Applications, or ~/Applications when /Applications is not writable.
set -euo pipefail

REPO="ViseLuca/mac-qr-code-reader"
ASSET="QRReader.zip"
APP_NAME="QR Reader.app"
BUNDLE_ID="it.lucav.qrreader"
MIN_MACOS=14

# Messages follow the system language, as the app does: Italian on a Mac set to Italian, English otherwise.
ITALIAN=false
[[ "$(defaults read -g AppleLanguages 2>/dev/null | sed -n 2p | tr -d ' ",')" == it* ]] && ITALIAN=true

# l10n "English" "Italiano"
l10n() { if $ITALIAN; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
say() { printf '%s\n' "$(l10n "$1" "$2")"; }
fail() { printf '\n❌ %s\n' "$(l10n "$1" "$2")" >&2; exit 1; }

# Everything runs from main(), called on the last line: if the download of this script stops halfway, bash runs nothing.
main() {
  [[ "$(uname -s)" == Darwin ]] || fail "QR Reader only runs on macOS." "QR Reader funziona solo su macOS."
  local macos
  macos="$(sw_vers -productVersion)"
  (( ${macos%%.*} >= MIN_MACOS )) || fail "macOS $MIN_MACOS or later is required (this Mac has $macos)." \
    "Serve macOS $MIN_MACOS o successivo (questo Mac ha $macos)."

  # Global, not local: the EXIT trap runs after main() has returned.
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  say "Looking for the latest version…" "Cerco l'ultima versione…"
  curl -fsSL -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/releases/latest" -o "$tmp/release.json" \
    || fail "Cannot reach GitHub. Check your connection and try again." \
            "Non riesco a contattare GitHub. Controlla la connessione e riprova."

  local version url="" digest="" count i
  version="$(plutil -extract tag_name raw -o - "$tmp/release.json")"
  count="$(plutil -extract assets raw -o - "$tmp/release.json")"
  for (( i = 0; i < count; i++ )); do
    if [[ "$(plutil -extract "assets.$i.name" raw -o - "$tmp/release.json")" == "$ASSET" ]]; then
      url="$(plutil -extract "assets.$i.browser_download_url" raw -o - "$tmp/release.json")"
      digest="$(plutil -extract "assets.$i.digest" raw -o - "$tmp/release.json" 2>/dev/null || true)"
      break
    fi
  done
  [[ -n "$url" ]] || fail "Release $version does not contain $ASSET." "La release $version non contiene $ASSET."

  say "Downloading QR Reader ${version}…" "Scarico QR Reader ${version}…"
  curl -fL --progress-bar "$url" -o "$tmp/$ASSET" || fail "Download failed." "Download non riuscito."

  if [[ "$digest" == sha256:* ]]; then
    [[ "$(shasum -a 256 "$tmp/$ASSET" | cut -d' ' -f1)" == "${digest#sha256:}" ]] \
      || fail "The downloaded file is corrupted (checksum mismatch). Try again." \
              "Il file scaricato è corrotto (checksum diverso). Riprova."
  fi

  ditto -x -k "$tmp/$ASSET" "$tmp/unzipped"
  local app="$tmp/unzipped/$APP_NAME"
  [[ -d "$app" ]] || fail "The zip does not contain $APP_NAME." "Lo zip non contiene $APP_NAME."
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == "$BUNDLE_ID" ]] \
    || fail "The zip contains another app." "Lo zip contiene un'altra app."
  codesign --verify --deep --strict "$app" 2>/dev/null || fail "The app's signature is not valid." "La firma dell'app non è valida."

  local dir="/Applications"
  [[ -w "$dir" ]] || { dir="$HOME/Applications"; mkdir -p "$dir"; }
  local dest="$dir/$APP_NAME"

  osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
  # The old copy goes into the temp folder, deleted on exit; the new one replaces it whole, with no leftover files.
  if [[ -e "$dest" ]]; then
    mv "$dest" "$tmp/old.app" || fail "Cannot replace $dest." "Non riesco a sostituire $dest."
  fi
  if ! mv "$app" "$dest"; then
    [[ -e "$tmp/old.app" ]] && mv "$tmp/old.app" "$dest"
    fail "Cannot copy the app to $dir." "Non riesco a copiare l'app in $dir."
  fi
  xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true

  say "✅ QR Reader $version installed in $dest" "✅ QR Reader $version installato in $dest"
  open "$dest"
  say "Look for its icon in the menu bar, top right." "Trovi l'icona nella barra dei menu, in alto a destra."
}

main "$@"
