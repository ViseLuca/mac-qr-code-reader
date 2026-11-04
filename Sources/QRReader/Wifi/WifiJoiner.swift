import CoreLocation
import CoreWLAN
import Foundation
import QRCore

enum WifiJoinError: LocalizedError {
    case noInterface
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noInterface: String(localized: "No Wi-Fi interface found.")
        case .failed(let reason): String(localized: "Connection failed: \(reason)")
        }
    }
}

/// Joins a Wi-Fi network: CoreWLAN first, `networksetup` as fallback
/// (covers hidden networks and denied Location permission, which hides SSIDs from scans).
enum WifiJoiner {
    static func join(_ wifi: WifiCredentials) async throws {
        await LocationAuthorizer.shared.requestIfNeeded()
        try await Task.detached(priority: .userInitiated) {
            try joinBlocking(ssid: wifi.ssid, password: wifi.password)
        }.value
    }

    private static func joinBlocking(ssid: String, password: String?) throws {
        guard let interface = CWWiFiClient.shared().interface() else { throw WifiJoinError.noInterface }
        if interface.ssid() == ssid { return }

        var coreWLANError: Error?
        do {
            if let network = try interface.scanForNetworks(withName: ssid).first(where: { $0.ssid == ssid }) {
                try interface.associate(to: network, password: password)
                return
            }
        } catch {
            coreWLANError = error
        }
        try networksetupJoin(interface: interface.interfaceName ?? "en0", ssid: ssid, password: password,
                             previousError: coreWLANError)
    }

    private static func networksetupJoin(interface: String, ssid: String, password: String?, previousError: Error?) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-setairportnetwork", interface, ssid] + (password.map { [$0] } ?? [])
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit()

        let failureMarkers = ["error", "could not", "failed", "unable"]
        if process.terminationStatus != 0 || failureMarkers.contains(where: output.lowercased().contains) {
            throw WifiJoinError.failed(output.isEmpty ? (previousError?.localizedDescription ?? String(localized: "unknown error")) : output)
        }
    }
}

/// CoreWLAN only reveals SSIDs to apps with Location permission.
@MainActor
final class LocationAuthorizer: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAuthorizer()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Void, Never>?

    func requestIfNeeded() async {
        guard manager.authorizationStatus == .notDetermined, continuation == nil else { return }
        manager.delegate = self
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestWhenInUseAuthorization()
            // Don't hang forever if the prompt never appears.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                self?.resume()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status != .notDetermined { self.resume() }
        }
    }

    private func resume() {
        continuation?.resume()
        continuation = nil
    }
}
