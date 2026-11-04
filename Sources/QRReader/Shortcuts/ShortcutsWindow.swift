import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The "Scorciatoie" window: click a shortcut, then press the new combination.
@MainActor
final class ShortcutsWindowController: NSObject, NSWindowDelegate {
    private let shortcuts: Shortcuts
    private let recorder: ShortcutRecorder
    private var window: NSWindow?

    init(shortcuts: Shortcuts) {
        self.shortcuts = shortcuts
        recorder = ShortcutRecorder(shortcuts: shortcuts)
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: ShortcutsView(shortcuts: shortcuts, recorder: recorder)))
            window.title = "Scorciatoie"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        // Menu bar apps are not reliably activated by `NSApp.activate()` alone (see CameraWindowController).
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        recorder.stop()
    }
}

/// Captures the next key combination pressed in the app's windows and assigns it to an action.
@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var action: ShortcutAction?
    @Published private(set) var rejected = false
    private let shortcuts: Shortcuts
    private var monitor: Any?

    init(shortcuts: Shortcuts) {
        self.shortcuts = shortcuts
    }

    func start(_ action: ShortcutAction) {
        stop()
        self.action = action
        shortcuts.isSuspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        action = nil
        rejected = false
        shortcuts.isSuspended = false
    }

    private func handle(_ event: NSEvent) {
        guard let action else { return }
        switch Int(event.keyCode) {
        case kVK_Escape:
            stop()
        case kVK_Delete, kVK_ForwardDelete:
            shortcuts.set(nil, for: action)
            stop()
        default:
            guard let shortcut = Shortcut(event: event) else {
                rejected = true
                NSSound.beep()
                return
            }
            shortcuts.set(shortcut, for: action)
            stop()
        }
    }
}

struct ShortcutsView: View {
    @ObservedObject var shortcuts: Shortcuts
    @ObservedObject var recorder: ShortcutRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                ForEach(ShortcutAction.allCases) { action in
                    GridRow {
                        Text(action.title)
                        Button {
                            recorder.action == action ? recorder.stop() : recorder.start(action)
                        } label: {
                            Text(label(for: action)).frame(minWidth: 150)
                        }
                        Button {
                            shortcuts.set(action.defaultShortcut, for: action)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Ripristina \(action.defaultShortcut.display)")
                        .disabled(shortcuts.assigned[action] == action.defaultShortcut)
                    }
                    if shortcuts.unavailable.contains(action) {
                        GridRow {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            Text("Già usata da un'altra app: scegline un'altra.")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .gridCellColumns(2)
                        }
                    }
                }
            }
            Text("Clicca una scorciatoia e premi la nuova combinazione, con almeno ⌘, ⌥ o ⌃ (i tasti F1–F12 anche da soli). Esc annulla, ⌫ la toglie.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 440)
    }

    private func label(for action: ShortcutAction) -> String {
        if recorder.action == action {
            return recorder.rejected ? "Aggiungi ⌘, ⌥ o ⌃" : "Premi i tasti…"
        }
        return shortcuts.assigned[action]?.display ?? "Nessuna"
    }
}
