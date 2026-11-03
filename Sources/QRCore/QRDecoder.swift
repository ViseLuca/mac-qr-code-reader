import CoreGraphics
import CoreVideo
import Vision

/// Decodes QR (and a few other 2D) codes from images using Vision.
public enum QRDecoder {
    static let symbologies: [VNBarcodeSymbology] = [.qr, .microQR, .aztec, .dataMatrix]

    /// Returns the unique payload strings found in the image, in detection order.
    public static func decode(cgImage: CGImage) -> [String] {
        run(VNImageRequestHandler(cgImage: cgImage, options: [:]))
    }

    /// Returns the unique payload strings found in a camera frame, in detection order.
    public static func decode(pixelBuffer: CVPixelBuffer) -> [String] {
        run(VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:]))
    }

    private static func run(_ handler: VNImageRequestHandler) -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = symbologies
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        var seen = Set<String>()
        return (request.results ?? []).compactMap(\.payloadStringValue).filter { seen.insert($0).inserted }
    }
}
