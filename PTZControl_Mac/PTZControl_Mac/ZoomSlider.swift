import SwiftUI
import AppKit

struct ZoomSlider: NSViewRepresentable {
    let stops: [Int]
    let value: Int
    let enabled: Bool
    let onChange: (Int) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.isContinuous = true
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.setAccessibilityLabel("Zoom level")
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        slider.minValue = 0; slider.maxValue = Double(max(1, stops.count - 1))
        slider.numberOfTickMarks = stops.count
        slider.isEnabled = enabled && stops.count > 1
        let nearest = stops.indices.min { abs(stops[$0] - value) < abs(stops[$1] - value) } ?? 0
        slider.doubleValue = Double(nearest)
    }
    final class Coordinator: NSObject {
        var parent: ZoomSlider
        init(_ parent: ZoomSlider) { self.parent = parent }
        @objc func changed(_ slider: NSSlider) {
            let index = Int(slider.doubleValue.rounded())
            if parent.stops.indices.contains(index) { parent.onChange(parent.stops[index]) }
        }
    }
}
