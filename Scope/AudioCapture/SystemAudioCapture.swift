import Foundation
import ScreenCaptureKit
import Combine

@MainActor
class SystemAudioCapture: NSObject, ObservableObject {
    @Published var isCapturing = false
    @Published var permissionGranted = true
    @Published var needsRelaunch = false
    @Published var errorMessage: String?

    private var stream: SCStream?
    private weak var analyzer: AudioAnalyzer?
    nonisolated let analyzerBox = AnalyzerBox()

    private var permissionPollTimer: Timer?

    func startCapture(analyzer: AudioAnalyzer) async {
        self.analyzer = analyzer
        analyzerBox.ref = analyzer

        if !CGPreflightScreenCaptureAccess() {
            permissionGranted = false
            return
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else {
                errorMessage = "NO DISPLAY"
                return
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])

            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.channelCount = 2
            config.sampleRate = 44100
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            config.showsCursor = false

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
            try await stream.startCapture()

            self.stream = stream
            isCapturing = true
            permissionGranted = true
        } catch {
            let msg = error.localizedDescription.lowercased()
            if msg.contains("permission") || msg.contains("denied") || msg.contains("declined") || msg.contains("not authorized") {
                permissionGranted = false
            } else {
                errorMessage = "ERR: \(error.localizedDescription.prefix(30))"
            }
        }
    }

    func stopCapture() async {
        try? await stream?.stopCapture()
        stream = nil
        isCapturing = false
    }

    func requestPermission() {
        CGRequestScreenCaptureAccess()
        startPermissionPolling()
    }

    func startPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if CGPreflightScreenCaptureAccess() {
                    self.permissionPollTimer?.invalidate()
                    self.permissionPollTimer = nil
                    self.needsRelaunch = true
                    self.relaunchApp()
                }
            }
        }
    }

    func relaunchApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.terminate(nil)
            }
        }
    }

    func retryCapture() {
        Task {
            if let analyzer { await startCapture(analyzer: analyzer) }
        }
    }

    func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        startPermissionPolling()
    }
}

final class AnalyzerBox: @unchecked Sendable {
    weak var ref: AudioAnalyzer?
}

extension SystemAudioCapture: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              sampleBuffer.isValid,
              let blockBuffer = sampleBuffer.dataBuffer,
              let formatDesc = sampleBuffer.formatDescription else { return }

        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }
        let channelCount = Int(asbd.pointee.mChannelsPerFrame)

        var dataPointer: UnsafeMutablePointer<Int8>?
        var totalLength = 0
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let pointer = dataPointer else { return }

        let sampleCount = totalLength / MemoryLayout<Float>.size / max(channelCount, 1)
        let samples = pointer.withMemoryRebound(to: Float.self, capacity: sampleCount * channelCount) {
            Array(UnsafeBufferPointer(start: $0, count: sampleCount * channelCount))
        }

        analyzerBox.ref?.process(interleavedSamples: samples, channelCount: channelCount)
    }
}
