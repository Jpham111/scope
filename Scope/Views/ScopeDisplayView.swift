import AppKit
import SwiftUI

class ScopeNSView: NSView {
    var renderer: ScopeRenderer
    var analyzer: AudioAnalyzer
    var settings: ScopeSettings

    private var displayLink: CADisplayLink?

    override var isFlipped: Bool { true }

    init(renderer: ScopeRenderer, analyzer: AudioAnalyzer, settings: ScopeSettings) {
        self.renderer = renderer
        self.analyzer = analyzer
        self.settings = settings
        super.init(frame: .zero)
        wantsLayer = true
        updateBackgroundColor()
        setupDisplayLink()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        displayLink?.invalidate()
    }

    private func setupDisplayLink() {
        let link = self.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func updateBackgroundColor() {
        let v: CGFloat = settings.lightMode ? 0.96 : 0.04
        layer?.backgroundColor = NSColor(red: v, green: v, blue: v, alpha: 1).cgColor
    }

    @objc private func tick() {
        updateBackgroundColor()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        renderer.renderFromBuffer(in: ctx, size: bounds.size, settings: settings, ringBuffer: analyzer.ringBuffer)
    }

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        settings.gain = (settings.gain - delta * 0.01).clamped(to: 0.5...4.0)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: // Space — toggle XY/Wave
            settings.mode = settings.mode == .xy ? .wave : .xy
        default:
            super.keyDown(with: event)
        }
    }
}

struct ScopeDisplayView: NSViewRepresentable {
    var renderer: ScopeRenderer
    var analyzer: AudioAnalyzer
    var settings: ScopeSettings

    func makeNSView(context: Context) -> ScopeNSView {
        ScopeNSView(renderer: renderer, analyzer: analyzer, settings: settings)
    }

    func updateNSView(_ nsView: ScopeNSView, context: Context) {}
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
