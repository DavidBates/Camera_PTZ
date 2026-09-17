import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var cameraController: CameraController
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Settings").font(.title2.bold()); Spacer(); Text("PTZ Control 1.1").foregroundStyle(.secondary).font(.caption) }.padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GroupBox("Preview") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Show camera preview", isOn: $cameraController.showPreview)
                            Toggle("Pause when the window is inactive", isOn: $cameraController.pausePreviewWhenInactive)
                                .disabled(!cameraController.showPreview)
                            Text("Pausing releases this app’s video input. Camera movement controls remain available.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                    GroupBox("Zoom") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Zoom level")
                                TextField("Level", value: Binding<Double>(get: {
                                    guard let z = cameraController.currentZoom else { return 1 }
                                    return Double(cameraController.displayedZoom) / Double(max(1, z.minimum))
                                }, set: { value in
                                    guard value.isFinite, let z = cameraController.currentZoom else { return }
                                    let raw = max(Double(z.minimum), min(Double(z.maximum), value * Double(max(1,z.minimum))))
                                    cameraController.setZoom(Int(raw.rounded()))
                                }), format: .number.precision(.fractionLength(2)))
                                    .frame(width: 65).accessibilityLabel("Zoom multiplier")
                                    .disabled(cameraController.currentZoom == nil)
                                Text("×")
                                Spacer()
                                Button("Refresh") { cameraController.refreshZoom() }.disabled(cameraController.isBusy)
                            }
                            Stepper("Slider stops: \(cameraController.zoomStopCount)", value: $cameraController.zoomStopCount, in: 2...91)
                            Text("The slider and + / − buttons use the same stops. More stops give finer adjustments; fewer give larger steps.")
                                .font(.caption).foregroundStyle(.secondary)
                            if let z = cameraController.currentZoom {
                                Text(String(format: "Camera range: %.1f×–%.1f× · about %.2f× per step", Double(z.minimum)/Double(max(1,z.minimum)), Double(z.maximum)/Double(max(1,z.minimum)), Double(z.maximum-z.minimum)/Double(max(1,z.minimum))/Double(cameraController.zoomStopCount-1)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                    GroupBox("Movement") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Use Logitech step movement", isOn: $cameraController.useLogitechMotionControl)
                            HStack {
                                Text("Pulse duration")
                                TextField("Milliseconds", value: $cameraController.motorIntervalTimer, format: .number).frame(width: 65)
                                Text("ms (30–500)").foregroundStyle(.secondary)
                            }.disabled(cameraController.useLogitechMotionControl)
                            Stepper("Motor speed: \(cameraController.movementSpeed)", value: $cameraController.movementSpeed, in: cameraController.availableSpeedRange)
                                .disabled(cameraController.useLogitechMotionControl || cameraController.availableSpeedRange.lowerBound == cameraController.availableSpeedRange.upperBound)
                            Text(cameraController.availableSpeedRange.lowerBound == cameraController.availableSpeedRange.upperBound ? "This camera reports a fixed motor speed. For a larger standard-motion nudge, increase pulse duration." : "Motor speed applies to standard motion. Logitech step movement uses fixed increments.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                    GroupBox("Presets") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Try CC3000e hardware presets", isOn: $cameraController.experimentalHardwarePresets)
                            Text("Experimental: M followed by a number saves over that camera slot. A number recalls it. Check that recall returns to the saved framing; USB success alone does not prove preset support.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                    GroupBox("Camera & diagnostics") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(cameraController.selectedCameraName ?? "No camera connected").font(.subheadline)
                            TextField("Camera name filter (blank for automatic)", text: $cameraController.deviceFilter)
                            HStack {
                                Button("Rescan") { cameraController.discoverCameras() }
                                Button("Probe Camera") { cameraController.probeCamera() }
                                Button("Copy Log") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(cameraController.probeLog, forType: .string)
                                }
                            }.disabled(cameraController.isBusy)
                            ScrollView {
                                Text(cameraController.probeLog).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(height: 130)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                }.padding()
            }
            Divider()
            HStack { Spacer(); Button("Done") { cameraController.saveSettings(); dismiss() }.keyboardShortcut(.defaultAction) }.padding()
        }.frame(width: 520, height: 660)
        .onDisappear { cameraController.saveSettings() }
    }
}
