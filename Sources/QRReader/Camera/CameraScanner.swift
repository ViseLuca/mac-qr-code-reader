import AVFoundation
import QRCore

enum CameraError: LocalizedError {
    case denied
    case noDevice

    var errorDescription: String? {
        switch self {
        case .denied: "Accesso alla fotocamera negato."
        case .noDevice: "Nessuna fotocamera disponibile."
        }
    }
}

/// Runs an AVCaptureSession and decodes frames at ~5 fps on a background queue.
final class CameraScanner: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    var onDetect: (@MainActor ([String]) -> Void)?

    private let queue = DispatchQueue(label: "qrreader.camera")
    private var lastDecode = Date.distantPast // accessed only on `queue`
    private var configured = false

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    func configure() throws {
        guard !configured else { return }
        guard let device = AVCaptureDevice.default(for: .video) else { throw CameraError.noDevice }
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        configured = true
    }

    func start() {
        queue.async { [session] in session.startRunning() }
    }

    func stop() {
        queue.async { [session] in session.stopRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastDecode) >= 0.2, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastDecode = now
        let raws = QRDecoder.decode(pixelBuffer: pixelBuffer)
        guard !raws.isEmpty else { return }
        Task { @MainActor [weak self] in self?.onDetect?(raws) }
    }
}
