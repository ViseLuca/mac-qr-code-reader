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
            if Prompt.confirm(String(localized: "QR Reader \(release.version.description) is available"),
                              info: String(localized: "You have \(version ?? "?"). The update downloads from GitHub and the app relaunches by itself. Afterwards macOS may ask again for the Camera and Screen Recording permissions."),
                              confirm: String(localized: "Update Now")) {
                install(release)
            }
        case .success(nil):
            state = .idle
            if manual { Prompt.message(String(localized: "QR Reader is up to date"), info: String(localized: "You have the latest version (\(version ?? "?")).")) }
        case .failure(let error):
            if manual { Prompt.message(String(localized: "Update check failed"), info: error.localizedDescription) }
        }
    }

    func install(_ release: Release) {
        guard updater.canInstall else {
            Prompt.message(String(localized: "QR Reader cannot update itself"),
                           info: String(localized: "It is not allowed to replace itself in its folder. Download \(Updater.assetName) from the release page that opens and replace the app."))
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
                if Prompt.confirm(String(localized: "Update failed"), info: error.localizedDescription, confirm: String(localized: "Open Release")) {
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
            Prompt.message(String(localized: "Update installed"), info: String(localized: "Reopen QR Reader to use the new version."))
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

    @MainActor static func confirm(_ title: String, info: String, confirm: String, cancel: String = String(localized: "Cancel")) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: cancel)
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
