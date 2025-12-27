import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        HStack(spacing: 0) {
            // Main content area (left)
            if appState.images.isEmpty {
                DropZoneView()
            } else {
                VStack(spacing: 0) {
                    // Main crop editor
                    if let activeImage = appState.activeImage {
                        CropEditorView(image: activeImage)
                    }

                    // Thumbnail strip at bottom
                    ThumbnailStripView()
                }
            }

            Divider()

            // Sidebar (right)
            SidebarView()
                .frame(width: 260)
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
        .toolbar {
            ToolbarItemGroup {
                if !appState.images.isEmpty {
                    Button {
                        appState.showFileImporter = true
                    } label: {
                        Label("Add Images", systemImage: "plus")
                    }

                    Button(role: .destructive) {
                        appState.clearAll()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                }
            }
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
        VStack(spacing: 0) {
            // Top section with settings
            List {
                // Resolution warning
                if appState.hasResolutionMismatch {
                    Section {
                        ResolutionWarningView()
                    }
                }

                Section("Crop Settings") {
                    CropSettingsView()
                }

                Section("Export Settings") {
                    ExportSettingsView()
                }

                Section("Info") {
                    ImageInfoView()
                }

                Section {
                    ActionButtonsView()
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Keyboard shortcuts at bottom
            KeyboardShortcutsView()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ResolutionWarningView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Resolution Mismatch", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.yellow)

            if let majority = appState.majorityResolution {
                Text("\(appState.mismatchedImages.count) image(s) differ from the majority resolution of \(Int(majority.width))×\(Int(majority.height))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // List mismatched files
            VStack(alignment: .leading, spacing: 4) {
                ForEach(appState.mismatchedImages.prefix(3)) { item in
                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.caption2)
                        Text(item.filename)
                            .font(.caption2)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(item.originalSize.width))×\(Int(item.originalSize.height))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if appState.mismatchedImages.count > 3 {
                    Text("...and \(appState.mismatchedImages.count - 3) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }
}

struct ImageInfoView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Images:")
                Spacer()
                Text("\(appState.images.count)")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)

            if let majority = appState.majorityResolution {
                HStack {
                    Text("Resolution:")
                    Spacer()
                    Text("\(Int(majority.width)) × \(Int(majority.height))")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            if appState.cropSettings.hasAnyCrop, let majority = appState.majorityResolution {
                let newSize = appState.cropSettings.croppedSize(from: majority)
                HStack {
                    Text("Output size:")
                    Spacer()
                    Text("\(Int(newSize.width)) × \(Int(newSize.height))")
                        .foregroundStyle(.green)
                }
                .font(.callout)
            }
        }
    }
}

struct KeyboardShortcutsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard Shortcuts")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ShortcutRow(keys: "← →", description: "Navigate images")
                ShortcutRow(keys: "⇧ + arrows", description: "Adjust crop edges")
                ShortcutRow(keys: "⇧⌥ + arrows", description: "Uncrop (reverse)")
                ShortcutRow(keys: "⇧⌃ + arrows", description: "Adjust by 10px")
                ShortcutRow(keys: "⌃ + drag", description: "Snap to 10px grid")
                ShortcutRow(keys: "Double-click", description: "Reset edge to 0")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack(spacing: 8) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 90, alignment: .leading)

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .frame(width: 1000, height: 700)
}
