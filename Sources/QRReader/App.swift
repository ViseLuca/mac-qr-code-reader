import AppKit
import QRCore
import SwiftUI

@main
struct QRReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("QR Reader", systemImage: "qrcode.viewfinder") {
            MenuContent(history: AppController.shared.history)
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
        Button("Esci") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
