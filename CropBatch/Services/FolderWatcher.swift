import Foundation
import AppKit
import UserNotifications

@MainActor
@Observable
final class FolderWatcher {
    static let shared = FolderWatcher()

    // Configuration
    var isWatching = false
    var watchedFolder: URL?
    var outputFolder: URL?
    var cropSettings = CropSettings()
    var exportSettings = ExportSettings()
    var usePreset: CropPreset?

    // State
    var processedCount = 0
    var lastProcessedFile: String?
    var errorMessage: String?

    // Internal
    private var fileDescriptor: CInt = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var knownFiles: Set<String> = []

    private init() {}

    // MARK: - Watch Control

    func startWatching(folder: URL, output: URL) {
        guard !isWatching else { return }

        watchedFolder = folder
        outputFolder = output
        errorMessage = nil

        // Get initial list of files
        knownFiles = Set(existingFiles(in: folder))

        // Open folder for monitoring (store in local var first for safe cleanup)
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            errorMessage = "Cannot access folder"
            return
        }

        // Create dispatch source for file system events
        // Use main queue for thread safety with @MainActor class
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.checkForNewFiles()
            }
        }

        // Cancel handler runs on the dispatch source's queue (.main)
        // Capture fd directly to ensure proper cleanup even if self is deallocated
        source.setCancelHandler { [weak self] in
            close(fd)  // Always close the captured fd
            Task { @MainActor in
                self?.fileDescriptor = -1
            }
        }

        // Only store after successful setup
        fileDescriptor = fd
        dispatchSource = source
        source.resume()
        isWatching = true
    }

    func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
        isWatching = false
        knownFiles.removeAll()
    }

    // MARK: - File Processing

    private func checkForNewFiles() {
        guard let folder = watchedFolder else { return }

        let currentFiles = Set(existingFiles(in: folder))
        let newFiles = currentFiles.subtracting(knownFiles)

        for filename in newFiles {
            let url = folder.appendingPathComponent(filename)
            processNewFile(url)
        }

        knownFiles = currentFiles
    }

    private func existingFiles(in folder: URL) -> [String] {
        let supportedExtensions = ["png", "jpg", "jpeg", "heic", "tiff", "bmp"]
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return contents.filter { filename in
            let ext = (filename as NSString).pathExtension.lowercased()
            return supportedExtensions.contains(ext)
        }
    }

    private func processNewFile(_ url: URL) {
        guard let outputFolder = outputFolder else { return }

        // Small delay to ensure file is fully written
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }

            do {
                // Load image
                guard let image = NSImage(contentsOf: url) else {
                    self.errorMessage = "Cannot read: \(url.lastPathComponent)"
                    return
                }

                // Use preset settings if available, otherwise use configured settings
                let settings = self.usePreset?.cropSettings ?? self.cropSettings

                // Crop
                let cropped = try ImageCropService.crop(image, with: settings)

                // Determine output URL
                var exportSettings = self.exportSettings
                exportSettings.outputDirectory = .custom(outputFolder)
                let outputURL = exportSettings.outputURL(for: url)

                // Save
                let format = exportSettings.preserveOriginalFormat
                    ? self.formatFromExtension(url.pathExtension)
                    : exportSettings.format.utType

                try ImageCropService.save(cropped, to: outputURL, format: format, quality: exportSettings.quality)

                self.processedCount += 1
                self.lastProcessedFile = url.lastPathComponent
                self.errorMessage = nil

                // Show notification
                self.showNotification(for: url.lastPathComponent)

            } catch {
                self.errorMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    private func formatFromExtension(_ ext: String) -> UTType {
        switch ext.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "heic": return .heic
        case "tiff", "tif": return .tiff
        default: return .png
        }
    }

    private func showNotification(for filename: String) {
        let content = UNMutableNotificationContent()
        content.title = "Screenshot Cropped"
        content.body = filename

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - UTType import
import UniformTypeIdentifiers
