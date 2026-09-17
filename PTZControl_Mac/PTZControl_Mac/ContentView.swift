import SwiftUI
import AppKit
import Combine

@MainActor
final class PTZViewState: ObservableObject {
    @Published var selectedPreset: Int?
    @Published var memoryMode = false
    @Published var showingSettings = false
}
struct ContentView: View {
    @EnvironmentObject var cameraController: CameraController
    @StateObject private var state = PTZViewState()
    private var canMove: Bool { cameraController.isConnected && !cameraController.isBusy && !state.showingSettings }
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PTZ Control").font(.headline)
                    Text(cameraController.selectedCameraName ?? "No camera")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 2)
                Button { state.showingSettings = true } label: { Image(systemName: "gearshape") }
                    .help("Settings").accessibilityLabel("Settings")
                Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "xmark") }
                    .help("Quit").accessibilityLabel("Quit")
            }
            if cameraController.cameras.count > 1 {
                Picker("Camera", selection: Binding(get: { cameraController.selectedCameraIndex }, set: { cameraController.selectCamera($0) })) {
                    ForEach(Array(cameraController.cameras.enumerated()), id: \.element.id) { index, camera in Text(camera.name).tag(index) }
                }.disabled(cameraController.isBusy)
            }
            if cameraController.showPreview {
                CameraPreviewPanel(camera: cameraController.selectedCamera, enabled: true, pauseWhenInactive: cameraController.pausePreviewWhenInactive)
            }
            VStack(spacing: 6) {
                direction("arrow.up", "Tilt up") { cameraController.tilt(.up) }
                HStack(spacing: 6) {
                    direction("arrow.left", "Pan left") { cameraController.pan(.left) }
                    Button {
                        cameraController.gotoHome { ok in if ok { state.selectedPreset = nil } }
                    } label: { Image(systemName: "house").frame(width: 54, height: 28) }
                        .help("Home").accessibilityLabel("Home")
                    direction("arrow.right", "Pan right") { cameraController.pan(.right) }
                }
                direction("arrow.down", "Tilt down") { cameraController.tilt(.down) }
            }
            .buttonStyle(.bordered).controlSize(.large).disabled(!canMove)
            Divider()
            VStack(spacing: 5) {
                HStack {
                    Text("Zoom").font(.subheadline)
                    Spacer()
                    Text(cameraController.zoomLabel).font(.system(.subheadline, design: .monospaced)).monospacedDigit()
                }
                ZoomSlider(stops: cameraController.zoomStops, value: cameraController.displayedZoom, enabled: cameraController.isConnected) { cameraController.setZoom($0); state.selectedPreset = nil }
                    .frame(height: 26)
                HStack {
                    Button { cameraController.zoom(.out); state.selectedPreset = nil } label: {
                        Image(systemName: "minus.magnifyingglass").frame(maxWidth: .infinity, minHeight: 25)
                    }.accessibilityLabel("Zoom out")
                    Button { cameraController.zoom(.in); state.selectedPreset = nil } label: {
                        Image(systemName: "plus.magnifyingglass").frame(maxWidth: .infinity, minHeight: 25)
                    }.accessibilityLabel("Zoom in")
                }.buttonStyle(.bordered).disabled(!cameraController.isConnected || cameraController.currentZoom == nil)
            }
            Divider()
            HStack {
                Text("Presets").font(.subheadline)
                Spacer()
                Button(state.memoryMode ? "Choose slot…" : "M") { state.memoryMode.toggle() }
                    .tint(state.memoryMode ? .orange : .gray)
                    .help("Save the current framing: click M, then a preset number")
                    .accessibilityLabel("Save preset mode")
                    .disabled(!canMove)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 6) {
                ForEach(1...8, id: \.self) { slot in
                    Button { preset(slot) } label: { Text("\(slot)").frame(maxWidth: .infinity, minHeight: 25) }
                        .tint(state.selectedPreset == slot ? .green : .gray)
                        .help(state.memoryMode ? "Save preset \(slot)" : "Recall preset \(slot)")
                        .disabled(!canMove)
                }
            }
            Button("Stop") { cameraController.stop() }
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.cancelAction)
                .disabled(!cameraController.isConnected)
            HStack(alignment: .top, spacing: 5) {
                if cameraController.isBusy { ProgressView().controlSize(.small) }
                Text(cameraController.status)
                    .font(.caption).foregroundColor(cameraController.lastActionFailed ? .orange : .secondary)
                    .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                    .help(cameraController.status)
            }.frame(minHeight: 32)
        }
        .padding(12).frame(width: 260)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $state.showingSettings) { SettingsView().environmentObject(cameraController) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in cameraController.shutdown() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in cameraController.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in cameraController.refreshZoom() }
        .onChange(of: cameraController.selectedCameraIndex) { _, _ in state.selectedPreset = nil; state.memoryMode = false }
        .onDisappear { cameraController.stop() }
        .onAppear { cameraController.discoverCameras() }
    }
    private func direction(_ image: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button { state.selectedPreset = nil; action() } label: { Image(systemName: image).frame(width: 54, height: 28) }
            .help(label).accessibilityLabel(label)
    }
    private func preset(_ slot: Int) {
        if state.memoryMode {
            cameraController.savePreset(slot) { ok in if ok { state.memoryMode = false; state.selectedPreset = slot } }
        } else {
            cameraController.gotoPreset(slot) { ok in if ok { state.selectedPreset = slot } }
        }
    }
}
