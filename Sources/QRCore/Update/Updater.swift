import CoreServices
import CryptoKit
import Foundation

/// Updates the app in place from the latest GitHub release: the zip that `scripts/build-app.sh dist` makes.
public struct Updater: Sendable {
    public static let repo = "ViseLuca/mac-qr-code-reader"
    public static let assetName = "QRReader.zip"

    public let appURL: URL
    /// The running version; nil outside an app bundle (`swift run`), where there is nothing to update.
    public let currentVersion: AppVersion?
    private let bundleIdentifier: String?

    public init(bundle: Bundle = .main) {
        appURL = bundle.bundleURL
        bundleIdentifier = bundle.bundleIdentifier
        currentVersion = appURL.pathExtension == "app" ? Self.version(of: bundle) : nil
    }

    /// False when the app cannot replace itself, as for a translocated copy or one in a folder the user cannot write.
    public var canInstall: Bool {
        let files = FileManager.default
        return files.isWritableFile(atPath: appURL.path) && files.isWritableFile(atPath: appURL.deletingLastPathComponent().path)
    }

    /// The latest release, if newer than the running app. Unauthenticated: GitHub allows 60 calls per hour per IP.
    public func newerRelease() async throws -> Release? {
        guard let current = currentVersion else { return nil }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let release = try Release.decode(try await Self.fetch(request))
        return release.version > current ? release : nil
    }

    /// Downloads and checks `release`, then swaps it in for the app on disk. The running process keeps
    /// the old code until it is relaunched.
    public func install(_ release: Release) async throws {
        let data = try await Self.fetch(URLRequest(url: release.download))
        try await Task.detached(priority: .userInitiated) { try installBlocking(release, data: data) }.value
    }

    private func installBlocking(_ release: Release, data: Data) throws {
        let files = FileManager.default
        // On the app's volume, so the final swap is a rename.
        let staging = try files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: appURL, create: true)
        defer { try? files.removeItem(at: staging) }

        if let expected = release.sha256 {
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expected.lowercased() else { throw UpdateError(String(localized: "Corrupted download: checksum mismatch")) }
        }
        let zip = staging.appendingPathComponent(Self.assetName)
        try data.write(to: zip)
        try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path])

        guard let app = try files.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
                  .first(where: { $0.pathExtension == "app" }),
              let downloaded = Bundle(url: app) else {
            throw UpdateError(String(localized: "The release zip does not contain the app"))
        }
        guard downloaded.bundleIdentifier == bundleIdentifier else {
            throw UpdateError(String(localized: "The release zip contains another app: \(downloaded.bundleIdentifier ?? "?")"))
        }
        // An app that still reports an older version would be offered again on every check.
        guard let version = Self.version(of: downloaded), version == release.version else {
            throw UpdateError(String(localized: "Release \(release.version.description) contains app version \(Self.version(of: downloaded)?.description ?? "?")"))
        }
        try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        _ = try files.replaceItemAt(appURL, withItemAt: app)
        // Finder caches by the bundle's date, which the zip keeps from the build.
        try? files.setAttributes([.modificationDate: Date()], ofItemAtPath: appURL.path)
        LSRegisterURL(appURL as CFURL, true)
    }

    private static func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw UpdateError(status == 404 ? String(localized: "No release published on GitHub") : String(localized: "GitHub responded \(status)"))
        }
        return data
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError(String(localized: "\((tool as NSString).lastPathComponent) failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"))
        }
    }

    private static func version(of bundle: Bundle) -> AppVersion? {
        (bundle.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }
}
