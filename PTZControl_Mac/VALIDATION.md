# Version 1.3 validation

- Native arm64 Xcode build: succeeded.
- Strict app signature verification: passed.
- Protocol tests: 41 passed, zero failures.
- Physical read-only CC3000e probe: all eight image controls available. See Diagnostics/image-controls-readonly.log.
- Brightness/contrast/saturation: 0–255, current and default 128.
- Focus: 0–255, current 30, default 0; autofocus on.
- White balance: 2000–7500 K, current 7500, default 4000; Auto on.
- Anti-flicker: current/default 2 (60 Hz).
- No physical image SET requests, preset writes or movement were performed during this update.
- Visual UI testing was blocked by desktop automation timeout. Quit the older app, run Build/PTZControl_Mac 1.3.app, then test each control and the preview formats. Turn Auto off before testing manual focus/white balance; turn it back on afterward if desired.
- Restore defaults intentionally excludes pan, tilt and zoom. Aspect ratio is preview-only.
