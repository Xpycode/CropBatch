import SwiftUI

/// Native NSSegmentedControl — replaces SwiftUI Picker(.segmented).
struct AppKitSegmented<T: Hashable>: NSViewRepresentable {
    let items: [(title: String, value: T)]
    @Binding var selection: T

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: items.map(\.title),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.changed)
        )
        control.segmentDistribution = .fillEqually
        if let idx = items.firstIndex(where: { $0.value == selection }) {
            control.selectedSegment = idx
        }
        return control
    }

    func updateNSView(_ nsView: NSSegmentedControl, context: Context) {
        if let idx = items.firstIndex(where: { $0.value == selection }) {
            nsView.selectedSegment = idx
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject {
        let parent: AppKitSegmented
        init(parent: AppKitSegmented) { self.parent = parent }
        @objc func changed(_ sender: NSSegmentedControl) {
            let idx = sender.selectedSegment
            if idx >= 0 && idx < parent.items.count {
                parent.selection = parent.items[idx].value
            }
        }
    }
}
