import SwiftUI
import AppKit

@main
struct PTZControlMacApp: App {
    @NSApplicationDelegateAdaptor(MenuBarAppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

/// Retains the status item and windows for the entire application lifetime.
@MainActor
final class MenuBarAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let camera = CameraController()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        item.button?.image = Self.menuIcon()
        item.button?.toolTip = "PTZ Control"
        item.button?.setAccessibilityLabel("PTZ Control")
        item.button?.target = self
        item.button?.action = #selector(toggleControls)
        popover.behavior = .transient
        popover.delegate = self
        let controls = NSHostingController(rootView:
            ContentView(openSettings: { [weak self] in self?.showSettings() })
                .environmentObject(camera))
        controls.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controls
        camera.discoverCameras()
        // Make the menu-bar app and hardware-free entry point discoverable on launch.
        DispatchQueue.main.async { [weak self] in self?.toggleControls() }
    }

    @objc private func toggleControls() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        camera.refreshZoom()
    }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 660),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "PTZ Control Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView:
                SettingsView(onDone: { [weak self] in self?.settingsWindow?.close() })
                    .environmentObject(camera))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func popoverDidClose(_ notification: Notification) { camera.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { camera.shutdown() }

    /// Template artwork: macOS supplies white in a dark menu bar and black in a light one.
    private static func menuIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            NSColor.black.setStroke()
            let body = NSBezierPath(roundedRect: NSRect(x: 5, y: 5, width: 10, height: 10), xRadius: 2, yRadius: 2)
            body.lineWidth = 1.4; body.stroke()
            let lens = NSBezierPath(ovalIn: NSRect(x: 7.3, y: 7.3, width: 5.4, height: 5.4))
            lens.lineWidth = 1.2; lens.stroke()
            let arrows = NSBezierPath()
            for angle in [0.0, Double.pi / 2, Double.pi, 3 * Double.pi / 2] {
                func point(_ x: Double, _ y: Double) -> NSPoint {
                    NSPoint(x: 10 + x * cos(angle) - y * sin(angle), y: 10 + x * sin(angle) + y * cos(angle))
                }
                arrows.move(to: point(6.5, 0)); arrows.line(to: point(9, 0))
                arrows.move(to: point(7.4, -1.6)); arrows.line(to: point(9, 0)); arrows.line(to: point(7.4, 1.6))
            }
            arrows.lineWidth = 1.2; arrows.lineCapStyle = .round; arrows.lineJoinStyle = .round; arrows.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
