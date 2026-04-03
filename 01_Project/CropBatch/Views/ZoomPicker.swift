import SwiftUI

// MARK: - AppKit Segmented Control (bypasses Liquid Glass)

struct ZoomPicker: NSViewRepresentable {
    @Binding var selection: ZoomMode

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentCount = ZoomMode.allCases.count
        control.segmentStyle = .texturedRounded
        control.trackingMode = .selectOne

        for (index, mode) in ZoomMode.allCases.enumerated() {
            control.setLabel(mode.rawValue, forSegment: index)
            control.setWidth(0, forSegment: index) // Auto-size
        }

        control.target = context.coordinator
        control.action = #selector(Coordinator.segmentChanged(_:))

        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        if let index = ZoomMode.allCases.firstIndex(of: selection) {
            control.selectedSegment = index
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    class Coordinator: NSObject {
        var selection: Binding<ZoomMode>

        init(selection: Binding<ZoomMode>) {
            self.selection = selection
        }

        @MainActor @objc func segmentChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            if index >= 0 && index < ZoomMode.allCases.count {
                selection.wrappedValue = ZoomMode.allCases[index]
            }
        }
    }
}
