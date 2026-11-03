import AppKit

/// Full-screen overlay (one window per display) to drag a rectangle, like ⌘⇧4.
/// A simple click without dragging selects the whole display. Esc or right-click cancels.
@MainActor
final class RegionSelector {
    private var windows: [NSWindow] = []
    private var completion: ((CGRect?) -> Void)?

    func begin(completion: @escaping (CGRect?) -> Void) {
        guard windows.isEmpty else { return }
        self.completion = completion
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { [weak self, weak window] localRect in
                guard let self, let window else { return }
                guard let localRect else { return self.finish(nil) }
                let rect = localRect.width < 8 || localRect.height < 8
                    ? window.frame
                    : localRect.offsetBy(dx: window.frame.minX, dy: window.frame.minY)
                self.finish(rect)
            }
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
        }
        NSApp.activate()
        if let mouseWindow = windows.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? windows.first {
            mouseWindow.makeKey()
            mouseWindow.makeFirstResponder(mouseWindow.contentView)
        }
        NSCursor.crosshair.push()
    }

    private func finish(_ rect: CGRect?) {
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        windows = []
        let completion = self.completion
        self.completion = nil
        completion?(rect)
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var onFinish: ((NSRect?) -> Void)?
    private var start: NSPoint?
    private var current: NSPoint?

    private var selection: NSRect? {
        guard let start, let current else { return nil }
        return NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        if let selection {
            dim.append(NSBezierPath(rect: selection))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.3).setFill()
        dim.fill()

        if let selection {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        } else {
            let hint = "Trascina per selezionare un QR · clic per tutto lo schermo · Esc per annullare" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let size = hint.size(withAttributes: attrs)
            hint.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        onFinish?(selection ?? .zero)
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish?(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onFinish?(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
