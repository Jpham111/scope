# Scope XY-7

Real-time Lissajous oscilloscope for macOS system audio.

Captures system audio via ScreenCaptureKit and renders it as a live XY (Lissajous) or waveform display with CRT phosphor persistence, bloom glow, and vignette — all at 60fps in a borderless floating window.

No virtual audio drivers. No kernel extensions. Just plug in and play.

> **[Download v1.0.0 →](https://github.com/Jpham111/scope/releases/latest)**

---

## Why I Built This

I'm a music nerd. I love records, I love good speakers, and I love the obsessive little rituals around listening to music well.

Somewhere along the way I started noticing people who paired their vinyl setups with vintage oscilloscopes — sitting next to the turntable, glowing green, drawing real-time Lissajous figures from the audio signal. It's a beautiful, useless detail. The trace doesn't make the music sound better. It just makes it feel like more is happening. Like the music is *visible*.

I wanted that on my desk. But I didn't want to buy a CRT, find a stereo signal splitter, run cables across the room, and dedicate physical space to a thing I'd use casually.

So I built the digital version: a real oscilloscope that lives on your desktop, taps directly into your system audio, and gives you the same hypnotic phosphor trace while you work, code, or just listen. Borderless floating window, always-on-top, four phosphor colors, light and dark mode — the kind of thing you set up once and then forget is even running until someone walks by and asks what it is.

It's meant to be a fun, slightly indulgent way to visualize music while you work. Nothing more. Sometimes that's enough.

---

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
- Apple Silicon or Intel
- Screen Recording permission (for system audio capture — no screen content is recorded)

## Install

**Easy way — for everyone:**

1. [Download the latest DMG](https://github.com/Jpham111/scope/releases/latest)
2. Open the DMG and drag **Scope** to **Applications**
3. Launch Scope and grant Screen Recording permission when prompted
4. The app auto-detects the grant and relaunches — you're ready

Signed with a Developer ID certificate and notarized by Apple. No Gatekeeper warnings, no terminal commands.

**Build from source:**

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
