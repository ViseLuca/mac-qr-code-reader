import AppKit
import QRCore
import SwiftUI

enum WifiStatus: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)
}

@MainActor
final class ResultModel: ObservableObject {
    @Published var payloads: [QRPayload] = []
    @Published var message: String?
    @Published var wifiStatus: [Int: WifiStatus] = [:]

    func connect(index: Int) {
        guard payloads.indices.contains(index), case .wifi(let wifi) = payloads[index] else { return }
        wifiStatus[index] = .connecting
        Task {
            do {
                try await WifiJoiner.join(wifi)
                wifiStatus[index] = .connected
            } catch {
                if let password = wifi.password { Clipboard.copy(password) }
                wifiStatus[index] = .failed(error.localizedDescription)
            }
        }
    }
}

/// Floating, non-activating panel that shows the latest scan result.
@MainActor
final class ResultPanelController {
    private let model = ResultModel()
    private lazy var panel: NSPanel = makePanel()

    func show(raws: [String]) {
        model.payloads = raws.map(QRPayload.parse)
        model.message = nil
        model.wifiStatus = [:]
        present()
    }

    func showMessage(_ message: String) {
        model.payloads = []
        model.message = message
        model.wifiStatus = [:]
        present()
    }

    private func present() {
        if !panel.isVisible, let screen = NSScreen.main {
            panel.layoutIfNeeded()
            let frame = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - panel.frame.width - 20, y: frame.maxY - 20))
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 160),
                            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "QR Reader"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingController(rootView: ResultView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        return panel
    }
}

// MARK: - Views

struct ResultView: View {
    @ObservedObject var model: ResultModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let message = model.message {
                Label(message, systemImage: "qrcode.viewfinder")
            }
            ForEach(Array(model.payloads.enumerated()), id: \.offset) { index, payload in
                if index > 0 { Divider() }
                PayloadCard(payload: payload, status: model.wifiStatus[index] ?? .idle) {
                    model.connect(index: index)
                }
            }
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct PayloadCard: View {
    let payload: QRPayload
    let status: WifiStatus
    let onConnect: () -> Void

    var body: some View {
        switch payload {
        case .wifi(let wifi): wifiCard(wifi)
        case .url(let url): urlCard(url)
        case .contact(let vcard): contactCard(vcard)
        case .text(let text): textCard(text)
        }
    }

    private func wifiCard(_ wifi: WifiCredentials) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Wi-Fi Network", systemImage: "wifi").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("Network").foregroundStyle(.secondary)
                    Text(wifi.ssid).textSelection(.enabled)
                }
                GridRow {
                    Text("Password").foregroundStyle(.secondary)
                    Text(wifi.password ?? "—").font(.body.monospaced()).textSelection(.enabled)
                }
                GridRow {
                    Text("Security").foregroundStyle(.secondary)
                    Text(wifi.security.displayName + (wifi.hidden ? " · " + String(localized: "hidden", comment: "Wi-Fi network") : ""))
                }
            }
            HStack {
                Button("Connect", action: onConnect)
                    .keyboardShortcut(.defaultAction)
                    .disabled(status == .connecting || status == .connected)
                if let password = wifi.password {
                    Button("Copy Password") { Clipboard.copy(password) }
                }
                Spacer()
                statusView
            }
            if case .failed(let reason) = status {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reason).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    Text(wifi.password == nil ? "" : LocalizedStringKey("Password copied to the clipboard.")).font(.caption).foregroundStyle(.secondary)
                    Button("Open Wi-Fi Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .idle: EmptyView()
        case .connecting: ProgressView().controlSize(.small)
        case .connected: Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Label("Error", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private func urlCard(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Link", systemImage: "link").font(.headline)
            Text(url.absoluteString).textSelection(.enabled).lineLimit(4)
            HStack {
                Button("Open") { NSWorkspace.shared.open(url) }.keyboardShortcut(.defaultAction)
                Button("Copy") { Clipboard.copy(url.absoluteString) }
            }
        }
    }

    private func contactCard(_ vcard: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(payload.summary, systemImage: "person.crop.circle").font(.headline)
            HStack {
                Button("Add to Contacts") { Self.openVCard(vcard) }.keyboardShortcut(.defaultAction)
                Button("Copy") { Clipboard.copy(vcard) }
            }
        }
    }

    private func textCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Text", systemImage: "text.alignleft").font(.headline)
            ScrollView {
                Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .fixedSize(horizontal: false, vertical: true)
            Button("Copy") { Clipboard.copy(text) }.keyboardShortcut(.defaultAction)
        }
    }

    private static func openVCard(_ vcard: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(String(localized: "QR Contact") + ".vcf")
        do {
            try vcard.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }
}

enum Clipboard {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
