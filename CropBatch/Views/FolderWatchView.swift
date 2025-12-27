import SwiftUI
import UniformTypeIdentifiers

struct FolderWatchView: View {
    @State private var watcher = FolderWatcher.shared
    @State private var showInputPicker = false
    @State private var showOutputPicker = false
    @State private var presetManager = PresetManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with status
            HStack {
                Image(systemName: watcher.isWatching ? "eye.circle.fill" : "eye.slash.circle")
                    .foregroundStyle(watcher.isWatching ? .green : .secondary)

                Text("Folder Watch")
                    .font(.headline)

                Spacer()

                if watcher.isWatching {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.2)))
                }
            }

            // Input folder
            FolderPickerRow(
                label: "Watch folder",
                folder: watcher.watchedFolder,
                showPicker: $showInputPicker
            )

            // Output folder
            FolderPickerRow(
                label: "Output folder",
                folder: watcher.outputFolder,
                showPicker: $showOutputPicker
            )

            // Preset selection
            HStack {
                Text("Apply preset")
                    .font(.callout)

                Spacer()

                Menu {
                    Button("Use current crop settings") {
                        watcher.usePreset = nil
                    }

                    Divider()

                    ForEach(presetManager.allPresets) { preset in
                        Button {
                            watcher.usePreset = preset
                            watcher.cropSettings = preset.cropSettings
                        } label: {
                            Label(preset.name, systemImage: preset.icon)
                        }
                    }
                } label: {
                    HStack {
                        Text(watcher.usePreset?.name ?? "Current settings")
                            .font(.caption)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .controlBackgroundColor)))
                }
                .buttonStyle(.plain)
            }

            // Start/Stop button
            if watcher.isWatching {
                Button {
                    watcher.stopWatching()
                } label: {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Stop Watching")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    startWatching()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Watching")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
            }

            // Status display
            if watcher.isWatching {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Processed:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(watcher.processedCount)")
                            .font(.caption.monospacedDigit())
                    }

                    if let lastFile = watcher.lastProcessedFile {
                        HStack {
                            Text("Last:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(lastFile)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(0.1)))
            }

            // Error display
            if let error = watcher.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.1)))
            }
        }
        .fileImporter(
            isPresented: $showInputPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                watcher.watchedFolder = url
            }
        }
        .fileImporter(
            isPresented: $showOutputPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                watcher.outputFolder = url
            }
        }
    }

    private var canStart: Bool {
        watcher.watchedFolder != nil && watcher.outputFolder != nil
    }

    private func startWatching() {
        guard let input = watcher.watchedFolder,
              let output = watcher.outputFolder else { return }
        watcher.startWatching(folder: input, output: output)
    }
}

struct FolderPickerRow: View {
    let label: String
    let folder: URL?
    @Binding var showPicker: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)

            Spacer()

            Button {
                showPicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption)
                    Text(folder?.lastPathComponent ?? "Choose...")
                        .font(.caption)
                        .lineLimit(1)
                        .frame(maxWidth: 100)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    FolderWatchView()
        .frame(width: 280)
        .padding()
}
