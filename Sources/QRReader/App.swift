import AppKit
import QRCore
import SwiftUI

@main
struct QRReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("QR Reader", systemImage: "qrcode.viewfinder") {
            MenuContent(history: AppController.shared.history, updates: AppController.shared.updates)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppController.shared.setUp() }
    }
}

struct MenuContent: View {
    @ObservedObject var history: History
    @ObservedObject var updates: UpdateController
    private var controller: AppController { .shared }

    var body: some View {
        Button("Mirino sullo schermo") { controller.toggleViewfinder() }
            .keyboardShortcut("q", modifiers: [.option, .shift])
        Button("Seleziona area…") { controller.startRegionSelection() }
            .keyboardShortcut("a", modifiers: [.option, .shift])
        Button("Webcam") { controller.toggleCamera() }
            .keyboardShortcut("c", modifiers: [.option, .shift])
        Divider()
        Menu("Cronologia") {
            if history.items.isEmpty {
                Text("Nessuna scansione")
            } else {
                ForEach(history.items) { item in
                    Button(QRPayload.parse(item.raw).summary) { controller.showFromHistory(item) }
                }
                Divider()
                Button("Cancella cronologia") { history.clear() }
            }
        }
        Divider()
        if let version = updates.version {
            switch updates.state {
            case .available(let release):
                Button("⬆️ Aggiorna alla \(release.version)") { updates.install(release) }
            case .installing:
                Text("Aggiornamento in corso…")
            case .idle:
                Button("Controlla aggiornamenti… (\(version))") { Task { await updates.check(manual: true) } }
            }
        }
        Button("Esci") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
