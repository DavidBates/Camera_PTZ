# Hardware verification — 2026-09-17, 21:05–21:07 UTC

The initially running app was the original Xcode build, not the updated output.
Its Settings showed PID 0000, guessed unit 6, and four-byte reset/preset payloads.
Closed that instance and opened the updated signed app at outputs/UpdatedApp/PTZControl_Mac.app.

Observed through the running app's diagnostic UI:

- Device: 046d:0848, location 02130000; registry ID 4295684129.
- VideoControl interface 0; camera terminal 1, bitmap 2E 12 02.
- Processing unit 3, bitmap 5B 17.
- Logitech peripheral XU is unit 11, GUID FFE52D21-8030-4E2C-82D9-F587D00540BD.
- Standard absolute zoom: GET_INFO 03; min 100, max 1000, resolution 1, default 100.
- Standard relative pan/tilt: GET_INFO 03; min/max/res/default speed bytes all 1.
- Standard absolute pan/tilt is not advertised. Software position presets therefore cannot work on this camera; hardware presets remain unverified.
- XU selector 1: GET_INFO 03, GET_LEN 4. Selector 2: GET_INFO 02 (SET only), GET_LEN 1.
- Zoom-in SET_CUR [B5 00] at wValue 0B00 / wIndex 0100 succeeded. GET_CUR confirmed 181.
- Zoom-out SET_CUR [B4 00] succeeded. GET_CUR confirmed original zoom 180 restored.
- Logitech pan-right [FF FE 00 00] and pan-left [00 01 00 00] at wValue 0100 / wIndex 0B00 both returned IOReturn 0 with actual length 4.
- Standard STOP [00 00 00 00] at wValue 0E00 / wIndex 0100 returned IOReturn 0, actual length 4.

The signed sandboxed app can access USB when launched normally. The earlier command-line agent sandbox resource error is not representative of this runtime.
Zoom setting readback is hardware-confirmed. Pan commands are USB-confirmed; physical direction/displacement was not visually observed. Home, tilt, hardware presets and video-app coexistence remain untested in this session.
