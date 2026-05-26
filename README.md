# Scope XY-7

Real-time Lissajous oscilloscope for macOS system audio.

Captures system audio via ScreenCaptureKit and renders it as a live XY (Lissajous) or waveform display with CRT phosphor persistence, bloom glow, and vignette — all at 60fps in a borderless floating window.

No virtual audio drivers. No kernel extensions. Just plug in and play.

## Features

- **XY and Wave modes** — Lissajous figures or traditional waveform
- **Phosphor persistence** — adjustable trail decay, just like a real CRT
- **Bloom glow** — downscale/upscale compositing simulates CRT phosphor bleed
- **4 phosphor colors** — green, amber, white, orange
- **Light and dark mode**
- **PNG snapshots and MP4 recording**
- **Floating window** — borderless, always-on-top, draggable, resizable
- **Dynamic dock icon** — appears when window is open, hides when closed
- **Seamless permission flow** — auto-detects grant and relaunches

## Requirements

- macOS 14.0 or later
- Screen Recording permission (for system audio capture — no screen content is recorded)

## Build

1. Clone the repo
2. Open `Scope/Scope.xcodeproj` in Xcode
3. Set your signing team in **Signing & Capabilities** (free Apple ID works)
4. Build and run (`Cmd + R`)

> **Note:** Screen Recording permission is tied to the app's code signature. Using a stable signing team avoids re-granting permission after each build.

## How It Works

```
System Audio → ScreenCaptureKit → Ring Buffer → Core Graphics Renderer → CADisplayLink
```

- **Audio capture** runs on a high-priority GCD queue via `SCStream`
- **Ring buffer** (2048 samples, NSLock) stores snapshots read directly by the renderer — no main thread dispatch for audio data
- **Renderer** uses an offscreen `CGContext` for phosphor persistence (partial alpha fill each frame), with cached grid and vignette overlays
- **Display** is an `NSView` driven by `CADisplayLink` at 60fps

## Controls

| Control | Action |
|---------|--------|
| Left-click menubar icon | Toggle window |
| Right-click menubar icon | Quit |
| Space | Toggle XY / Wave mode |
| Scroll wheel | Adjust gain |
| PERSIST slider | Trail decay length |
| GAIN slider | Signal amplification |
| Color dots | Switch phosphor color |
| Sun/moon icon | Toggle light/dark mode |
| SNAP | Save PNG to Desktop |
| REC | Record MP4 to Desktop |

## Project Structure

```
Scope/
├── ScopeApp.swift                # App entry, menubar icon, floating panel, dock icon
├── AudioCapture/
│   ├── SystemAudioCapture.swift  # ScreenCaptureKit stream + permission handling
│   └── AudioAnalyzer.swift       # Ring buffer + signal detection
├── Renderer/
│   └── ScopeRenderer.swift       # Offscreen CG rendering, grid, vignette, bloom
├── Views/
│   ├── ScopeDisplayView.swift    # NSView + CADisplayLink, keyboard/scroll input
│   └── ScopeWindowView.swift     # SwiftUI window UI, controls, permission onboarding
├── Capture/
│   └── CaptureManager.swift      # PNG export + MP4 recording via AVAssetWriter
└── Info.plist
```

## Design

UI follows Teenage Engineering design language:
- 9px monospaced type with wide tracking
- `#FF6600` orange as the only accent color
- 1px borders, flat controls, no shadows
- The interface disappears — the visualization is the product

## License

MIT
