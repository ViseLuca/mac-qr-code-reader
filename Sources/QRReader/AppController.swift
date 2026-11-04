import AppKit
import QRCore

/// Central coordinator: owns the scan modes and routes detections to the result panel.
@MainActor
final class AppController {
    static let shared = AppController()

    let history = History()
    let updates = UpdateController()
    let shortcuts = Shortcuts()
    private lazy var shortcutsWindow = ShortcutsWindowController(shortcuts: shortcuts)
    private let resultPanel = ResultPanelController()
    private let regionSelector = RegionSelector()
    private var viewfinder: ViewfinderController?
    private var camera: CameraWindowController?

    /// Continuous modes (viewfinder, webcam) report the same code many times per second.
    /// A code is reported again only after it has been out of sight for `repeatInterval`.
    private var lastRaws: [String] = []
    private var lastSeen = Date.distantPast
    private let repeatInterval: TimeInterval = 3

    func setUp() {
        shortcuts.start(handlers: [
            .viewfinder: { [weak self] in self?.toggleViewfinder() },
            .region: { [weak self] in self?.startRegionSelection() },
            .camera: { [weak self] in self?.toggleCamera() },
        ])
        updates.start()
    }

    // MARK: - Modes

    func toggleViewfinder() {
        if let viewfinder {
            viewfinder.close()
            return
        }
        let controller = ViewfinderController()
        controller.onDetect = { [weak self] raws in self?.handleContinuous(raws) }
        controller.onError = { [weak self] error in self?.showScreenCaptureError(error) }
        controller.onClose = { [weak self] in self?.viewfinder = nil }
        viewfinder = controller
        controller.show()
    }

    func startRegionSelection() {
        regionSelector.begin { [weak self] rect in
            guard let self, let rect else { return }
            Task { await self.scanRegion(rect) }
        }
    }

    func toggleCamera() {
        if let camera {
            camera.isKeyWindow ? camera.close() : camera.bringToFront()
            return
        }
        let controller = CameraWindowController()
        controller.onDetect = { [weak self] raws in self?.handleContinuous(raws) }
        controller.onClose = { [weak self] in self?.camera = nil }
        camera = controller
        Task { await controller.show() }
    }

    func showFromHistory(_ item: History.Item) {
        resultPanel.show(raws: [item.raw])
    }

    func showShortcuts() {
        shortcutsWindow.show()
    }

    func showAbout() {
        let repo = URL(string: "https://github.com/\(Updater.repo)")!
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let title = ["QR Reader", version].compactMap { $0 }.joined(separator: " ")
        let info = "Lettore di QR code per la barra dei menu. Gratuito e open source.\n\n\(repo.host()!)\(repo.path())"
        if Prompt.confirm(title, info: info, confirm: "Apri su GitHub", cancel: "Chiudi") {
            NSWorkspace.shared.open(repo)
        }
    }

    // MARK: - Detection handling

    private func scanRegion(_ rect: CGRect) async {
        do {
            let image = try await ScreenCapturer.shared.capture(globalRect: rect)
            let raws = await Task.detached { QRDecoder.decode(cgImage: image) }.value
            if raws.isEmpty {
                resultPanel.showMessage("Nessun QR trovato nell'area selezionata.")
            } else {
                report(raws)
            }
        } catch {
            showScreenCaptureError(error)
        }
    }

    private func handleContinuous(_ raws: [String]) {
        let now = Date()
        defer { lastSeen = now }
        if raws == lastRaws, now.timeIntervalSince(lastSeen) < repeatInterval { return }
        lastRaws = raws
        report(raws)
    }

    private func report(_ raws: [String]) {
        raws.forEach(history.add)
        resultPanel.show(raws: raws)
    }

    private func showScreenCaptureError(_ error: Error) {
        viewfinder?.close()
        let alert = NSAlert()
        alert.messageText = "Impossibile catturare lo schermo"
        alert.informativeText = """
        \(error.localizedDescription)

        Concedi il permesso in Impostazioni di Sistema › Privacy e sicurezza › Registrazione schermo e audio, poi riavvia QR Reader.
        """
        alert.addButton(withTitle: "Apri Impostazioni")
        alert.addButton(withTitle: "Annulla")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }
}
