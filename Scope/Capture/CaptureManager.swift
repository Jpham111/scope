import Foundation
import AppKit
import AVFoundation
import Combine
import CoreVideo

@MainActor
class CaptureManager: ObservableObject {
    @Published var isRecording = false
    @Published var lastSaveMessage: String?

    weak var renderer: ScopeRenderer?

    private var recordingTimer: Timer?
    private var capturedFrames: [CGImage] = []

    // MARK: - Snapshot

    func snapshot() {
        guard let frame = renderer?.captureFrame() else { showMessage("NO FRAME"); return }
        guard let framed = addExportFrame(to: frame) else { showMessage("ERROR"); return }
        saveImage(framed)
        copyToPasteboard(framed)
        showMessage("SAVED")
    }

    // MARK: - Recording

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        capturedFrames = []

        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let frame = self.renderer?.captureFrame() {
                    self.capturedFrames.append(frame)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.finishRecording()
        }
    }

    func stopRecording() {
        finishRecording()
    }

    private func finishRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false

        let frames = capturedFrames
        capturedFrames = []
        guard !frames.isEmpty else { showMessage("ERROR"); return }

        Task { await self.writeVideo(frames: frames) }
    }

    // MARK: - Video writing

    private func writeVideo(frames: [CGImage]) async {
        let ts = isoTimestamp()
        let url = desktopURL(name: "scope-xy7-\(ts).mp4")
        let first = frames[0]
        let w = first.width
        let h = first.height

        guard let writer = try? AVAssetWriter(url: url, fileType: .mp4) else {
            showMessage("ERROR"); return
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let bufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: bufferAttrs)

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for (idx, frame) in frames.enumerated() {
            let framed = addExportFrame(to: frame) ?? frame
            guard let pixelBuffer = makePixelBuffer(from: framed, pool: adaptor.pixelBufferPool) else { continue }
            let time = CMTime(value: CMTimeValue(idx), timescale: 30)
            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            adaptor.append(pixelBuffer, withPresentationTime: time)
        }

        input.markAsFinished()
        await writer.finishWriting()
        showMessage(writer.status == .completed ? "SAVED" : "ERROR")
    }

    // MARK: - Helpers

    private func addExportFrame(to image: CGImage) -> CGImage? {
        let padding: CGFloat = 8
        let w = CGFloat(image.width) + padding * 2
        let h = CGFloat(image.height) + padding * 2

        guard let ctx = CGContext(
            data: nil, width: Int(w), height: Int(h),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: padding, y: padding, width: CGFloat(image.width), height: CGFloat(image.height)))

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: NSColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        ]
        let watermark = NSAttributedString(string: "SCOPE XY-7", attributes: attrs)
        let wSize = watermark.size()
        let wRect = CGRect(x: w - wSize.width - padding, y: padding, width: wSize.width, height: wSize.height)
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        watermark.draw(in: wRect)
        NSGraphicsContext.restoreGraphicsState()

        return ctx.makeImage()
    }

    private func makePixelBuffer(from image: CGImage, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        } else {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: image.width,
                kCVPixelBufferHeightKey as String: image.height
            ]
            CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32ARGB, attrs as CFDictionary, &buffer)
        }
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: image.width, height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }

    private func saveImage(_ image: CGImage) {
        let url = desktopURL(name: "scope-xy7-\(isoTimestamp()).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    private func copyToPasteboard(_ image: CGImage) {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
    }

    private func desktopURL(name: String) -> URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
    }

    private func isoTimestamp() -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return fmt.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }

    private func showMessage(_ msg: String) {
        lastSaveMessage = msg
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if lastSaveMessage == msg { lastSaveMessage = nil }
        }
    }
}
