import SwiftUI

// MARK: - Aspect Guide (Always Visible)

struct AspectGuideView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        LabeledContent("Aspect") {
            HStack(spacing: 3) {
                Button {
                    appState.showAspectRatioGuide = nil
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24)
                }
                .buttonStyle(.bordered)
                .tint(appState.showAspectRatioGuide == nil ? .accentColor : .secondary)

                ForEach(AspectRatioGuide.allCases) { guide in
                    Button {
                        appState.showAspectRatioGuide = guide
                    } label: {
                        Text(guide.rawValue)
                            .frame(minWidth: 24)
                    }
                    .buttonStyle(.bordered)
                    .tint(appState.showAspectRatioGuide == guide ? .yellow : .secondary)
                }
            }
            .controlSize(.small)
        }
    }
}
