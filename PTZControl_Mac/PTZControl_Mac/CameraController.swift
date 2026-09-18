import Foundation
import Combine
import AppKit

@MainActor
final class CameraController: ObservableObject {
    @Published var cameras: [Camera] = []
    @Published var selectedCameraIndex = 0
    @Published var useLogitechMotionControl = false
    @Published var motorIntervalTimer = 70
    @Published var deviceFilter = ""
    @Published var isProbing = false
    @Published var isBusy = false
    @Published var isConnected = false
    @Published var probeLog = ""
    @Published var status = "Connect a camera"
    @Published var lastActionFailed = false
    @Published var availableSpeedRange = 1...1
    @Published var movementSpeed = 1
    @Published var currentZoom: ZoomState?
    @Published var zoomTarget: Int?
    @Published var showPreview = true { didSet { UserDefaults.standard.set(showPreview, forKey: "ShowPreview") } }
    @Published var pausePreviewWhenInactive = true { didSet { UserDefaults.standard.set(pausePreviewWhenInactive, forKey: "PausePreviewWhenInactive") } }
    @Published var zoomStopCount = 19 { didSet { UserDefaults.standard.set(zoomStopCount, forKey: "ZoomStopCount") } }
    @Published var previewWidescreen = false { didSet { UserDefaults.standard.set(previewWidescreen, forKey: "PreviewWidescreen") } }
    @Published var imageControls: [ImageControlState] = []
    private let queue = DispatchQueue(label: "dev.magician.ptz.usb", qos: .userInitiated)
    private let backend: PTZCameraController = CC3000eController()
    private var generation = 0
    private var pendingZoom: Int?
    private var zoomRefresh: DispatchWorkItem?
    init() {
        loadSettings()
    }
    var selectedCamera: Camera? { cameras.indices.contains(selectedCameraIndex) ? cameras[selectedCameraIndex] : nil }
    var selectedCameraName: String? { selectedCamera?.name }
    var zoomStops: [Int] { currentZoom?.stops(count: zoomStopCount) ?? [] }
    var displayedZoom: Int { zoomTarget ?? currentZoom?.current ?? 100 }
    var zoomLabel: String {
        guard let z = currentZoom else { return "Zoom unavailable" }
        return String(format: "%.2f×", Double(displayedZoom) / Double(max(1,z.minimum)))
    }
    func discoverCameras() {
        guard !isBusy else { return }
        isBusy = true; isConnected = false; imageControls = []; currentZoom = nil; pendingZoom = nil; zoomTarget = nil; generation += 1
        let token = generation; let backend = backend; let filter = deviceFilter
        queue.async { [weak self] in
            backend.disconnect()
            let found = CC3000eController.discover().filter { filter.isEmpty || filter == "*" || $0.name.localizedCaseInsensitiveContains(filter) }
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.cameras = found; self.selectedCameraIndex = 0; self.isBusy = false
                if found.isEmpty { self.status = "No Logitech camera found" }
                else { self.selectCamera(0) }
            }
        }
    }
    func selectCamera(_ index: Int) {
        guard !isBusy, cameras.indices.contains(index) else { return }
        generation += 1; pendingZoom = nil; zoomTarget = nil; currentZoom = nil; isConnected = false
        selectedCameraIndex = index
        let camera = cameras[index]
        perform("Ready: \(camera.name)", refreshImage: true, completion: { [weak self] ok in self?.isConnected = ok }) { try $0.connect(camera) }
    }
    private func perform(_ success: String, refreshImage: Bool = false, completion: ((Bool) -> Void)? = nil, action: @escaping (PTZCameraController) throws -> Void) {
        guard !isBusy else { completion?(false); return }
        isBusy = true; lastActionFailed = false
        let backend = backend; let token = generation; let speed = UInt8(clamping: movementSpeed)
        queue.async { [weak self] in
            (backend as? CC3000eController)?.speed = speed
            var failure: String?
            do { try action(backend) } catch { failure = error.localizedDescription; print("[PTZ ERROR] \(error.localizedDescription)") }
            let images = refreshImage ? backend.readImageControls() : nil
            let zoom = try? backend.readZoom()
            let speeds = backend.supportedMovementSpeeds ?? 1...1
            let report = backend.diagnosticReport(); let message = failure
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.isBusy = false; self.isProbing = false
                if let images { self.imageControls = images }
                self.currentZoom = zoom
                self.availableSpeedRange = speeds
                self.movementSpeed = max(speeds.lowerBound, min(speeds.upperBound, self.movementSpeed))
                self.probeLog = report; self.status = message ?? success; self.lastActionFailed = message != nil
                completion?(message == nil)
                self.drainZoom()
            }
        }
    }
    func pan(_ direction: PanDirection) {
        let interval = motorIntervalTimer, xu = useLogitechMotionControl
        perform("Pan complete") { try $0.pan(direction, milliseconds: interval, preferLogitech: xu) }
    }
    func tilt(_ direction: TiltDirection) {
        let interval = motorIntervalTimer, xu = useLogitechMotionControl
        perform("Tilt complete") { try $0.tilt(direction, milliseconds: interval, preferLogitech: xu) }
    }
    func zoom(_ direction: ZoomDirection) {
        guard let z = currentZoom else { return }
        let displayed = ZoomState(current: displayedZoom, minimum: z.minimum, maximum: z.maximum, resolution: z.resolution)
        setZoom(displayed.adjacent(direction: direction, stopCount: zoomStopCount))
    }
    func setZoom(_ value: Int) {
        guard isConnected, let z = currentZoom else { return }
        let target = z.clamped(value)
        pendingZoom = target; zoomTarget = target
        drainZoom()
    }
    private func drainZoom() {
        guard !isBusy, let target = pendingZoom else { return }
        pendingZoom = nil
        perform("Zoom \(zoomLabel)", completion: { [weak self] _ in
            guard let self else { return }
            if self.pendingZoom == nil { self.zoomTarget = nil }
        }) { try $0.setZoom(target) }
    }
    func refreshZoom() {
        guard isConnected, !isBusy else { return }
        perform("Ready") { _ in }
    }
    private func refreshZoomAfterRecall() {
        zoomRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshZoom() }
        zoomRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
    func gotoHome(completion: ((Bool) -> Void)? = nil) {
        pendingZoom = nil; zoomTarget = nil
        perform("Home command sent", completion: { [weak self] ok in
            if ok { self?.refreshZoomAfterRecall() }; completion?(ok)
        }) { try $0.home() }
    }
    func stop() {
        pendingZoom = nil; zoomTarget = nil
        let backend = backend; let token = generation
        queue.async { [weak self] in
            var errorMessage: String?
            do { try backend.stop() } catch { errorMessage = error.localizedDescription }
            let report = backend.diagnosticReport(); let error = errorMessage
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.probeLog = report
                if let error { self.status = error; self.lastActionFailed = true }
            }
        }
    }
    func shutdown() { zoomRefresh?.cancel(); let backend = backend; queue.sync { backend.disconnect() } }
    func refreshImageControls() {
        guard isConnected else { return }
        perform("Image controls refreshed", refreshImage: true) { _ in }
    }
    func setImage(_ kind: ImageControl, value: Int) {
        perform("\(kind.title) updated", refreshImage: true) { try $0.setImageControl(kind, value: value) }
    }
    func restoreImageDefaults() {
        perform("Image defaults restored", refreshImage: true) { try $0.restoreImageDefaults() }
    }
    func probeCamera() {
        guard !isBusy, let camera = selectedCamera else { return }
        isProbing = true
        perform("Probe complete", refreshImage: true, completion: { [weak self] ok in self?.isConnected = ok }) { try $0.connect(camera) }
    }
    func loadSettings() {
        let d = UserDefaults.standard
        previewWidescreen = d.bool(forKey: "PreviewWidescreen")
        useLogitechMotionControl = d.bool(forKey: "UseLogitechMotionControl")
        motorIntervalTimer = d.object(forKey: "MotorIntervalTimer") == nil ? 70 : max(30,min(500,d.integer(forKey:"MotorIntervalTimer")))
        deviceFilter = d.string(forKey:"DeviceFilter") ?? ""
        movementSpeed = max(1,min(255,d.integer(forKey:"MovementSpeed")))
        showPreview = d.object(forKey:"ShowPreview") == nil ? true : d.bool(forKey:"ShowPreview")
        pausePreviewWhenInactive = d.object(forKey:"PausePreviewWhenInactive") == nil ? true : d.bool(forKey:"PausePreviewWhenInactive")
        zoomStopCount = d.object(forKey:"ZoomStopCount") == nil ? 19 : max(2,min(91,d.integer(forKey:"ZoomStopCount")))
    }

    func saveSettings() {
        let d = UserDefaults.standard
        d.set(useLogitechMotionControl, forKey:"UseLogitechMotionControl")
        d.set(max(30,min(500,motorIntervalTimer)), forKey:"MotorIntervalTimer")
        d.set(deviceFilter, forKey:"DeviceFilter"); d.set(movementSpeed, forKey:"MovementSpeed")
    }
}
