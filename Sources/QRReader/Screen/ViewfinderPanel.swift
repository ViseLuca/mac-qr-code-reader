import AppKit
import QRCore

/// Floating frame that continuously scans whatever is underneath it.
/// Drag the frame to move it, drag a corner to resize, ✕ to close.
/// The transparent interior is click-through.
@MainActor
final class ViewfinderController {
    var onDetect: (([String]) -> Void)?
    var onError: ((Error) -> Void)?
    var onClose: (() -> Void)?

    private let panel: NSPanel
    private let view: ViewfinderView
    private var scanLoop: Task<Void, Never>?
    private var mouseTimer: Timer?
    private var foundUntil = Date.distantPast

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 300),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        view = ViewfinderView(frame: panel.contentLayoutRect)
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        view.onClose = { [weak self] in self?.close() }
    }

    func show() {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()

        scanLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scanOnce()
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        // Make the interior click-through: ignore mouse events while the pointer is inside it.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouseThrough() }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    func close() {
        scanLoop?.cancel()
        scanLoop = nil
        mouseTimer?.invalidate()
        mouseTimer = nil
        panel.orderOut(nil)
        onClose?()
    }

    private var interiorGlobalRect: CGRect {
        view.interiorRect.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
    }

    private func updateMouseThrough() {
        guard !view.isInteracting else { return }
        let inside = interiorGlobalRect.insetBy(dx: 2, dy: 2).contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents != inside { panel.ignoresMouseEvents = inside }
    }

    private func scanOnce() async {
        guard !view.isInteracting else { return }
        do {
            let image = try await ScreenCapturer.shared.capture(globalRect: interiorGlobalRect)
            let raws = await Task.detached { QRDecoder.decode(cgImage: image) }.value
            guard !Task.isCancelled else { return }
            if !raws.isEmpty {
                foundUntil = Date().addingTimeInterval(1)
                onDetect?(raws)
            }
            view.found = Date() < foundUntil
        } catch {
            guard !Task.isCancelled else { return }
            onError?(error)
        }
    }
}

final class ViewfinderView: NSView {
    static let band: CGFloat = 10
    static let topBar: CGFloat = 24

    var onClose: (() -> Void)?
    var found = false {
        didSet { if oldValue != found { needsDisplay = true } }
    }
    private(set) var isInteracting = false

    private enum Drag {
        case move
        case resize(left: Bool, bottom: Bool)
    }

    private var drag: Drag?
    private var startMouse = NSPoint.zero
    private var startFrame = NSRect.zero
    private let minSize = NSSize(width: 120, height: 130)

    var interiorRect: NSRect {
        NSRect(x: Self.band, y: Self.band,
               width: bounds.width - 2 * Self.band,
               height: bounds.height - Self.band - Self.topBar)
    }

    private var closeRect: NSRect {
        NSRect(x: bounds.maxX - Self.topBar - 2, y: bounds.maxY - Self.topBar, width: Self.topBar, height: Self.topBar)
    }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)

        let accent: NSColor = found ? .systemGreen : .white
        let frame = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        frame.append(NSBezierPath(rect: interiorRect))
        frame.windingRule = .evenOdd
        (found ? NSColor.systemGreen.withAlphaComponent(0.55) : NSColor.black.withAlphaComponent(0.5)).setFill()
        frame.fill()

        // Corner brackets around the scan area.
        let r = interiorRect
        let length = min(28, r.width / 3, r.height / 3)
        let brackets = NSBezierPath()
        brackets.lineWidth = 4
        brackets.lineCapStyle = .round
        for (corner, dx, dy) in [(NSPoint(x: r.minX, y: r.minY), 1.0, 1.0), (NSPoint(x: r.maxX, y: r.minY), -1.0, 1.0),
                                 (NSPoint(x: r.minX, y: r.maxY), 1.0, -1.0), (NSPoint(x: r.maxX, y: r.maxY), -1.0, -1.0)] {
            brackets.move(to: NSPoint(x: corner.x + dx * length, y: corner.y))
            brackets.line(to: corner)
            brackets.line(to: NSPoint(x: corner.x, y: corner.y + dy * length))
        }
        accent.setStroke()
        brackets.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let title = (found ? String(localized: "QR found") : String(localized: "QR Viewfinder")) as NSString
        title.draw(at: NSPoint(x: Self.band + 2, y: bounds.maxY - Self.topBar + 6), withAttributes: attrs)

        let close = "✕" as NSString
        let closeSize = close.size(withAttributes: attrs)
        close.draw(at: NSPoint(x: closeRect.midX - closeSize.width / 2, y: closeRect.midY - closeSize.height / 2),
                   withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if closeRect.contains(point) {
            onClose?()
            return
        }
        guard let window else { return }
        isInteracting = true
        startMouse = NSEvent.mouseLocation
        startFrame = window.frame
        let grip: CGFloat = 22
        let nearLeft = point.x < grip, nearRight = point.x > bounds.maxX - grip
        let nearBottom = point.y < grip, nearTop = point.y > bounds.maxY - grip
        drag = (nearLeft || nearRight) && (nearBottom || nearTop) ? .resize(left: nearLeft, bottom: nearBottom) : .move
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let drag else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - startMouse.x, dy = mouse.y - startMouse.y
        var frame = startFrame
        switch drag {
        case .move:
            frame.origin.x += dx
            frame.origin.y += dy
        case .resize(let left, let bottom):
            if left {
                frame.size.width = max(minSize.width, startFrame.width - dx)
                frame.origin.x = startFrame.maxX - frame.width
            } else {
                frame.size.width = max(minSize.width, startFrame.width + dx)
            }
            if bottom {
                frame.size.height = max(minSize.height, startFrame.height - dy)
                frame.origin.y = startFrame.maxY - frame.height
            } else {
                frame.size.height = max(minSize.height, startFrame.height + dy)
            }
        }
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        drag = nil
        isInteracting = false
    }
}
