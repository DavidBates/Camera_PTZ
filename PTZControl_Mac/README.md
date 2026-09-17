# PTZControl Mac — CC3000e native backend

This is a working copy of the supplied Xcode project. The original at
`/Users/david.bates/Projects/GitHub/PTZControl/PTZControlMac/PTZControl_Mac`
is preserved; the updated source and application are delivered in this folder.

## Version 1.1

- Live camera preview, with a setting to release video capture when the window is inactive (on by default).
- Current zoom level, a notched zoom slider, and plus/minus buttons that use the same stops.
- Settings allow a numeric zoom level and 2–91 slider stops. Default: 19 stops (0.5× increments on the tested 1×–10× CC3000e).
- Rapid slider changes are coalesced; USB requests remain serialized.
- The camera reports a fixed relative movement speed. Settings show this instead of implying unsupported speed adjustment; pulse duration remains adjustable.
- Optional experimental CC3000e hardware presets. Enable **Try CC3000e hardware presets**, use **M → 1** to save, then **1** to recall. Saving overwrites that camera slot. USB success alone does not establish that the camera remembered a position.

## Current verification

- Native arm64 app builds; 30 protocol tests pass.
- The signed sandboxed app now successfully communicates with the physical CC3000e.
- Zoom changed from 180 to 181 and back to 180, verified by camera readback.
- Logitech pan-left/pan-right and standard STOP requests return USB success.
- Actual VideoControl interface is 0, camera terminal 1, Logitech peripheral XU 11.
- Absolute pan/tilt is absent, so software position presets are unavailable on this camera.
- Pan direction/displacement, tilt, home, hardware presets and video-app coexistence still need visual testing.
- The earlier diagnostic resource error occurred inside the agent environment. See
  `Diagnostics/hardware-verification.md` for the newer physical-device evidence.

If you see the old settings with PID 0000 and peripheral unit 6, you launched the
original project. The updated app has a **Stop** button and status message. The
original project was not overwritten.

## Open and build

Open `PTZControl_Mac.xcodeproj`, select the `PTZControl_Mac` scheme and **My Mac**,
and run. Deployment target is macOS 14; architecture is arm64. Set your signing
team if Xcode asks. The project uses only Apple system frameworks and a small C
bridge to IOKit's public IOUSBLib headers. All PTZ policy and encoding is Swift.

For an ad-hoc local build without a development team:

```sh
xcodebuild -project PTZControl_Mac.xcodeproj -scheme PTZControl_Mac \
  -configuration Debug -derivedDataPath .build/App \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
```

A tested build is also supplied as `PTZControl_Mac.zip` alongside this project.
Unzip it to obtain `PTZControl_Mac.app`; the ZIP prevents cloud file-provider metadata
from contaminating the signed bundle.
It is intended for local testing, not a notarized distribution release.

## One physical-camera test session

1. Leave the camera connected. Run the app from Xcode and retain **all console output**,
   including `[USB]` lines. Startup is read-only; it never resets or moves the camera.
2. Open Settings → **Probe Camera**. The log contains raw configuration descriptors,
   VID/PID/location, interfaces, camera terminal, processing units, XU GUID bytes,
   capability bitmaps, and PTZ `GET_INFO`, supported XU `GET_LEN`, and standard
   `GET_CUR/MIN/MAX/RES/DEF` results. Copy Diagnostic Log captures Swift logs;
   the complete Xcode console also includes C-level connection/configuration failures.
3. Click **zoom in once**, then **zoom out once**. Check for successful two-byte
   `SET_CUR` and readback, and visually confirm zoom. If either fails, save the
   log before continuing. At a range endpoint an outward request may be a no-op.
4. Click right, left, up, down individually. Standard relative control sends a
   bounded 70 ms pulse followed by STOP. Absolute-only cameras move one reported
   resolution step. If standard motion is unavailable but the Logitech peripheral
   XU is advertised, it uses a finite one-step command.
5. Use **Stop** or Escape. Focus loss/window disappearance and application shutdown
   also request stop. The existing UI remains click-to-nudge; it does not start an
   unbounded hold-to-move operation. Each USB request has a 1-second completion timeout.
   Stop waits for the current bounded operation on the serial queue; it cannot
   cancel a hung kernel call or a previously submitted absolute/XU finite move.
6. Check **Use Logitech Camera Motion Control** to test the independently encoded
   XU step path, only if the probe reports it. Try each direction once and retain
   the log so orientation can be checked on the physical device.
7. Click Home. Prefer verified one-byte Logitech reset-both (`03`), otherwise use
   standard absolute `GET_DEF`; zoom uses its reported default. This is a position
   reset, not a USB device reset or a factory reset.
8. Hardware presets are experimental on CC3000e. Enable them in Settings, save an authorized slot with M → slot, nudge, and recall that slot. Check both framing and zoom visually. Do not overwrite other slots during testing. Software presets require readable absolute pan/tilt, which this camera does not advertise.
9. Repeat one zoom/pan pulse while Meet, Zoom, or OBS is using the camera. Confirm
   its video continues. Unplug the camera; the next command should report an error.
   Reconnect and use **Rescan Cameras** to establish a fresh registry identity.

Movement speed in Settings is clamped and quantized to the reported relative
speed range/resolution. The motor interval is bounded to 30–500 ms. Neither setting
changes Logitech finite-step distance or absolute-coordinate resolution.

## Diagnostic executable and protocol tests

From the project directory:

```sh
./check.sh > protocol-tests.log 2>&1
.build/Diagnostics > cc3000e-probe.log 2>&1
# Only after checking the read-only log; these commands move the camera:
.build/Diagnostics --zoom-in > cc3000e-zoom-in.log 2>&1
.build/Diagnostics --zoom-out > cc3000e-zoom-out.log 2>&1
```

Diagnostics requires exactly one `046d:0848` device, preventing accidental camera
selection. Optional flags: `--pan-right`, `--pan-left`, `--tilt-up`, `--tilt-down`,
`--stop`, `--home`. No arguments means read-only. Run from your normal Terminal to
compare USB access with the sandboxed app; do not run as root. The diagnostic has
no App Sandbox entitlement, so this comparison isolates app signing/entitlement
issues from the USB protocol. A sandbox around the parent process still applies.

## Permissions and coexistence

The signed app explicitly includes:

- `com.apple.security.app-sandbox = true`
- `com.apple.security.device.usb = true`
- `com.apple.security.device.camera = true`

The preview uses AVFoundation and requests macOS Camera permission. Allow it in the
system prompt, or System Settings → Privacy & Security → Camera. No microphone
permission or audio input is used. Preview can be disabled in Settings; PTZ remains
independent of video capture and camera permission. With **Pause when window is
inactive** enabled, the capture session stops and removes its video input when the
window loses focus, is minimized, or becomes hidden. It restarts on return.
Camera permission does not authorize raw USB access. Apple USB accessory approval,
where enabled, must also allow the connected device.

No DriverKit entitlement, system extension, kernel extension, administrator access,
or legacy Logitech process is required by this implementation. It uses documented
`IOUSBDeviceInterface320.DeviceRequestTO` on endpoint zero without exclusive device
open. It never calls seize, claims the video interface, changes configuration,
resets the device, or detaches Apple's UVC driver. Apple's SDK documents that
DeviceRequestTO need not open the device for ordinary requests; whether this camera
and OS permit the class requests alongside Apple's driver requires the test above.

`0xe00002be` is a resource error, **not proof of a missing entitlement**. Compare the
signed app and ordinary Terminal diagnostic if it persists. A failure before the
first UVC request concerns user-client access, not payload encoding. Preserve the
exact error and stage; do not respond by guessing unit IDs or seizing the device.

Check the actual signature, not only the source entitlement file:

```sh
codesign -d --entitlements :- PTZControl_Mac.app
file PTZControl_Mac.app/Contents/MacOS/PTZControl_Mac
```

See `ARCHITECTURE.md` for original faults, protocol provenance, and implementation choices.
