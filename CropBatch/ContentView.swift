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
                .frame(width: 420)
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
            // Center: Zoom controls only
            ToolbarItem(placement: .principal) {
                if !appState.images.isEmpty {
                    Picker("Zoom", selection: Binding(
                        get: { appState.zoomMode },
                        set: { appState.zoomMode = $0 }
                    )) {
                        ForEach(ZoomMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
            }

            // Right side: buttons only
            ToolbarItemGroup(placement: .primaryAction) {
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

    private func zoomInfoText(for image: ImageItem) -> String {
        let scale = calculateZoomScale(for: image)
        let percentage = Int(scale * 100)
        return "\(percentage)%  \(Int(image.originalSize.width))×\(Int(image.originalSize.height))"
    }

    private func calculateZoomScale(for image: ImageItem) -> CGFloat {
        // Approximate scale based on typical view size
        // This is a simplified calculation for display purposes
        let availableWidth: CGFloat = 500
        let availableHeight: CGFloat = 400

        switch appState.zoomMode {
        case .actualSize:
            return 1.0
        case .fit:
            let scaleX = availableWidth / image.originalSize.width
            let scaleY = availableHeight / image.originalSize.height
            return min(scaleX, scaleY, 1.0)
        case .fitWidth:
            return availableWidth / image.originalSize.width
        case .fitHeight:
            return availableHeight / image.originalSize.height
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

    // Collapsed state persistence
    @AppStorage("sidebar.presetsExpanded") private var presetsExpanded = true
    @AppStorage("sidebar.cropExpanded") private var cropExpanded = true
    @AppStorage("sidebar.blurExpanded") private var blurExpanded = true
    @AppStorage("sidebar.exportExpanded") private var exportExpanded = true
    @AppStorage("sidebar.infoExpanded") private var infoExpanded = true
    @AppStorage("sidebar.autoProcessExpanded") private var autoProcessExpanded = false
    @AppStorage("sidebar.shortcutsExpanded") private var shortcutsExpanded = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Resolution warning (always visible if needed)
                if appState.hasResolutionMismatch {
                    ResolutionWarningView()
                        .padding()
                    Divider()
                }

                // Crop Presets
                CollapsibleSection(title: "Crop Presets", icon: "square.stack", isExpanded: $presetsExpanded) {
                    PresetPickerView()
                }

                // Crop Settings
                CollapsibleSection(title: "Crop Settings", icon: "crop", isExpanded: $cropExpanded) {
                    CropSettingsView()
                }

                // Blur/Redact Tool
                CollapsibleSection(title: "Blur / Redact", icon: "eye.slash", isExpanded: $blurExpanded) {
                    BlurToolSettings()
                }

                // Export Settings
                CollapsibleSection(title: "Export Settings", icon: "square.and.arrow.down", isExpanded: $exportExpanded) {
                    ExportSettingsView()
                }

                // Info & Export
                CollapsibleSection(title: "Info & Export", icon: "info.circle", isExpanded: $infoExpanded) {
                    VStack(spacing: 12) {
                        ImageInfoView()
                        ActionButtonsView()
                    }
                }

                // Auto-Processing
                CollapsibleSection(title: "Auto-Processing", icon: "eye", isExpanded: $autoProcessExpanded) {
                    FolderWatchView()
                }

                // Keyboard Shortcuts
                CollapsibleSection(title: "Keyboard Shortcuts", icon: "keyboard", isExpanded: $shortcutsExpanded) {
                    KeyboardShortcutsContentView()
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Collapsible Section

struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Content
            if isExpanded {
                content()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            Divider()
        }
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

struct KeyboardShortcutsContentView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column: Navigation & Crop
            VStack(alignment: .leading, spacing: 4) {
                Text("Navigation & Crop")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)

                ShortcutRow(keys: "←  →", description: "Navigate")
                ShortcutRow(keys: "⇧ Arrow", description: "Adjust crop")
                ShortcutRow(keys: "⇧⌥ Arrow", description: "Uncrop")
                ShortcutRow(keys: "⇧⌃ Arrow", description: "×10 adjust")
                ShortcutRow(keys: "⌃ Drag", description: "Snap grid")
                ShortcutRow(keys: "Dbl-click", description: "Reset")
            }
            .frame(width: 190, alignment: .leading)

            Divider()
                .padding(.horizontal, 8)

            // Right column: Zoom
            VStack(alignment: .leading, spacing: 4) {
                Text("Zoom")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 2)

                ZoomShortcutRow(keys: "⌘1", description: "100%")
                ZoomShortcutRow(keys: "⌘2", description: "Fit")
                ZoomShortcutRow(keys: "⌘3", description: "Width")
                ZoomShortcutRow(keys: "⌘4", description: "Height")
            }

            Spacer()
        }
    }
}

struct ShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 70, alignment: .leading)

            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct ZoomShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 24, alignment: .leading)

            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .frame(width: 1000, height: 700)
}
