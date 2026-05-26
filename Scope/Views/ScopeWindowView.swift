import SwiftUI

// MARK: - Color constants

private let teOrange  = Color(red: 1.0, green: 0.4, blue: 0)
private let teBg      = Color(red: 0.04, green: 0.04, blue: 0.04)
private let teBorder  = Color(red: 0.1, green: 0.1, blue: 0.1)
private let teMuted   = Color(red: 0.4, green: 0.4, blue: 0.4)
private let teBright  = Color(red: 0.6, green: 0.6, blue: 0.6)

// MARK: - Shared typography modifier

private struct TEFont: ViewModifier {
    var tracking: CGFloat = 1.2
    func body(content: Content) -> some View {
        content
            .font(.system(size: 9, weight: .regular, design: .monospaced))
            .tracking(tracking)
    }
}

extension View {
    fileprivate func teFont(_ tracking: CGFloat = 1.2) -> some View {
        modifier(TEFont(tracking: tracking))
    }
}

// MARK: - Main window view

struct ScopeWindowView: View {
    @ObservedObject var audioCapture: SystemAudioCapture
    @ObservedObject var analyzer: AudioAnalyzer
    var renderer: ScopeRenderer
    @ObservedObject var settings: ScopeSettings
    @ObservedObject var captureManager: CaptureManager
    var onClose: () -> Void

    private var bg: Color {
        settings.lightMode
            ? Color(red: 0.96, green: 0.96, blue: 0.96)
            : teBg
    }

    private var border: Color {
        settings.lightMode
            ? Color(red: 0.85, green: 0.85, blue: 0.85)
            : teBorder
    }

    private var muted: Color {
        settings.lightMode
            ? Color(red: 0.5, green: 0.5, blue: 0.5)
            : teMuted
    }

    private var bright: Color {
        settings.lightMode
            ? Color(red: 0.2, green: 0.2, blue: 0.2)
            : teBright
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().background(border)
            scopeArea
            Divider().background(border)
            controlBar
        }
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(border, lineWidth: 1)
        )
    }

    // MARK: Title bar

    private var titleBar: some View {
        HStack(spacing: 0) {
            Button {
                onClose()
            } label: {
                Circle()
                    .fill(Color(red: 1.0, green: 0.3, blue: 0.25))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(Color(red: 0.4, green: 0.0, blue: 0.0))
                    )
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)

            Spacer()

            Text("SCOPE XY-7")
                .teFont()
                .foregroundColor(muted)

            Spacer()

            statusText
            lightModeToggle
                .padding(.trailing, 10)
        }
        .frame(height: 32)
    }

    private var lightModeToggle: some View {
        Button {
            settings.lightMode.toggle()
        } label: {
            Image(systemName: settings.lightMode ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 10))
                .foregroundColor(muted)
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
    }

    @ViewBuilder
    private var statusText: some View {
        if let msg = captureManager.lastSaveMessage {
            Text(msg)
                .teFont(0.8)
                .foregroundColor(teOrange)
        } else if !audioCapture.permissionGranted {
            Text("NO PERMISSION")
                .teFont(0.8)
                .foregroundColor(muted)
        } else if let err = audioCapture.errorMessage {
            Text(err.uppercased())
                .teFont(0.8)
                .foregroundColor(muted)
        } else if audioCapture.isCapturing {
            Text("44.1KHZ · 2CH")
                .teFont(0.8)
                .foregroundColor(bright)
        } else {
            Text("NO CAPTURE")
                .teFont(0.8)
                .foregroundColor(muted)
        }
    }

    // MARK: Scope area

    private var scopeArea: some View {
        Group {
            if !audioCapture.permissionGranted {
                permissionView
            } else {
                ScopeDisplayView(renderer: renderer, analyzer: analyzer, settings: settings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg)
    }

    private var permissionView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform.circle")
                .font(.system(size: 32, weight: .thin))
                .foregroundColor(teOrange)

            Text("AUDIO ACCESS REQUIRED")
                .teFont(1.0)
                .foregroundColor(muted)

            Text("SCOPE USES SCREEN RECORDING TO\nCAPTURE SYSTEM AUDIO. NO SCREEN\nCONTENT IS EVER RECORDED.")
                .teFont(0.8)
                .foregroundColor(muted.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            if audioCapture.needsRelaunch {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text("RESTARTING...")
                        .teFont(0.8)
                        .foregroundColor(teOrange)
                }
            } else {
                VStack(spacing: 10) {
                    Button("GRANT ACCESS") {
                        audioCapture.requestPermission()
                    }
                    .buttonStyle(.plain)
                    .teFont(1.0)
                    .foregroundColor(teOrange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(teOrange, lineWidth: 1))

                    Button("OPEN SYSTEM SETTINGS") {
                        audioCapture.openPermissionSettings()
                    }
                    .buttonStyle(.plain)
                    .teFont(0.8)
                    .foregroundColor(muted)
                }
            }

            Text("SCOPE WILL RESTART AUTOMATICALLY\nAFTER YOU GRANT PERMISSION.")
                .teFont(0.6)
                .foregroundColor(muted.opacity(0.4))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Spacer()

            Button("QUIT SCOPE") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .teFont(0.8)
            .foregroundColor(muted.opacity(0.5))
            .padding(.bottom, 12)
        }
        .padding(.horizontal)
    }

    // MARK: Control bar

    private var controlBar: some View {
        VStack(spacing: 0) {
            persistenceSlider
            gainSlider
            Divider().background(border)
            HStack(spacing: 8) {
                modeToggle
                Spacer()
                colorDots
                signalLED
                Spacer()
                snapButton
                recButton
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
        }
    }

    private var persistenceSlider: some View {
        HStack(spacing: 8) {
            Text("PERSIST")
                .teFont(0.8)
                .foregroundColor(muted)
                .frame(width: 42, alignment: .leading)
            Slider(value: $settings.persistence, in: 0.05...0.95)
                .accentColor(teOrange)
                .frame(maxWidth: .infinity)
            Text("\(Int(settings.persistence * 100))%")
                .teFont(0.8)
                .foregroundColor(bright)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
    }

    private var gainSlider: some View {
        HStack(spacing: 8) {
            Text("GAIN")
                .teFont(0.8)
                .foregroundColor(muted)
                .frame(width: 42, alignment: .leading)
            Slider(value: $settings.gain, in: 0.5...4.0)
                .accentColor(teOrange)
                .frame(maxWidth: .infinity)
            Text(String(format: "%.1fx", settings.gain))
                .teFont(0.8)
                .foregroundColor(bright)
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
    }

    private var modeToggle: some View {
        HStack(spacing: 4) {
            ForEach(DisplayMode.allCases, id: \.self) { mode in
                let isActive = settings.mode == mode
                Button(mode.rawValue) { settings.mode = mode }
                    .buttonStyle(.plain)
                    .teFont(0.8)
                    .foregroundColor(isActive ? teOrange : muted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(isActive ? teOrange : border, lineWidth: 1)
                    )
            }
        }
    }

    private var colorDots: some View {
        HStack(spacing: 6) {
            ForEach(PhosphorColor.allCases, id: \.self) { color in
                let isActive = settings.phosphor == color
                Button { settings.phosphor = color } label: {
                    Circle()
                        .fill(isActive ? dotColor(color) : Color.clear)
                        .overlay(
                            Circle().stroke(
                                isActive ? dotColor(color) : Color(red: 0.3, green: 0.3, blue: 0.3),
                                lineWidth: 1
                            )
                        )
                        .frame(width: 10, height: 10)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dotColor(_ color: PhosphorColor) -> Color {
        switch color {
        case .green:  return Color(red: 0, green: 1.0, blue: 0.39)
        case .amber:  return Color(red: 1.0, green: 0.67, blue: 0)
        case .white:  return Color(red: 0.88, green: 0.88, blue: 0.88)
        case .orange: return Color(red: 1.0, green: 0.4, blue: 0)
        }
    }

    private var signalLED: some View {
        Circle()
            .fill(analyzer.hasSignal
                  ? Color(red: 0.2, green: 1.0, blue: 0.3)
                  : Color(red: 0.1, green: 0.2, blue: 0.1))
            .frame(width: 6, height: 6)
    }

    private var snapButton: some View {
        Button { captureManager.snapshot() } label: {
            HStack(spacing: 3) {
                Image(systemName: "square").font(.system(size: 8))
                Text("SNAP").teFont(0.8)
            }
            .foregroundColor(muted)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(border, lineWidth: 1))
    }

    private var recButton: some View {
        let recording = captureManager.isRecording
        return Button {
            if recording { captureManager.stopRecording() }
            else { captureManager.startRecording() }
        } label: {
            HStack(spacing: 3) {
                Circle()
                    .fill(recording ? teOrange : Color(red: 0.8, green: 0.1, blue: 0.1))
                    .frame(width: 6, height: 6)
                Text("REC")
                    .teFont(0.8)
                    .foregroundColor(recording ? teOrange : muted)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(recording ? teOrange : border, lineWidth: 1)
        )
    }
}
