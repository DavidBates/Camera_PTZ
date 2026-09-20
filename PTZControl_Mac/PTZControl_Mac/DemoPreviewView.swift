import SwiftUI

struct CameraConnectionView: View {
    @EnvironmentObject var cameraController: CameraController
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(cameraController.isDemoMode ? "DEMO MODE" : cameraController.isConnected ? "Camera connected" : cameraController.isBusy ? "Searching / connecting…" : "No suitable camera found",
                  systemImage: cameraController.isDemoMode ? "play.rectangle" : cameraController.isConnected ? "checkmark.circle" : "video.slash")
                .font(.caption.bold())
            if cameraController.isDemoMode {
                Text("Simulated preview and controls. No physical camera is being controlled.")
                Button("Exit demo & scan for camera") { cameraController.discoverCameras() }
            } else if !cameraController.isConnected {
                Text("Control pan, tilt, zoom and image settings on a compatible PTZ camera. Connect it by USB, or explore the controls in Demo mode.")
                if !cameraController.deviceFilter.isEmpty {
                    Text("A camera name filter is active in Settings.")
                }
                HStack {
                    Button("Try Demo mode") { cameraController.startDemo() }
                    Button("Rescan") { cameraController.discoverCameras() }
                }.disabled(cameraController.isBusy)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background((cameraController.isDemoMode ? Color.orange : Color.blue).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8))
    }
}

struct DemoPreviewView: View {
    @EnvironmentObject var cameraController: CameraController
    private func value(_ kind: ImageControl) -> Double {
        Double(cameraController.imageControls.first { $0.control == kind }?.current ?? 128)
    }
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack {
                    Color(red: 0.18, green: 0.34, blue: 0.44)
                    // An oversized illustrated scene makes framing changes visible at 1×.
                    VStack(spacing: 12) {
                        HStack(spacing: 35) {
                            Image(systemName: "leaf.fill").foregroundStyle(.green)
                            Image(systemName: "person.crop.square.fill").foregroundStyle(.orange)
                            Image(systemName: "lamp.desk.fill").foregroundStyle(.yellow)
                        }.font(.system(size: 48))
                        RoundedRectangle(cornerRadius: 5).fill(.brown).frame(width: 340, height: 16)
                        HStack(spacing: 40) {
                            Text("A").foregroundStyle(.cyan)
                            Text("B").foregroundStyle(.white)
                            Text("C").foregroundStyle(.pink)
                        }.font(.system(size: 28, weight: .bold, design: .rounded))
                    }
                    .scaleEffect(Double(cameraController.displayedZoom) / 100)
                    .offset(x: -cameraController.demoPan * geometry.size.width,
                            y: cameraController.demoTilt * geometry.size.height)
                    .blur(radius: value(.autoFocus) == 0 ? abs(value(.focus) - 128) / 30 : 0)
                }
                .saturation(value(.saturation) / 128)
                .contrast(value(.contrast) / 128)
                .brightness((value(.brightness) - 128) / 255)
                .overlay((value(.whiteBalance) > 4500 ? Color.orange : Color.blue)
                    .opacity(value(.autoWhiteBalance) == 0 ? abs(value(.whiteBalance) - 4500) / 15000 : 0))
                .clipped()
            }
            .aspectRatio(cameraController.previewWidescreen ? 16 / 9 : 4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("SIMULATED PREVIEW · Pan / tilt to explore")
                .font(.system(size: 9, weight: .semibold))
            Text("Pan \(Int((cameraController.demoPan * 100).rounded()))% · Tilt \(Int((cameraController.demoTilt * 100).rounded()))% · \(cameraController.zoomLabel)")
                .font(.caption2).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
