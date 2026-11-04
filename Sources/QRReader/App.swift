import AppKit
import QRCore
import SwiftUI

@main
struct QRReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("QR Reader", systemImage: "qrcode.viewfinder") {
            MenuContent(history: AppController.shared.history, updates: AppController.shared.updates,
                        shortcuts: AppController.shared.shortcuts)
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
    @ObservedObject var shortcuts: Shortcuts
    private var controller: AppController { .shared }

    var body: some View {
        Button("Screen Viewfinder") { controller.toggleViewfinder() }
            .keyboardShortcut(shortcuts.assigned[.viewfinder]?.keyboardShortcut)
        Button("Select Area…") { controller.startRegionSelection() }
            .keyboardShortcut(shortcuts.assigned[.region]?.keyboardShortcut)
        Button("Webcam") { controller.toggleCamera() }
            .keyboardShortcut(shortcuts.assigned[.camera]?.keyboardShortcut)
        Divider()
        Menu("History") {
            if history.items.isEmpty {
                Text("No scans")
            } else {
                ForEach(history.items) { item in
                    Button(QRPayload.parse(item.raw).summary) { controller.showFromHistory(item) }
                }
                Divider()
                Button("Clear History") { history.clear() }
            }
        }
        Divider()
        if let version = updates.version {
            switch updates.state {
            case .available(let release):
                Button("⬆️ Update to \(release.version.description)") { updates.install(release) }
            case .installing:
                Text("Updating…")
            case .idle:
                Button("Check for Updates… (\(version))") { Task { await updates.check(manual: true) } }
            }
        }
        Button(shortcuts.unavailable.isEmpty ? LocalizedStringKey("Shortcuts…") : LocalizedStringKey("⚠️ Shortcuts…")) { controller.showShortcuts() }
            .keyboardShortcut(",")
        Button("About QR Reader") { controller.showAbout() }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
