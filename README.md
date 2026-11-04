# mac-qr-code-reader

QR code reader for the macOS menu bar. Native (Swift, Vision, ScreenCaptureKit, AVFoundation, CoreWLAN), no dependencies.

The app follows the system language: Italian on a Mac set to Italian, English otherwise.

## Modes

| Mode | Shortcut | What it does |
|---|---|---|
| **Screen Viewfinder** | ⌥⇧Q | Floating frame that keeps scanning whatever is under it. Drag the border to move it, a corner to resize it, ✕ to close it. Clicks pass through the inside. |
| **Select Area** | ⌥⇧A | Drag a rectangle as with ⌘⇧4. A click without dragging scans the whole screen, Esc cancels. |
| **Webcam** | ⌥⇧C | Window with a live preview. Close it to turn the camera off. |

Shortcuts can be changed from **Shortcuts…** in the menu: click the one to change and press the new combination (it needs at least ⌘, ⌥ or ⌃; F1–F12 also work on their own). ⌫ removes it, the arrow resets it to the default. If another app already uses the same combination, macOS refuses it: the window says so and the menu item becomes **⚠️ Shortcuts…**.

The result appears in a floating panel with actions based on the content:
- **Wi-Fi** (`WIFI:T:WPA;S:…;P:…;;`): Connect, Copy password
- **Link**: Open, Copy
- **vCard**: Add to Contacts
- **Text**: Copy

The last 20 scans are in the *History* menu, stored in plain text in UserDefaults, Wi-Fi passwords included.

## Installation

### With Terminal (recommended)

Open **Terminal** (Spotlight ⌘Space › "Terminal"), paste this line and press Return:

```sh
curl -fsSL https://raw.githubusercontent.com/ViseLuca/mac-qr-code-reader/main/scripts/install.sh | bash
```

It downloads the latest version, verifies it, installs it in `Applications` and opens it. No macOS warning: files downloaded with `curl` are not blocked by Gatekeeper the way browser downloads are. Run it again any time to reinstall.

### From the browser

1. Download **[QRReader.zip](https://github.com/ViseLuca/mac-qr-code-reader/releases/latest/download/QRReader.zip)** from the [latest release](https://github.com/ViseLuca/mac-qr-code-reader/releases/latest).
2. Unzip it and move `QR Reader.app` to `Applications`.
3. The app is free and not notarized by Apple, so macOS blocks it on first launch. Unblock it once: try to open it, dismiss the warning, then go to *System Settings › Privacy & Security*, scroll to the bottom and click **Open Anyway**.

To always have it at hand: *System Settings › General › Login Items* › add QR Reader.

### From source

Requires macOS 14+ and the Command Line Tools (`xcode-select --install`); Xcode is not needed.

```sh
scripts/build-app.sh install
```

| Command | What it does |
|---|---|
| `scripts/build-app.sh` | Universal build (Apple Silicon + Intel) in `build/QR Reader.app` |
| `scripts/build-app.sh install` | Build, copy to `/Applications` and relaunch |
| `scripts/build-app.sh dist 0.2.0` | Build version 0.2.0 signed with `QRReader Dev` and zip it into `build/QRReader.zip` for a release |
| `scripts/build-app.sh icon` | Redraw `Resources/AppIcon.icns` from `scripts/make-icon.swift` |
| `scripts/test.sh` | Unit tests (parser, decoder, updates) |
| `scripts/check-strings.sh` | Checks that every text in the app has an Italian translation |

> Always use the `.app`, not `swift run`: without an Info.plist macOS kills the app as soon as it accesses the camera.

## Updates

At launch and every 6 hours QR Reader checks the [latest release](https://github.com/ViseLuca/mac-qr-code-reader/releases/latest) on GitHub. If it is newer than the installed version, it offers to install it: it downloads `QRReader.zip`, verifies it against the SHA-256 published by GitHub, checks that it contains QR Reader at the release's version with a valid signature, replaces the app and relaunches it. If the app is in a folder it cannot write to, it opens the release page instead.

From the menu: **Check for Updates…**, which becomes **⬆️ Update to x.y.z** when one is available.

### Publishing a release

```sh
scripts/build-app.sh dist 0.2.0
gh release create 0.2.0 build/QRReader.zip
```

The asset must be named `QRReader.zip`. Local builds (`scripts/build-app.sh`, `install`) take their version from the latest git tag.

`dist` signs with the self-signed `QRReader Dev` certificate (another one with `CODESIGN_IDENTITY="…"`) and refuses ad-hoc signing: with an unchanging signature macOS recognizes every version as the same app, so users don't have to grant permissions again after each update.

#### Signing certificate (one time only)

1. *Keychain Access › Certificate Assistant › Create a Certificate…*
2. Name `QRReader Dev`, Identity Type *Self-Signed Root*, Certificate Type *Code Signing*, check **Let me override defaults**.
3. *Validity Period*: `3650` days (the default is one year, after which `codesign` stops signing). Accept the rest with Continue.
4. Back it up: in Keychain Access, *My Certificates* › right-click `QRReader Dev` › **Export** as `.p12`, with a password, somewhere safe (e.g. 1Password). Export from *My Certificates*, not *Keys*: the backup must hold the certificate together with its private key (the disclosure arrow next to `QRReader Dev` shows it), as the private key is what signs. Check it with `openssl pkcs12 -in QRReader-Dev.p12 -info -noout` (add `-legacy` if OpenSSL rejects the algorithm): it must list both a certificate bag and a shrouded keybag. Keep the `.p12` secret and out of the repo: whoever has it can sign apps that macOS treats as QR Reader. If the certificate is lost, with a new one users will have to grant permissions again once.

To check: `codesign -d -r- "build/QR Reader.app"` must show `certificate leaf = H"…"`, not `cdhash`.

## Permissions

| Permission | Needed for | When it is requested |
|---|---|---|
| Screen Recording | Viewfinder, Select area | First use. After granting it, **relaunch the app**. |
| Camera | Webcam | First use |
| Location | Wi-Fi connection (macOS hides SSIDs without this permission) | First "Connect". If denied, the app falls back to `networksetup`. |

### Permissions requested again on every local build

Local builds are signed ad-hoc, so macOS treats each build as a different app. To avoid this, use the [signing certificate](#signing-certificate-one-time-only): `CODESIGN_IDENTITY="QRReader Dev" scripts/build-app.sh install`.

## Translations

Texts are written in English in the code (`String(localized:)`, SwiftUI literals) and translated in `Resources/it.lproj/Localizable.strings`; permission prompts in `Resources/it.lproj/InfoPlist.strings`. After adding or changing a text, update the Italian file and run `scripts/check-strings.sh`: it lists missing and unused translations.

## Structure

```
Sources/QRCore/      decoder (Vision), content parser, auto-update (Update/). No AppKit
Sources/QRReader/    app: menu bar, viewfinder, area selection, webcam, Wi-Fi, shortcuts (Shortcuts/), updates
Resources/           Info.plist, icon, translations (it.lproj)
Tests/QRCoreTests/   swift-testing
scripts/             .app build, icon, tests, translation check
```
