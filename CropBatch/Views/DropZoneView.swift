import SwiftUI

struct DropZoneView: View {
    @Environment(AppState.self) private var appState
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeating, isActive: isTargeted)

            VStack(spacing: 8) {
                Text("Drop Screenshots Here")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("or click to browse")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                appState.showImportPanel()
            } label: {
                Label("Import Images", systemImage: "folder")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Supports PNG, JPEG, HEIC, TIFF")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .foregroundStyle(isTargeted ? Color.blue : Color.gray.opacity(0.3))
                .padding(20)
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        Task { @MainActor in
                            appState.addImages(from: [url])
                        }
                    }
                }
                handled = true
            }
        }

        return handled
    }
}

#Preview {
    DropZoneView()
        .environment(AppState())
        .frame(width: 600, height: 400)
}
