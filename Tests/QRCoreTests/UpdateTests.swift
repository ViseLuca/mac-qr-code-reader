import Foundation
import Testing
@testable import QRCore

@Suite struct UpdateTests {
    @Test func versionsCompareNumerically() throws {
        let v = { (s: String) in try #require(AppVersion(s)) }
        #expect(try v("1.0.10") > v("1.0.9"))
        #expect(try v("v1.2.0") > v("1.1.99"))
        #expect(try v("0.2.0") > v("0.1.0"))
        #expect(try v("1.0") == v("1.0.0"))
        #expect(try !(v("1.0") < v("1.0.0")))
        #expect(try v("v1.0.3").description == "1.0.3")
    }

    @Test func invalidVersionsAreRejected() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("1.0-beta") == nil)
        #expect(AppVersion("1..0") == nil)
    }

    @Test func decodesLatestRelease() throws {
        let json = """
        {"tag_name": "0.2.0", "html_url": "https://github.com/ViseLuca/mac-qr-code-reader/releases/tag/0.2.0",
         "assets": [
           {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt", "digest": null},
           {"name": "QRReader.zip",
            "browser_download_url": "https://github.com/ViseLuca/mac-qr-code-reader/releases/download/0.2.0/QRReader.zip",
            "digest": "sha256:8a348c050e2bc81770ba3a1fe85d750fd5b0c8756087ae4ec5518b295af2097f"}
         ]}
        """
        let release = try Release.decode(Data(json.utf8))
        #expect(release.version == AppVersion("0.2.0"))
        #expect(release.download == URL(string: "https://github.com/ViseLuca/mac-qr-code-reader/releases/download/0.2.0/QRReader.zip"))
        #expect(release.sha256 == "8a348c050e2bc81770ba3a1fe85d750fd5b0c8756087ae4ec5518b295af2097f")
    }

    @Test func releaseWithoutTheAppFails() {
        let json = #"{"tag_name": "0.2.0", "html_url": "https://github.com/x/y", "assets": []}"#
        #expect(throws: UpdateError.self) { try Release.decode(Data(json.utf8)) }
    }

    @Test func noVersionOutsideAppBundle() {
        // The test runner is not an .app, like `swift run`: nothing to update.
        #expect(Updater(bundle: .main).currentVersion == nil)
    }
}
