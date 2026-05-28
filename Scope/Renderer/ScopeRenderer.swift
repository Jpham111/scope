import AppKit
import Combine
import CoreGraphics

enum DisplayMode: String, CaseIterable {
    case xy = "XY"
    case wave = "WAVE"
}

enum PhosphorColor: String, CaseIterable {
    case green, amber, white, orange

    var primary: NSColor {
        switch self {
        case .green:  return NSColor(red: 0, green: 1.0, blue: 0.39, alpha: 1)
        case .amber:  return NSColor(red: 1.0, green: 0.67, blue: 0, alpha: 1)
        case .white:  return NSColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1)
        case .orange: return NSColor(red: 1.0, green: 0.4, blue: 0, alpha: 1)
        }
    }

    var grid: NSColor { primary.withAlphaComponent(0.06) }
    var gridCenter: NSColor { primary.withAlphaComponent(0.12) }
}

class ScopeSettings: ObservableObject {
    @Published var mode: DisplayMode = .xy {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "scope.mode") }
    }
    @Published var phosphor: PhosphorColor = .green {
        didSet { UserDefaults.standard.set(phosphor.rawValue, forKey: "scope.phosphor") }
    }
    @Published var persistence: CGFloat = 0.45 {
        didSet { UserDefaults.standard.set(Double(persistence), forKey: "scope.persistence") }
    }
    @Published var gain: CGFloat = 2.0 {
        didSet { UserDefaults.standard.set(Double(gain), forKey: "scope.gain") }
    }
    @Published var glowIntensity: CGFloat = 0.2
    @Published var lightMode: Bool = false {
        didSet { UserDefaults.standard.set(lightMode, forKey: "scope.lightMode") }
    }

    var bgR: CGFloat { lightMode ? 1.0 : 0.0 }
    var bgG: CGFloat { lightMode ? 1.0 : 0.0 }
    var bgB: CGFloat { lightMode ? 1.0 : 0.0 }

    init() {
        let d = UserDefaults.standard
        if let m = d.string(forKey: "scope.mode"), let mode = DisplayMode(rawValue: m) {
            self.mode = mode
        }
        if let p = d.string(forKey: "scope.phosphor"), let phosphor = PhosphorColor(rawValue: p) {
            self.phosphor = phosphor
        }
        if d.object(forKey: "scope.persistence") != nil {
            self.persistence = CGFloat(d.double(forKey: "scope.persistence"))
        }
        if d.object(forKey: "scope.gain") != nil {
            self.gain = CGFloat(d.double(forKey: "scope.gain"))
        }
        if d.object(forKey: "scope.lightMode") != nil {
            self.lightMode = d.bool(forKey: "scope.lightMode")
        }
    }
}

class ScopeRenderer {
    private var persistenceBuffer: CGContext?
    private var glowBuffer: CGContext?
    private var bufferSize: CGSize = .zero
    private var gridImage: CGImage?
    private var gridSize: CGSize = .zero
    private var gridPhosphor: PhosphorColor?
    private var gridMode: DisplayMode?
    private var vignetteImage: CGImage?
    private var vignetteSize: CGSize = .zero
    private var vignetteLightMode: Bool?
    private var gridLightMode: Bool?
    private var bufferLightMode: Bool?

    func renderFromBuffer(in ctx: CGContext, size: CGSize, settings: ScopeSettings, ringBuffer: AudioRingBuffer) {
        let left = ringBuffer.snapshotLeft
        let right = ringBuffer.snapshotRight
        render(in: ctx, size: size, settings: settings, leftChannel: left, rightChannel: right)
    }

    func render(in ctx: CGContext, size: CGSize, settings: ScopeSettings, leftChannel: [Float], rightChannel: [Float]) {
        ensureBuffer(size: size, settings: settings)
        guard let buffer = persistenceBuffer else { return }

        fadeBuffer(buffer: buffer, settings: settings)
        drawTrace(in: buffer, size: size, settings: settings, left: leftChannel, right: rightChannel)

        // Bloom: draw a downscaled/upscaled copy underneath for soft glow
        if let traceImage = buffer.makeImage() {
            drawGlow(in: ctx, size: size, traceImage: traceImage, settings: settings)
            ctx.draw(traceImage, in: CGRect(origin: .zero, size: size))
        }

        let grid = cachedGrid(size: size, settings: settings)
        ctx.draw(grid, in: CGRect(origin: .zero, size: size))

        let vignette = cachedVignette(size: size, settings: settings)
        ctx.draw(vignette, in: CGRect(origin: .zero, size: size))
    }

    func captureFrame() -> CGImage? {
        persistenceBuffer?.makeImage()
    }

    // MARK: - Bloom via downscale/upscale

    private func drawGlow(in ctx: CGContext, size: CGSize, traceImage: CGImage, settings: ScopeSettings) {
        let scale: CGFloat = 0.25
        let glowW = max(1, Int(size.width * scale))
        let glowH = max(1, Int(size.height * scale))

        if glowBuffer == nil || Int(bufferSize.width * scale) != glowW {
            glowBuffer = CGContext(
                data: nil, width: glowW, height: glowH,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            glowBuffer?.interpolationQuality = .low
        }

        guard let glow = glowBuffer else { return }
        glow.clear(CGRect(x: 0, y: 0, width: glowW, height: glowH))
        glow.draw(traceImage, in: CGRect(x: 0, y: 0, width: glowW, height: glowH))

        if let blurred = glow.makeImage() {
            ctx.saveGState()
            ctx.setAlpha(0.6)
            ctx.interpolationQuality = .low
            ctx.draw(blurred, in: CGRect(origin: .zero, size: size))
            ctx.restoreGState()
        }
    }

    // MARK: - Buffer management

    private func ensureBuffer(size: CGSize, settings: ScopeSettings) {
        guard size.width > 0 && size.height > 0 else { return }
        if persistenceBuffer == nil || bufferSize != size || bufferLightMode != settings.lightMode {
            persistenceBuffer = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            bufferSize = size
            bufferLightMode = settings.lightMode
            persistenceBuffer?.setFillColor(CGColor(red: settings.bgR, green: settings.bgG, blue: settings.bgB, alpha: 1))
            persistenceBuffer?.fill(CGRect(origin: .zero, size: size))
            glowBuffer = nil
        }
    }

    private func fadeBuffer(buffer: CGContext, settings: ScopeSettings) {
        let fadeAlpha = 1.0 - settings.persistence
        buffer.setFillColor(CGColor(red: settings.bgR, green: settings.bgG, blue: settings.bgB, alpha: fadeAlpha))
        buffer.fill(CGRect(origin: .zero, size: bufferSize))
    }

    // MARK: - Cached grid

    private func cachedGrid(size: CGSize, settings: ScopeSettings) -> CGImage {
        if let img = gridImage, gridSize == size, gridPhosphor == settings.phosphor, gridMode == settings.mode, gridLightMode == settings.lightMode {
            return img
        }
        let img = buildGrid(size: size, settings: settings)
        gridImage = img
        gridSize = size
        gridPhosphor = settings.phosphor
        gridMode = settings.mode
        gridLightMode = settings.lightMode
        return img
    }

    private func buildGrid(size: CGSize, settings: ScopeSettings) -> CGImage {
        let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        let divisions: CGFloat = 8
        let stepX = size.width / divisions
        let stepY = size.height / divisions

        let light = settings.lightMode
        let gridAlpha: CGFloat = light ? 0.15 : 0.08
        let centerAlpha: CGFloat = light ? 0.3 : 0.15

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if light {
            ctx.setStrokeColor(CGColor(red: 0.7, green: 0.7, blue: 0.7, alpha: gridAlpha))
        } else {
            settings.phosphor.grid.getRed(&r, green: &g, blue: &b, alpha: &a)
            ctx.setStrokeColor(CGColor(red: r, green: g, blue: b, alpha: gridAlpha))
        }
        ctx.setLineWidth(0.5)

        for i in 0...Int(divisions) {
            let x = CGFloat(i) * stepX
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: size.height))
            let y = CGFloat(i) * stepY
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: size.width, y: y))
        }
        ctx.strokePath()

        if light {
            ctx.setStrokeColor(CGColor(red: 0.6, green: 0.6, blue: 0.6, alpha: centerAlpha))
        } else {
            settings.phosphor.gridCenter.getRed(&r, green: &g, blue: &b, alpha: &a)
            ctx.setStrokeColor(CGColor(red: r, green: g, blue: b, alpha: centerAlpha))
        }
        let cx = size.width / 2, cy = size.height / 2
        ctx.move(to: CGPoint(x: cx, y: 0))
        ctx.addLine(to: CGPoint(x: cx, y: size.height))
        ctx.move(to: CGPoint(x: 0, y: cy))
        ctx.addLine(to: CGPoint(x: size.width, y: cy))
        ctx.strokePath()

        if settings.mode == .xy {
            ctx.setStrokeColor(CGColor(red: r, green: g, blue: b, alpha: 0.05))
            ctx.setLineDash(phase: 0, lengths: [2, 5])
            ctx.move(to: CGPoint(x: 0, y: 0))
            ctx.addLine(to: CGPoint(x: size.width, y: size.height))
            ctx.move(to: CGPoint(x: size.width, y: 0))
            ctx.addLine(to: CGPoint(x: 0, y: size.height))
            ctx.strokePath()
        }

        return ctx.makeImage()!
    }

    // MARK: - Cached vignette

    private func cachedVignette(size: CGSize, settings: ScopeSettings) -> CGImage {
        if let img = vignetteImage, vignetteSize == size, vignetteLightMode == settings.lightMode { return img }
        let ctx = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(size.width, size.height) / 2
        let v: CGFloat = settings.lightMode ? 0.85 : 0.0
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: v, green: v, blue: v, alpha: 0),
                CGColor(red: v, green: v, blue: v, alpha: settings.lightMode ? 0.3 : 0.5)
            ] as CFArray,
            locations: [0.5, 1.0]
        )!
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: .drawsAfterEndLocation)
        let img = ctx.makeImage()!
        vignetteImage = img
        vignetteSize = size
        vignetteLightMode = settings.lightMode
        return img
    }

    // MARK: - Trace drawing

    private func drawTrace(in buffer: CGContext, size: CGSize, settings: ScopeSettings, left: [Float], right: [Float]) {
        let sampleCount = min(left.count, right.count)
        guard sampleCount > 1 else { return }

        let cx = size.width / 2
        let cy = size.height / 2
        let scale = min(size.width, size.height) / 2 * settings.gain

        let stride = max(1, sampleCount / 512)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        settings.phosphor.primary.getRed(&r, green: &g, blue: &b, alpha: &a)

        let path = CGMutablePath()

        switch settings.mode {
        case .xy:
            path.move(to: CGPoint(x: cx + CGFloat(left[0]) * scale, y: cy - CGFloat(right[0]) * scale))
            for i in Swift.stride(from: stride, to: sampleCount, by: stride) {
                path.addLine(to: CGPoint(x: cx + CGFloat(left[i]) * scale, y: cy - CGFloat(right[i]) * scale))
            }
        case .wave:
            path.move(to: CGPoint(x: 0, y: cy - CGFloat(left[0]) * scale * 0.7))
            for i in Swift.stride(from: stride, to: sampleCount, by: stride) {
                let x = CGFloat(i) / CGFloat(sampleCount) * size.width
                path.addLine(to: CGPoint(x: x, y: cy - CGFloat(left[i]) * scale * 0.7))
            }
        }

        buffer.setLineDash(phase: 0, lengths: [])
        buffer.setLineJoin(.round)
        buffer.setLineCap(.round)

        // Outer glow stroke — wider, dimmer
        buffer.setStrokeColor(CGColor(red: r, green: g, blue: b, alpha: 0.25))
        buffer.setLineWidth(4.0)
        buffer.addPath(path)
        buffer.strokePath()

        // Core stroke — bright and sharp
        buffer.setStrokeColor(CGColor(red: r, green: g, blue: b, alpha: 1.0))
        buffer.setLineWidth(1.5)
        buffer.addPath(path)
        buffer.strokePath()
    }
}
