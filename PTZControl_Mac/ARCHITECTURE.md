# Inspection and replacement report

Version 1.1 adds independent AVFoundation video preview with window-activity lifecycle management, hardware-range zoom presentation, adjustable discrete slider stops, latest-value zoom coalescing, and an explicitly opt-in CC3000e preset experiment. The existing USB backend and compact directional/preset controls are retained. Camera permission is required only for preview; see README for the current entitlement requirements.

## Original architecture

`PTZControlMacApp` owns a shared `CameraController` observable object. `ContentView`
has arrow, zoom, Home, memory and eight preset buttons; each action calls its matching
controller method. Those methods forward to concrete `USBCameraControl` methods and
ignore Boolean failure results. Settings persists Windows-inspired options using
UserDefaults and starts a background USB probe.

AVFoundation discovers cameras by their names. `CameraPreviewView` independently
opens a video capture session. `setDevice` looks up a CoreMediaIO ID but does not use
that ID to send PTZ. USB is opened lazily by a VID/PID parser; the parser recognizes a
Windows-style identifier and otherwise chooses the first Logitech device. An even
broader fallback can select the first UVC device on the bus.

There is no existing protocol abstraction. `USBCameraControl` combines discovery,
COM-style IOKit interface pointers, USB setup packets, Logitech command policy, and
probing. Its own header describes it as a template/example.

## Evidence of failure

1. `zoom` prints `Mock: Zoom` and returns false. It cannot control zoom.
2. `wIndex` is encoded as `(interface << 8) | unit`. UVC entity requests require
   `(entity << 8) | interface`. This addresses the wrong interface/entity.
3. The locally re-created `kIOUSBDeviceInterfaceID650` and
   `kIOUSBInterfaceInterfaceID300` UUID bytes do not match the installed Apple SDK.
   The SDK values are `4AAC1B2E-24C2-476A-964D-91333534F2CC` and
   `BCEAADDC-884D-4F27-8340-36D69FAB90F6`.
   The original also stores the device interface using the unversioned struct and
   passes a dereferenced interface pointer as ControlRequest's `self` argument.
4. Peripheral unit 6 is assumed; probing tries arbitrary unit IDs 2–10 and accepts
   the first selector response. It does not parse GUIDs to distinguish camera
   terminals, processing units and Logitech extension units.
5. Home and presets send a four-byte Windows DWORD to USB. cameractrls defines the
   matching Logitech selector as one byte. The original decodes `GET_LEN` backwards.
6. Pan/tilt copies Windows byte packing; its negative step encoding differs from
   cameractrls' documented byte sequences. The actual hardware response must decide
   behavior; Windows driver property storage is not a USB wire contract.
7. `USBDeviceOpen` and `USBInterfaceOpen` require ownership not needed for simple
   device control requests, creating a potential conflict with Apple's video driver.
8. Camera switching does not close the prior USB handle. `No Reset on Startup`
   accidentally skips initial USB selection as well as reset. Probe and UI requests
   can race on mutable USB pointers. Settings for motion mode and motor interval
   do not affect the original movement implementation; no explicit stop exists.
9. The project already enables USB access; a missing entitlement is not established
   as the original cause. The new diagnostic's `CreatePlugIn` resource error also
   occurs before packet encoding can be tested.

Video discovery/capture uses a separate, functional Apple stack, so its success says
nothing about the correctness of this custom USB request path.

## What is retained

The SwiftUI application shell, 220-point control panel, arrow/home/zoom layout,
camera selector, memory/preset layout, Settings entry point, motion-mode and interval
preferences, assets, product identity and Xcode project are retained. Preset actions
now update selection only after success. A small Stop button and status message are
added. The preview and misleading no-reset/guard options are removed: startup always
performs read-only discovery and USB requests have bounded timeouts. View state uses
an observable object so the project does not require the newer State compiler macro.

## Replacement boundary

- `CameraController`: main-thread presentation state; one serial worker owns all USB
  operations. Busy input is rejected instead of queued into a movement backlog.
- `PTZCameraController`: pan, tilt, zoom, stop, home, presets, connect and diagnostics.
- `CC3000eController`: capability-gated UVC/Logitech policy and packet logging.
- `UVCDescriptors`: validates descriptor boundaries and discovers terminal/XU IDs,
  interface numbers, GUIDs and control bitmaps. Multiple camera terminals are rejected
  as ambiguous instead of guessed.
- `USBTransport`: injectable boundary for deterministic packet tests.
- `USBBridge.c`: Apple-header-defined IOKit UUIDs and correctly typed interface calls.
  Reads the active configuration and issues endpoint-zero requests without seizing.

`CC3000eController` is marked unchecked Sendable because the adapter guarantees serial
access. Direct callers, including the diagnostic, must also call it serially.

Standard controls use Camera Terminal selectors `0B` (two-byte LE zoom), `0D`
(eight-byte signed LE absolute pan/tilt) and `0E` (four-byte relative direction/speed).
Motion selection is standard relative, then standard absolute, then Logitech step;
Settings can prefer the Logitech step path. It does not try a different movement
protocol after a failed SET, since the first command might already have moved.

Logitech peripheral GUID is `FFE52D21-8030-4E2C-82D9-F587D00540BD`, stored on wire as
`21 2D E5 FF 30 80 2C 4E 82 D9 F5 87 D0 05 40 BD`. Selector 1 is a four-byte step;
selector 2 is one-byte reset/preset mode. Both must exist in the descriptor and pass
GET_INFO/GET_LEN checks. Step directions follow cameractrls, including `FF FE` for a
negative step; physical direction validation remains outstanding. Standard UVC
relative packets instead use separate signed direction and unsigned speed bytes.

Hardware presets follow cameractrls' explicit model allowlist. `046d:0848` is absent;
for this model the app saves readable standard absolute pan/tilt and zoom locally.
If those controls are absent, presets report unsupported rather than claim success.

Every transfer logs timestamp, bmRequestType, bRequest, wValue, wIndex, length,
outbound payload, actual length, returned payload, numeric IOReturn and duration.
Short transfers fail. Connection/configuration operations also log their result.
A device disconnect requires a rescan, avoiding silent rebinding to another device.

## Primary sources inspected

- [cameractrls.py](https://github.com/soyersoyer/cameractrls/blob/master/cameractrls.py):
  Logitech peripheral GUID, selectors, exact step bytes, one-byte reset/preset payload,
  preset model allowlist. Linux ioctl plumbing is not ported.
- [xMRi ExtensionUnit.cpp](https://github.com/xMRi/PTZControl/blob/main/PTZControl/ExtensionUnit.cpp)
  and [ExtensionUnitDefines.h](https://github.com/xMRi/PTZControl/blob/main/PTZControl/ExtensionUnitDefines.h):
  same peripheral GUID/selectors and reset/preset values; Windows camera-control
  zoom and relative movement. The original Swift comments explicitly cite this code.
- [Linux UVC control mappings](https://github.com/torvalds/linux/blob/master/drivers/media/usb/uvc/uvc_ctrl.c):
  standard relative direction/speed and absolute control formats.
- Apple's installed `IOKit.framework/Headers/usb/IOUSBLib.h`: official UUIDs,
  interface types, descriptor access, DeviceRequestTO open requirements and timeouts.
- [Apple USB entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.usb)
  and [USB Device Interface Guide](https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/USBBook/USBDeviceInterfaces/USBDevInterfaces.html).

Reference snapshot downloaded 2026-09-17, SHA-256:

- cameractrls.py: `5c0b899b4fe32229c9e6e58fe1132cce8b84660aed073a6fb1728e1675da68b6`
- ExtensionUnit.cpp: `6e5b5aa94ef7e5e6b21901326e4b97e548e6636e58bb5a1f58c21e6b1d167b63`

Preserve the supplied project's GPL license when distributing derivatives.
