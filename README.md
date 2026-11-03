# mac-qr-code-reader

Lettore di QR code per macOS, nella barra dei menu. Nativo (Swift, Vision, ScreenCaptureKit, AVFoundation, CoreWLAN), nessuna dipendenza.

## Modalità

| Modalità | Scorciatoia | Cosa fa |
|---|---|---|
| **Mirino sullo schermo** | ⌥⇧Q | Riquadro flottante che scansiona in continuo ciò che c'è sotto. Trascina il bordo per spostarlo, un angolo per ridimensionarlo, ✕ per chiuderlo. L'interno lascia passare i clic. |
| **Seleziona area** | ⌥⇧A | Trascina un rettangolo come con ⌘⇧4. Un clic senza trascinare scansiona tutto lo schermo, Esc annulla. |
| **Webcam** | ⌥⇧C | Finestra con anteprima live. Chiudila per spegnere la fotocamera. |

Il risultato compare in un pannello flottante con azioni in base al contenuto:
- **Wi-Fi** (`WIFI:T:WPA;S:…;P:…;;`): Connetti, Copia password
- **Link**: Apri, Copia
- **vCard**: Aggiungi ai Contatti
- **Testo**: Copia

Le ultime 20 scansioni sono nel menu *Cronologia* (salvate in chiaro in UserDefaults, password Wi-Fi comprese).

## Requisiti

- macOS 14+
- Swift 6 (bastano i Command Line Tools: `xcode-select --install`)

## Build

```sh
scripts/build-app.sh          # → build/QRReader.app
open build/QRReader.app
scripts/test.sh               # test unitari (parser + decoder)
```

Per averla sempre a portata: copia `build/QRReader.app` in `/Applications` e aggiungila a *Impostazioni › Generali › Elementi login*.

> Usa sempre il `.app` e non `swift run`: senza Info.plist macOS chiude l'app appena accede alla fotocamera.

## Permessi

| Permesso | Serve per | Quando viene chiesto |
|---|---|---|
| Registrazione schermo | Mirino, Seleziona area | Primo utilizzo. Dopo averlo concesso **riavvia l'app**. |
| Fotocamera | Webcam | Primo utilizzo |
| Posizione | Connessione Wi-Fi (macOS nasconde gli SSID senza questo permesso) | Primo "Connetti". Se lo neghi, l'app usa `networksetup` come alternativa. |

### Permessi richiesti di nuovo a ogni build

La firma predefinita è ad-hoc, quindi macOS considera ogni build un'app diversa. Per evitarlo, crea una volta un certificato personale:

1. *Accesso Portachiavi › Assistente Certificato › Crea un certificato…*
2. Nome `QRReader Dev`, tipo *Firma del codice*
3. `CODESIGN_IDENTITY="QRReader Dev" scripts/build-app.sh`

## Struttura

```
Sources/QRCore/      decoder (Vision) + parser dei contenuti, testabili
Sources/QRReader/    app: menu bar, mirino, selezione area, webcam, Wi-Fi, scorciatoie
Tests/QRCoreTests/   swift-testing
scripts/             build del .app e test
```
