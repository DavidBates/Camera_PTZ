import SwiftUI

struct ImageControlsView: View {
    @EnvironmentObject var cameraController: CameraController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Preview format", selection: $cameraController.previewWidescreen) {
                Text("Standard (4:3)").tag(false)
                Text("Widescreen (16:9)").tag(true)
            }
            Text("Preview only; meeting apps choose their own format.").font(.caption2).foregroundStyle(.secondary)

            ForEach([ImageControl.brightness, .contrast, .saturation, .autoFocus, .focus, .autoWhiteBalance, .whiteBalance, .antiFlicker]) { kind in
                if let state = cameraController.imageControls.first(where: { $0.control == kind }) {
                    if kind.isAuto {
                        Toggle(kind.title, isOn: Binding(get: { state.current != 0 }, set: { cameraController.setImage(kind, value: $0 ? 1 : 0) }))
                            .disabled(!state.writable || cameraController.isBusy)
                    } else if kind == .antiFlicker {
                        Picker("Anti-flicker", selection: Binding(get: { state.current }, set: { cameraController.setImage(kind, value: $0) })) {
                            Text("Off").tag(0)
                            Text("50 Hz").tag(1)
                            Text("60 Hz").tag(2)
                        }.disabled(!state.writable || cameraController.isBusy)
                    } else {
                        ImageValueSlider(state: state, enabled: state.writable && !cameraController.isBusy && !autoEnabled(kind)) {
                            cameraController.setImage(kind, value: $0)
                        }
                    }
                } else {
                    Text("\(kind.title): unavailable").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Refresh") { cameraController.refreshImageControls() }
                Spacer()
                Button("Restore defaults") { cameraController.restoreImageDefaults() }
                    .disabled(cameraController.imageControls.isEmpty)
            }.disabled(!cameraController.isConnected || cameraController.isBusy)
            Text("Image settings affect the camera. Restore defaults leaves pan, tilt and zoom unchanged.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func autoEnabled(_ kind: ImageControl) -> Bool {
        guard let partner = kind.autoPartner else { return false }
        return (cameraController.imageControls.first { $0.control == partner }?.current ?? 0) != 0
    }
}

private struct ImageValueSlider: View {
    let state: ImageControlState
    let enabled: Bool
    let commit: (Int) -> Void
    @State private var draft = 0.0
    @State private var editing = false
    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(state.control.title)
                Spacer()
                Text(label).monospacedDigit().foregroundStyle(.secondary)
            }.font(.caption)
            Slider(value: Binding(get: { editing ? draft : Double(state.current) }, set: { draft = $0 }),
                   in: Double(state.minimum)...Double(max(state.minimum + 1, state.maximum)),
                   step: Double(max(1, state.resolution))) { active in
                if active { draft = Double(state.current); editing = true }
                else { let value = state.clamped(Int(draft.rounded())); editing = false; commit(value) }
            }
            .disabled(!enabled || state.maximum == state.minimum)
            .accessibilityLabel(state.control.title)
        }
    }
    private var label: String {
        let value = editing ? Int(draft.rounded()) : state.current
        if state.control == .whiteBalance { return "\(value) K" }
        let percent = 100 * (value - state.minimum) / max(1, state.maximum - state.minimum)
        return "\(percent)%"
    }
}
