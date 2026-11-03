import CoreImage
import CoreImage.CIFilterBuiltins
import Testing
@testable import QRCore

/// Renders `text` as a QR code on a white canvas with a generous quiet zone.
func makeQRImage(_ text: String, scale: CGFloat = 8, margin: CGFloat = 40) -> CGImage {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    let code = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let canvas = code.extent.insetBy(dx: -margin, dy: -margin)
    let image = code
        .transformed(by: CGAffineTransform(translationX: margin, y: margin))
        .composited(over: CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: canvas.size)))
    return CIContext().createCGImage(image, from: CGRect(origin: .zero, size: canvas.size))!
}

@Suite struct QRDecoderTests {
    @Test func roundTripText() {
        #expect(QRDecoder.decode(cgImage: makeQRImage("ciao dal mac")) == ["ciao dal mac"])
    }

    @Test func roundTripWifi() {
        let raw = "WIFI:T:WPA;S:Casa;P:pass word!;;"
        let decoded = QRDecoder.decode(cgImage: makeQRImage(raw))
        #expect(decoded == [raw])
        #expect(decoded.first.map(QRPayload.parse) == .wifi(WifiCredentials(ssid: "Casa", password: "pass word!", security: .wpa, hidden: false)))
    }

    @Test func blankImageHasNoCodes() {
        let blank = CIContext().createCGImage(
            CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200)),
            from: CGRect(x: 0, y: 0, width: 200, height: 200)
        )!
        #expect(QRDecoder.decode(cgImage: blank).isEmpty)
    }
}
