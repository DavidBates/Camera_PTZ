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
    func stop() throws
    func home() throws
    func readImageControls() -> [ImageControlState]
    func setImageControl(_ control: ImageControl, value: Int) throws
    func restoreImageDefaults() throws
    func diagnosticReport() -> String
}
