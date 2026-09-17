import Foundation

enum PanDirection { case left, right }
enum TiltDirection { case up, down }
enum ZoomDirection { case `in`, out }
struct Camera: Identifiable, Equatable, Sendable {
    let id: UInt64
    let name: String
    let vendor: UInt16
    let product: UInt16
    let location: UInt32
}
protocol PTZCameraController: AnyObject, Sendable {
    func connect(_ camera: Camera) throws
    func disconnect()
    func pan(_ direction: PanDirection, milliseconds: Int, preferLogitech: Bool) throws
    func tilt(_ direction: TiltDirection, milliseconds: Int, preferLogitech: Bool) throws
    func zoom(_ direction: ZoomDirection) throws
    func readZoom() throws -> ZoomState
    func setZoom(_ value: Int) throws
    var supportedMovementSpeeds: ClosedRange<Int>? { get }
    var experimentalHardwarePresets: Bool { get set }
    func stop() throws
    func home() throws
    func savePreset(_ slot: Int) throws
    func recallPreset(_ slot: Int) throws
    func diagnosticReport() -> String
}

protocol PTZPresetStore {
    func save(_ data: Data, key: String)
    func load(key: String) -> Data?
}
struct DefaultsPresetStore: PTZPresetStore {
    func save(_ data: Data, key: String) { UserDefaults.standard.set(data, forKey: key) }
    func load(key: String) -> Data? { UserDefaults.standard.data(forKey: key) }
}
