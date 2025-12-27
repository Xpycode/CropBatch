import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            if appState.images.isEmpty {
                DropZoneView()
            } else {
                ImageGridView()
            }
        }
        .fileImporter(
            isPresented: $state.showFileImporter,
            allowedContentTypes: [.png, .jpeg, .heic, .tiff, .bmp],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let accessibleURLs = urls.compactMap { url -> URL? in
                    guard url.startAccessingSecurityScopedResource() else { return nil }
                    return url
                }
                appState.addImages(from: accessibleURLs)
                accessibleURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            case .failure(let error):
                print("File import error: \(error.localizedDescription)")
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
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

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        List {
            Section("Crop Settings") {
                CropSettingsView()
            }

            Section("Images (\(appState.images.count))") {
                if appState.images.isEmpty {
                    Text("No images loaded")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(appState.images) { image in
                        ImageRowView(item: image)
                    }
                }
            }

            Section {
                ActionButtonsView()
            }
        }
        .listStyle(.sidebar)
    }
}

struct ImageRowView: View {
    let item: ImageItem
    @Environment(AppState.self) private var appState

    var isSelected: Bool {
        appState.selectedImageIDs.contains(item.id)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: item.originalImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.callout)
                    .lineLimit(1)

                Text("\(Int(item.originalSize.width)) × \(Int(item.originalSize.height))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                appState.selectedImageIDs.remove(item.id)
            } else {
                appState.selectedImageIDs.insert(item.id)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .frame(width: 900, height: 600)
}
