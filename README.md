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

## Installazione

### Con il Terminale (consigliato)

Apri **Terminale** (Spotlight ⌘Spazio › "Terminale"), incolla questa riga e premi Invio:

```sh
curl -fsSL https://raw.githubusercontent.com/ViseLuca/mac-qr-code-reader/main/scripts/install.sh | bash
```

Scarica l'ultima versione, la verifica, la installa in `Applicazioni` e la apre. Nessun avviso di macOS: i file scaricati con `curl` non vengono bloccati da Gatekeeper come quelli scaricati dal browser. Rilanciala quando vuoi per reinstallare.

### Dal browser

1. Scarica **[QRReader.zip](https://github.com/ViseLuca/mac-qr-code-reader/releases/latest/download/QRReader.zip)** dall'[ultima release](https://github.com/ViseLuca/mac-qr-code-reader/releases/latest).
2. Estrai lo zip e sposta `QR Reader.app` in `Applicazioni`.
3. L'app è gratuita e non è notarizzata da Apple, quindi al primo avvio macOS la blocca. Sbloccala una volta: prova ad aprirla, chiudi l'avviso, poi vai in *Impostazioni di Sistema › Privacy e sicurezza*, scorri in fondo e premi **Apri comunque**.

Per averla sempre a portata: *Impostazioni › Generali › Elementi login* › aggiungi QR Reader.

### Dai sorgenti

Servono macOS 14+ e i Command Line Tools (`xcode-select --install`), Xcode non serve.

```sh
scripts/build-app.sh install
```

| Comando | Cosa fa |
|---|---|
| `scripts/build-app.sh` | Build universale (Apple Silicon + Intel) in `build/QR Reader.app` |
| `scripts/build-app.sh install` | Build, copia in `/Applications` e riavvia |
| `scripts/build-app.sh dist 0.2.0` | Build della versione 0.2.0 firmata con `QRReader Dev` e zip in `build/QRReader.zip` per una release |
| `scripts/build-app.sh icon` | Ridisegna `Resources/AppIcon.icns` da `scripts/make-icon.swift` |
| `scripts/test.sh` | Test unitari (parser, decoder, aggiornamenti) |

> Usa sempre il `.app` e non `swift run`: senza Info.plist macOS chiude l'app appena accede alla fotocamera.

## Aggiornamenti

All'avvio e ogni 6 ore QR Reader controlla l'[ultima release](https://github.com/ViseLuca/mac-qr-code-reader/releases/latest) su GitHub. Se è più recente della versione installata, propone di installarla: scarica `QRReader.zip`, lo verifica con lo SHA-256 pubblicato da GitHub, controlla che contenga QR Reader alla versione della release con una firma valida, sostituisce l'app e la riavvia. Se l'app è in una cartella in cui non può scrivere, apre la pagina della release.

Dal menu: **Controlla aggiornamenti…**, che diventa **⬆️ Aggiorna alla x.y.z** quando ce n'è una.

### Pubblicare una release

```sh
scripts/build-app.sh dist 0.2.0
gh release create 0.2.0 build/QRReader.zip
```

L'asset deve chiamarsi `QRReader.zip`. Le build locali (`scripts/build-app.sh`, `install`) prendono la versione dall'ultimo tag git.

`dist` firma con il certificato self-signed `QRReader Dev` (un altro con `CODESIGN_IDENTITY="…"`) e rifiuta la firma ad-hoc: con una firma sempre uguale macOS riconosce ogni versione come la stessa app e gli utenti non devono riconcedere i permessi a ogni aggiornamento.

#### Certificato di firma (una volta sola)

1. *Accesso Portachiavi › Assistente Certificato › Crea un certificato…*
2. Nome `QRReader Dev`, tipo identità *Radice autofirmata*, tipo certificato *Firma del codice*, spunta **Lascia che sia io a sovrascrivere i valori predefiniti**.
3. *Periodo di validità*: `3650` giorni (il predefinito è un anno, poi `codesign` smette di firmare). Conferma il resto con Continua.
4. Fai un backup: in Accesso Portachiavi, *I miei certificati* › tasto destro su `QRReader Dev` › **Esporta** in `.p12`, con una password, in un posto sicuro (es. 1Password). Se il certificato va perso, con uno nuovo gli utenti dovranno riconcedere i permessi una volta.

Per controllare: `codesign -d -r- "build/QR Reader.app"` deve mostrare `certificate leaf = H"…"`, non `cdhash`.

## Permessi

| Permesso | Serve per | Quando viene chiesto |
|---|---|---|
| Registrazione schermo | Mirino, Seleziona area | Primo utilizzo. Dopo averlo concesso **riavvia l'app**. |
| Fotocamera | Webcam | Primo utilizzo |
| Posizione | Connessione Wi-Fi (macOS nasconde gli SSID senza questo permesso) | Primo "Connetti". Se lo neghi, l'app usa `networksetup` come alternativa. |

### Permessi richiesti di nuovo a ogni build locale

Le build locali sono firmate ad-hoc, quindi macOS considera ogni build un'app diversa. Per evitarlo usa il [certificato di firma](#certificato-di-firma-una-volta-sola): `CODESIGN_IDENTITY="QRReader Dev" scripts/build-app.sh install`.

## Struttura

```
Sources/QRCore/      decoder (Vision), parser dei contenuti, auto-update (Update/). Niente AppKit
Sources/QRReader/    app: menu bar, mirino, selezione area, webcam, Wi-Fi, scorciatoie, aggiornamenti
Tests/QRCoreTests/   swift-testing
scripts/             build del .app, icona, test
```
