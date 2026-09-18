import SwiftUI
import AVFoundation
import AppKit
import Combine

// The capture queue owns all session mutations. USB control remains independent.
final class PreviewCaptureWorker: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.magician.ptz.preview")
    private var selectedID: String?
    private var registryID: UInt64?
    func update(camera: Camera?, run: Bool, widescreen: Bool = false, completion: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            guard run, let camera else {
                if session.isRunning { session.stopRunning() }
                session.beginConfiguration()
                for input in session.inputs { session.removeInput(input) }
                session.commitConfiguration(); selectedID = nil; registryID = nil
                print("[Preview] stopped; video input released")
                completion("Preview paused")
                return
            }
            if registryID != camera.id {
                if session.isRunning { session.stopRunning() }
                session.beginConfiguration()
                for input in session.inputs { session.removeInput(input) }
                session.commitConfiguration(); selectedID = nil; registryID = camera.id
            }
            let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified).devices
            let packedID = UInt64(camera.location) << 32 | UInt64(camera.vendor) << 16 | UInt64(camera.product)
            let exact = devices.filter { UInt64($0.uniqueID.replacingOccurrences(of: "0x", with: ""), radix: 16) == packedID }
            let named = devices.filter { $0.localizedName == camera.name }
            // Never guess among identical cameras. Exact packed USB identity is preferred.
            let match = exact.count == 1 ? exact.first : (named.count == 1 ? named.first : nil)
            guard let device = match else { completion("Preview camera unavailable or ambiguous. PTZ still works."); return }
            do {
                if selectedID != device.uniqueID {
                    if session.isRunning { session.stopRunning() }
                    session.beginConfiguration(); selectedID = nil
                    for input in session.inputs { session.removeInput(input) }

                    let input: AVCaptureDeviceInput
                    do { input = try AVCaptureDeviceInput(device: device) }
                    catch { session.commitConfiguration(); throw error }
                    guard session.canAddInput(input) else {
                        session.commitConfiguration()
                        completion("Camera preview unavailable. PTZ still works."); return
                    }
                    session.addInput(input); session.commitConfiguration(); selectedID = device.uniqueID
                    print("[Preview] matched \(device.localizedName) UID=\(device.uniqueID)")
                }
                let preset: AVCaptureSession.Preset = widescreen ? .hd1280x720 : .vga640x480
                if session.sessionPreset != preset {
                    guard session.canSetSessionPreset(preset) else {
                        if session.isRunning { session.stopRunning() }
                        completion("Selected preview format unavailable. Choose another format."); return
                    }
                    session.beginConfiguration(); session.sessionPreset = preset; session.commitConfiguration()
                }
                if !session.isRunning { session.startRunning() }
                completion(session.isRunning ? nil : "Preview could not start. Try turning it off and on.")
            } catch { completion("Preview: \(error.localizedDescription)") }
        }
    }
    func stop() { update(camera: nil, run: false) { _ in } }
}

@MainActor
final class PreviewModel: ObservableObject {
    @Published var message: String? = "Preview paused"
    let worker = PreviewCaptureWorker()
    private var camera: Camera?
    private var widescreen = false
    private var enabled = true
    private var pauseWhenInactive = true
    private var active = false
    private var requestInFlight = false
    private var revision = 0
    private var notificationTokens: [NSObjectProtocol] = []
    init() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: worker.session, queue: .main) { [weak self] note in
            let description = (note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "Camera preview interrupted"
            Task { @MainActor [weak self] in self?.message = description }
        })
        notificationTokens.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: worker.session, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.message = "Preview interrupted. PTZ still works." }
        })
        notificationTokens.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: worker.session, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcile() }
        })
    }
    func configure(camera: Camera?, enabled: Bool, pause: Bool, widescreen: Bool) {
        self.widescreen = widescreen; self.camera = camera; self.enabled = enabled; pauseWhenInactive = pause; reconcile()
    }
    func activityChanged(_ value: Bool) { guard active != value else { return }; active = value; reconcile() }
    func stop() { enabled = false; reconcile() }
    private func reconcile() {
        revision += 1; let token = revision
        guard enabled, camera != nil, active || !pauseWhenInactive else {
            message = enabled ? "Preview paused" : "Preview off"
            worker.stop(); return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            message = "Allow camera access for the preview"
            guard !requestInFlight else { return }
            requestInFlight = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                Task { @MainActor [weak self] in self?.requestInFlight = false; self?.reconcile() }
            }
            return
        default:
            message = "Enable Camera access in System Settings → Privacy & Security. PTZ still works."
            worker.stop(); return
        }
        message = "Starting preview…"
        worker.update(camera: camera, run: true, widescreen: widescreen) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.revision == token else { return }
                self.message = result
            }
        }
    }
    deinit {
        for token in notificationTokens { NotificationCenter.default.removeObserver(token) }
        worker.stop()
    }
}

@MainActor
final class PreviewHostView: NSView {
    var activityChanged: ((Bool) -> Void)?
    private var tokens: [NSObjectProtocol] = []
    let previewLayer: AVCaptureVideoPreviewLayer
    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true; layer = previewLayer; previewLayer.videoGravity = .resizeAspect
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layout() { super.layout(); previewLayer.frame = bounds }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for token in tokens { NotificationCenter.default.removeObserver(token) }; tokens = []
        let names: [Notification.Name] = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSWindow.didChangeOcclusionStateNotification, NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification]
        for name in names {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.reportActivity() }
            })
        }
        reportActivity()
    }
    func reportActivity() {
        let active = NSApp.isActive && (window?.isKeyWindow == true) && (window?.isMiniaturized == false) && (window?.occlusionState.contains(.visible) == true)
        activityChanged?(active)
    }
    deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}
struct CameraPreviewSurface: NSViewRepresentable {
    @ObservedObject var model: PreviewModel
    func makeNSView(context: Context) -> PreviewHostView {
        let view = PreviewHostView(session: model.worker.session)
        view.activityChanged = { [weak model] active in model?.activityChanged(active) }
        return view
    }
    func updateNSView(_ view: PreviewHostView, context: Context) {}
    static func dismantleNSView(_ view: PreviewHostView, coordinator: ()) { view.activityChanged?(false); view.previewLayer.session = nil }
}
struct CameraPreviewPanel: View {
    let camera: Camera?
    let enabled: Bool
    let pauseWhenInactive: Bool
    let widescreen: Bool
    @StateObject private var model = PreviewModel()
    var body: some View {
        ZStack {
            Color.black
            CameraPreviewSurface(model: model)
            if let message = model.message {
                Color.black.opacity(0.85)
                VStack(spacing: 6) {
                    Image(systemName: "video.slash")
                    Text(message).font(.caption).multilineTextAlignment(.center)
                }.foregroundColor(.white).padding(8)
            }
        }
        .frame(height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { configure() }
        .onChange(of: camera) { _, _ in configure() }
        .onChange(of: widescreen) { _, _ in configure() }
        .onChange(of: enabled) { _, _ in configure() }
        .onChange(of: pauseWhenInactive) { _, _ in configure() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.stop() }
        .onDisappear { model.stop() }
    }
    private func configure() { model.configure(camera: camera, enabled: enabled, pause: pauseWhenInactive, widescreen: widescreen) }
}
