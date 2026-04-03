import SwiftUI

// MARK: - Transform Row

struct TransformRowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 8) {
            Label("Transform", systemImage: "rotate.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Rotate buttons
            Button {
                appState.rotateActiveImage(clockwise: false)
            } label: {
                Image(systemName: "rotate.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.activeImage == nil)
            .help("Rotate Left (⌘[)")

            Button {
                appState.rotateActiveImage(clockwise: true)
            } label: {
                Image(systemName: "rotate.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.activeImage == nil)
            .help("Rotate Right (⌘])")

            Divider()
                .frame(height: 20)

            // Flip buttons
            Button {
                appState.flipActiveImage(horizontal: true)
            } label: {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.activeImage == nil)
            .help("Flip Horizontal")

            Button {
                appState.flipActiveImage(horizontal: false)
            } label: {
                Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.activeImage == nil)
            .help("Flip Vertical")

            // Transform reset button - always visible, disabled when no transform
            Button {
                appState.resetActiveImageTransform()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundColor(appState.activeImageTransform.isIdentity ? Color.secondary : Color.orange)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.activeImage == nil || appState.activeImageTransform.isIdentity)
            .help("Reset Transform")
        }
    }
}
