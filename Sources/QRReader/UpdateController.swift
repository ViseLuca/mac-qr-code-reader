import AppKit
import QRCore

/// Looks for a newer GitHub release at launch and every few hours, offers it once, installs it and relaunches.
@MainActor
final class UpdateController: ObservableObject {
    enum State: Equatable {
        case idle
        case available(Release)
        case installing
    }

    @Published private(set) var state = State.idle
    private let updater = Updater()
    private var loop: Task<Void, Never>?
    /// The release already offered with an alert, so periodic checks do not ask again.
    private var offered: AppVersion?

    var version: String? { updater.currentVersion?.description }

    func start() {
        guard updater.currentVersion != nil, loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check(manual: false)
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    /// An automatic check speaks only when there is something new; a manual one always answers.
    func check(manual: Bool) async {
        if state == .installing { return }
        let result: Result<Release?, Error>
        do {
            result = .success(try await updater.newerRelease())
        } catch {
            result = .failure(error)
        }
        if state == .installing { return }

        switch result {
        case .success(let release?):
            state = .available(release)
            guard manual || (offered != release.version && NSApp.modalWindow == nil) else { return }
            offered = release.version
            if Prompt.confirm("È disponibile QR Reader \(release.version)",
                              info: "Hai la \(version ?? "?"). L'aggiornamento si scarica da GitHub e l'app si riavvia da sola. Dopo, macOS potrebbe chiedere di nuovo i permessi Fotocamera e Registrazione schermo.",
                              confirm: "Aggiorna ora") {
                install(release)
            }
        case .success(nil):
            state = .idle
            if manual { Prompt.message("QR Reader è aggiornato", info: "Hai l'ultima versione (\(version ?? "?")).") }
        case .failure(let error):
            if manual { Prompt.message("Controllo aggiornamenti non riuscito", info: error.localizedDescription) }
        }
    }

    func install(_ release: Release) {
        guard updater.canInstall else {
            Prompt.message("QR Reader non può aggiornarsi da solo",
                           info: "Non ha i permessi per sostituirsi nella sua cartella. Scarica \(Updater.assetName) dalla pagina della release che si apre e sostituisci l'app.")
            NSWorkspace.shared.open(release.page)
            return
        }
        state = .installing
        let updater = updater
        Task {
            do {
                try await updater.install(release)
                Self.relaunch(updater.appURL)
            } catch {
                state = .available(release)
                if Prompt.confirm("Aggiornamento non riuscito", info: error.localizedDescription, confirm: "Apri la release") {
                    NSWorkspace.shared.open(release.page)
                }
            }
        }
    }

    /// Quits, and reopens the new copy once this process is gone.
    private static func relaunch(_ app: URL) {
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
        reopen.arguments = ["-c", #"while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; open "$2""#,
                            "sh", String(ProcessInfo.processInfo.processIdentifier), app.path]
        if (try? reopen.run()) == nil {
            Prompt.message("Aggiornamento installato", info: "Riapri QR Reader per usare la nuova versione.")
        }
        NSApp.terminate(nil)
    }
}

enum Prompt {
    @MainActor static func message(_ title: String, info: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        NSApp.activate()
        alert.runModal()
    }

    @MainActor static func confirm(_ title: String, info: String, confirm: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Annulla")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
