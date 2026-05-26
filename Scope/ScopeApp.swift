import SwiftUI
import AppKit

@main
struct ScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: ScopePanel!

    let audioCapture = SystemAudioCapture()
    let analyzer = AudioAnalyzer()
    let renderer = ScopeRenderer()
    let settings = ScopeSettings()
    let captureManager = CaptureManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        captureManager.renderer = renderer

        setupStatusItem()
        setupPanel()

        Task {
            await audioCapture.startCapture(analyzer: analyzer)
            showPanel()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MenubarIcon.make()
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func setupPanel() {
        let frame = NSRect(x: 0, y: 0, width: 420, height: 520)
        panel = ScopePanel(
            contentRect: frame,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.minSize = NSSize(width: 320, height: 400)
        panel.center()
        panel.onClose = { [weak self] in self?.hidePanel() }

        let hostingView = NSHostingView(
            rootView: ScopeWindowView(
                audioCapture: audioCapture,
                analyzer: analyzer,
                renderer: renderer,
                settings: settings,
                captureManager: captureManager,
                onClose: { [weak self] in self?.hidePanel() }
            )
        )
        panel.contentView = hostingView
    }

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Scope", action: #selector(quitApp), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.setActivationPolicy(.regular)
    }

    func hidePanel() {
        panel.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Borderless floating panel

class ScopePanel: NSPanel {
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }
}

// MARK: - Menubar Icon

enum MenubarIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 7
            let path = NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            path.lineWidth = 1.2
            NSColor.black.setStroke()
            path.stroke()

            let lissajous = NSBezierPath()
            let segments = 60
            let innerRadius = radius - 2.5
            for i in 0...segments {
                let t = Double(i) / Double(segments) * .pi * 2
                let x = center.x + CGFloat(sin(t * 3)) * innerRadius
                let y = center.y + CGFloat(cos(t * 2)) * innerRadius
                if i == 0 { lissajous.move(to: CGPoint(x: x, y: y)) }
                else { lissajous.line(to: CGPoint(x: x, y: y)) }
            }
            lissajous.lineWidth = 0.8
            lissajous.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
