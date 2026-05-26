import Foundation
import Accelerate
import Combine

final class AudioRingBuffer: @unchecked Sendable {
    private let bufferSize = 2048
    private var leftBuffer: [Float]
    private var rightBuffer: [Float]
    private var writeIndex = 0
    private let lock = NSLock()

    // Latest snapshot — read by renderer directly, no main thread hop
    private(set) var snapshotLeft:  [Float]
    private(set) var snapshotRight: [Float]
    private(set) var rms: Float = 0

    init() {
        leftBuffer  = Array(repeating: 0, count: 2048)
        rightBuffer = Array(repeating: 0, count: 2048)
        snapshotLeft  = Array(repeating: 0, count: 2048)
        snapshotRight = Array(repeating: 0, count: 2048)
    }

    func write(interleavedSamples: [Float], channelCount: Int) {
        lock.lock()
        let frameCount = interleavedSamples.count / max(channelCount, 1)
        for frame in 0..<frameCount {
            leftBuffer[writeIndex] = interleavedSamples[frame * channelCount]
            rightBuffer[writeIndex] = channelCount > 1
                ? interleavedSamples[frame * channelCount + 1]
                : interleavedSamples[frame * channelCount]
            writeIndex = (writeIndex + 1) % bufferSize
        }
        let wi = writeIndex
        snapshotLeft  = Array(leftBuffer[wi...])  + Array(leftBuffer[..<wi])
        snapshotRight = Array(rightBuffer[wi...]) + Array(rightBuffer[..<wi])
        lock.unlock()

        var r: Float = 0
        vDSP_rmsqv(snapshotLeft, 1, &r, vDSP_Length(bufferSize))
        rms = r
    }
}

@MainActor
class AudioAnalyzer: ObservableObject {
    @Published var hasSignal: Bool = false

    nonisolated let ringBuffer = AudioRingBuffer()

    nonisolated func process(interleavedSamples: [Float], channelCount: Int) {
        ringBuffer.write(interleavedSamples: interleavedSamples, channelCount: channelCount)
        let detected = ringBuffer.rms > 0.001
        Task { @MainActor in
            if self.hasSignal != detected { self.hasSignal = detected }
        }
    }
}
