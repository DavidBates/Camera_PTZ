import Foundation

struct ZoomState: Equatable, Sendable {
    let current: Int
    let minimum: Int
    let maximum: Int
    let resolution: Int
    var label: String { String(format: "%.2f×", Double(current) / Double(max(1, minimum))) }
    func clamped(_ value: Int) -> Int {
        let limited = min(maximum, max(minimum, value))
        let index = Int((Double(limited - minimum) / Double(resolution)).rounded())
        return min(minimum + (maximum - minimum) / resolution * resolution, minimum + index * resolution)
    }
    func stops(count: Int) -> [Int] {
        guard maximum > minimum, resolution > 0 else { return [minimum] }
        let steps = (maximum - minimum) / resolution
        guard steps > 0 else { return [minimum] }
        let intervals = min(steps, max(1, min(90, count - 1)))
        return (0...intervals).map { minimum + Int((Double($0 * steps) / Double(intervals)).rounded()) * resolution }
    }
    func adjacent(direction: ZoomDirection, stopCount: Int) -> Int {
        let values = stops(count: stopCount)
        return direction == .in ? (values.first { $0 > current } ?? maximum) : (values.last { $0 < current } ?? minimum)
    }
}
