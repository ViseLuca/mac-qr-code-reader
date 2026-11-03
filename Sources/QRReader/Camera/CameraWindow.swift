import AppKit
import AVFoundation

/// Window with a live, mirrored webcam preview. Closing it stops the camera.
@MainActor
final class CameraWindowController: NSObject, NSWindowDelegate {
    var onDetect: (([String]) -> Void)?
    var onClose: (() -> Void)?

    private let scanner = CameraScanner()
    private let window: NSWindow
    private let preview: CameraPreviewView

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        preview = CameraPreviewView(session: scanner.session)
        super.init()
        window.title = "Webcam QR"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 320, height: 240)
        window.contentView = preview
        window.delegate = self
        scanner.onDetect = { [weak self] raws in
            self?.preview.flash()
            self?.onDetect?(raws)
        }
    }

    func show() async {
        guard await CameraScanner.requestAccess() else {
            fail(CameraError.denied, settingsPane: "Privacy_Camera")
            return
        }
        do {
            try scanner.configure()
        } catch {
            fail(error, settingsPane: nil)
            return
        }
        preview.configureMirroring()
        scanner.start()
        window.center()
        // Stay above other windows: the user is usually busy holding a phone up to the camera.
        window.level = .floating
        bringToFront()
    }

    var isKeyWindow: Bool { window.isKeyWindow }

    /// Menu bar apps are not reliably activated by `NSApp.activate()` (cooperative activation,
    /// macOS 14+), so also force the window to the front.
    func bringToFront() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func close() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        scanner.stop()
        onClose?()
    }

    private func fail(_ error: Error, settingsPane: String?) {
        onClose?()
        let alert = NSAlert()
        alert.messageText = "Webcam non disponibile"
        alert.informativeText = error.localizedDescription
        if settingsPane != nil { alert.addButton(withTitle: "Apri Impostazioni") }
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn, let settingsPane {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsPane)")!)
        }
    }
}

final class CameraPreviewView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let hint = NSTextField(labelWithString: "Inquadra un QR code")

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.borderColor = NSColor.systemGreen.cgColor
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)

        hint.textColor = .white
        hint.font = .systemFont(ofSize: 13, weight: .medium)
        hint.wantsLayer = true
        hint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        hint.layer?.cornerRadius = 6
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }

    func configureMirroring() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }

    /// Green border pulse on detection.
    func flash() {
        layer?.borderWidth = 6
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.layer?.borderWidth = 0 }
    }
}
