import AppKit
import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError {
    case noScreen
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .noScreen: "L'area selezionata non è su nessuno schermo."
        case .noDisplay: "Schermo non disponibile per la cattura."
        }
    }
}

/// Captures a region of the screen with ScreenCaptureKit, excluding this app's own windows
/// (so the viewfinder frame and result panel never end up in the image).
@MainActor
final class ScreenCapturer {
    static let shared = ScreenCapturer()

    private var cachedContent: SCShareableContent?
    private var cachedAt = Date.distantPast

    /// - Parameter globalRect: rect in AppKit global coordinates (origin bottom-left of the main screen).
    func capture(globalRect: CGRect) async throws -> CGImage {
        let center = CGPoint(x: globalRect.midX, y: globalRect.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) else {
            throw ScreenCaptureError.noScreen
        }
        let rect = globalRect.intersection(screen.frame)
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { throw ScreenCaptureError.noScreen }
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { throw ScreenCaptureError.noDisplay }

        var content = try await shareableContent(forceRefresh: false)
        var display = content.displays.first { $0.displayID == displayID }
        if display == nil {
            content = try await shareableContent(forceRefresh: true)
            display = content.displays.first { $0.displayID == displayID }
        }
        guard let display else { throw ScreenCaptureError.noDisplay }

        let pid = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == pid }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let config = SCStreamConfiguration()
        // sourceRect is in display points with a top-left origin.
        config.sourceRect = CGRect(x: rect.minX - screen.frame.minX,
                                   y: screen.frame.maxY - rect.maxY,
                                   width: rect.width, height: rect.height)
        config.width = Int(rect.width * screen.backingScaleFactor)
        config.height = Int(rect.height * screen.backingScaleFactor)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private func shareableContent(forceRefresh: Bool) async throws -> SCShareableContent {
        if !forceRefresh, let cachedContent, Date().timeIntervalSince(cachedAt) < 10 {
            return cachedContent
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        cachedContent = content
        cachedAt = Date()
        return content
    }
}
