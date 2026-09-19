import Foundation

@main struct DemoTests {
    @MainActor static func main() async {
        let camera = CameraController()
        camera.discoverCameras()
        while camera.isBusy { try? await Task.sleep(for: .milliseconds(20)) }
        guard camera.cameras.isEmpty else { fatalError("Unplug supported cameras for this integration test") }
        assert(!camera.isConnected && !camera.canControl)
        assert(camera.status.contains("No suitable camera"))
        camera.stop()
        camera.startDemo()
        assert(camera.isDemoMode && camera.canControl && !camera.isConnected)
        camera.pan(.right); camera.tilt(.up)
        assert(camera.demoPan > 0 && camera.demoTilt > 0)
        for _ in 0..<20 { camera.pan(.right) }
        assert(camera.demoPan == 1)
        camera.setZoom(500)
        assert(camera.displayedZoom == 500)
        camera.setImage(.brightness, value: 255)
        assert(camera.imageControls.first { $0.control == .brightness }?.current == 255)
        camera.restoreImageDefaults()
        assert(camera.imageControls.first { $0.control == .brightness }?.current == 128)
        assert(camera.displayedZoom == 500)
        camera.gotoHome()
        assert(camera.demoPan == 0 && camera.demoTilt == 0 && camera.displayedZoom == 100)
        camera.stop(); camera.probeCamera(); camera.refreshZoom(); camera.refreshImageControls()
        assert(!camera.lastActionFailed && !camera.isBusy)
        camera.discoverCameras()
        assert(!camera.isDemoMode && camera.currentZoom == nil && camera.imageControls.isEmpty)
        while camera.isBusy { try? await Task.sleep(for: .milliseconds(20)) }
        assert(!camera.canControl && camera.status.contains("No suitable camera"))
        camera.shutdown()
        print("PASS: no-camera discovery, demo controls, bounds, defaults, Home, and exit/rescan")
    }
}
