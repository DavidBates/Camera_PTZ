# Validation — version 1.1, 2026-09-17

- Xcode 27.0, macOS SDK 27.0, deployment target macOS 14; native arm64 Debug build succeeded.
- 30 protocol/descriptor/zoom-stop checks passed, zero failures. Tests cover experimental preset save/recall payloads, zoom rounding, clamping, endpoints and stop spacing using a fake USB transport.
- Camera preview and USB control use separate serial queues. Preview uses video only and releases the input on pause.
- Embedded permissions: App Sandbox, USB and Camera. No microphone permission, third-party runtime, Intel dependency or Rosetta.
- Earlier physical testing verified descriptor discovery, zoom SET/readback (180 → 181 → 180), successful Logitech pan transfers and STOP. The user confirmed physical movement.
- Actual device: 046d:0848, VideoControl interface 0, terminal 1, Logitech peripheral extension unit 11. Zoom range 100–1000, resolution 1. Relative movement speed is fixed at 1; absolute pan/tilt is not advertised.
- Version 1.1 launched and read current zoom 100 (1×). Preview reached the macOS camera permission request; live frames and pause/resume require permission and physical verification.
- CC3000e hardware presets remain experimental until a saved slot physically restores the framing. The user authorized slot 1 only. No other slots should be overwritten.

## Quick acceptance check

1. Allow Camera permission and confirm the preview. Switch to another app, then back: preview should pause and resume.
2. Try zoom plus/minus and the slider. Settings → Zoom level also accepts a number. Change slider stops and confirm both slider and buttons use that spacing.
3. Enable experimental CC3000e presets. At the desired framing, press M then 1. Move slightly, then press 1; visually check pan, tilt and zoom restoration. Preserve all other slots.
4. Check Home and Stop, then camera controls while your meeting app uses the camera. If a command fails, copy the diagnostic log from Settings.

The initial agent-sandbox resource error in the older probe log is historical; the normally launched app subsequently communicated successfully. The downloadable ZIP is a local ad-hoc signed build, not a notarized release.
