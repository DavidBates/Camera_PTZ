# App Review notes

PTZ Control is a macOS menu bar utility for the Logitech ConferenceCam CC3000e. Physical camera movement and live video require that USB camera. An interactive Demo mode is included for reviewing the controls without hardware or camera permission.

1. Launch the app. The controls panel opens automatically; reopen it using the camera-and-arrows icon in the macOS menu bar.
2. With no supported camera attached, the panel displays **No suitable camera found**. Select **Try Demo mode**.
3. A persistent **DEMO MODE** banner identifies the simulated session. Use the direction buttons and zoom slider or +/− buttons to change the illustrated framing. **Home** resets framing and zoom.
4. Expand **Image controls** to try brightness, contrast, color intensity, autofocus/manual focus, auto/manual white balance, and the sample anti-flicker setting. Disable an automatic control to enable its manual slider. **Restore defaults** resets image adjustments without changing framing.
5. The gear opens Settings, where the demo banner remains visible. Preview format and zoom stops can be changed there. Focus and color effects are illustrative; anti-flicker does not simulate real lighting flicker.
6. **Exit demo & scan for camera** discards the simulated values and searches for hardware. With no camera attached, the no-camera message returns. Demo values are never applied to a physical camera.

Demo mode uses an illustration, not live video. Movement uses finite nudges; Stop does not need to interrupt an ongoing animation. No account, network service, or extra download is required.

## Local verification

- Native Debug build succeeded.
- Existing USB protocol checks passed.
- With supported hardware unplugged, run `bash check-demo.sh` from this directory to check discovery, simulated control changes, bounds, defaults, Home, and exit/rescan.
- Demo panel visually inspected. Full interactive UI walkthrough remains to be completed before submission.
