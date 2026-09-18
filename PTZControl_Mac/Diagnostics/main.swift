import Foundation
let arguments = Set(CommandLine.arguments.dropFirst())
let cameras = CC3000eController.discover().filter { $0.product == 0x0848 }
guard cameras.count == 1 else {
    print("Expected exactly one CC3000e (046d:0848); found \(cameras.count). No commands sent.")
    exit(1)
}
let camera = CC3000eController()
do {
    try camera.connect(cameras[0])
    for state in camera.readImageControls() {
        print("IMAGE \(state.control.title): current=\(state.current) range=\(state.minimum)...\(state.maximum) step=\(state.resolution) writable=\(state.writable) default=\(String(describing: state.defaultValue))")
    }
    // Default is read-only. Each optional movement must be explicitly requested.
    if arguments.contains("--zoom-in") { try camera.zoom(.in) }
    if arguments.contains("--zoom-out") { try camera.zoom(.out) }
    if arguments.contains("--pan-right") { try camera.pan(.right,milliseconds:70,preferLogitech:false) }
    if arguments.contains("--pan-left") { try camera.pan(.left,milliseconds:70,preferLogitech:false) }
    if arguments.contains("--tilt-up") { try camera.tilt(.up,milliseconds:70,preferLogitech:false) }
    if arguments.contains("--tilt-down") { try camera.tilt(.down,milliseconds:70,preferLogitech:false) }
    if arguments.contains("--home") { try camera.home() }
    if arguments.contains("--stop") { try camera.stop() }
    camera.disconnect()
} catch {
    print("ERROR: \(error.localizedDescription)"); camera.disconnect(); exit(1)
}
