import Foundation

enum ImageControl: String, CaseIterable, Identifiable, Sendable {
    case brightness, contrast, saturation, whiteBalance, autoWhiteBalance, focus, autoFocus, antiFlicker
    var id: String { rawValue }
    var title: String {
        switch self {
        case .brightness: return "Brightness"
        case .contrast: return "Contrast"
        case .saturation: return "Color intensity"
        case .whiteBalance: return "White balance"
        case .autoWhiteBalance: return "Auto white balance"
        case .focus: return "Focus"
        case .autoFocus: return "Autofocus"
        case .antiFlicker: return "Anti-flicker"
        }
    }
    var terminal: Bool { self == .focus || self == .autoFocus }
    var selector: UInt8 {
        switch self {
        case .brightness: return 2
        case .contrast: return 3
        case .saturation: return 7
        case .whiteBalance: return 10
        case .autoWhiteBalance: return 11
        case .focus: return 6
        case .autoFocus: return 8
        case .antiFlicker: return 5
        }
    }
    var bit: Int {
        switch self {
        case .brightness: return 0
        case .contrast: return 1
        case .saturation: return 3
        case .whiteBalance: return 6
        case .autoWhiteBalance: return 12
        case .focus: return 5
        case .autoFocus: return 17
        case .antiFlicker: return 10
        }
    }
    var isAuto: Bool { self == .autoFocus || self == .autoWhiteBalance }
    var length: Int { isAuto || self == .antiFlicker ? 1 : 2 }
    var autoPartner: ImageControl? { self == .focus ? .autoFocus : self == .whiteBalance ? .autoWhiteBalance : nil }
    func decode(_ bytes: [UInt8]) -> Int {
        if length == 1 { return Int(bytes[0]) }
        return self == .brightness ? Int(Int16(bitPattern: bytes.le16(0))) : Int(bytes.le16(0))
    }
    func encode(_ value: Int) -> [UInt8] {
        if length == 1 { return [UInt8(clamping: value)] }
        let bits = UInt16(truncatingIfNeeded: value)
        return [UInt8(bits & 255), UInt8(bits >> 8)]
    }
}
struct ImageControlState: Identifiable, Sendable {
    let control: ImageControl
    var id: ImageControl { control }
    let current: Int
    let minimum: Int
    let maximum: Int
    let resolution: Int
    let defaultValue: Int?
    let writable: Bool
    func clamped(_ value: Int) -> Int {
        minimum + (max(minimum, min(maximum, value)) - minimum) / max(1, resolution) * max(1, resolution)
    }
}
