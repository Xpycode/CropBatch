import Foundation
import AppKit

/// Handles command-line interface for batch cropping
struct CLIHandler {
    struct CLIOptions {
        var inputPaths: [String] = []
        var outputDir: String?
        var cropTop: Int = 0
        var cropBottom: Int = 0
        var cropLeft: Int = 0
        var cropRight: Int = 0
        var format: ExportFormat = .png
        var quality: Double = 0.9
        var suffix: String = "_cropped"
        var help: Bool = false
        var version: Bool = false
    }

    /// Check if the app was launched with CLI arguments
    static func hasArguments() -> Bool {
        let args = CommandLine.arguments
        // Skip first arg (executable path) and filter system/Xcode debug args
        let systemPrefixes = ["-NS", "-Apple", "-com.apple.", "-CF"]
        let systemValues = ["YES", "NO", "true", "false", "1", "0"]

        let relevantArgs = args.dropFirst().filter { arg in
            // Skip args that start with system prefixes
            if systemPrefixes.contains(where: { arg.hasPrefix($0) }) {
                return false
            }
            // Skip common boolean values (often follow system flags)
            if systemValues.contains(arg) {
                return false
            }
            return true
        }
        return !relevantArgs.isEmpty
    }

    /// Parse command line arguments
    static func parseArguments() -> CLIOptions {
        var options = CLIOptions()
        let args = Array(CommandLine.arguments.dropFirst())

        var i = 0
        while i < args.count {
            let arg = args[i]

            switch arg {
            case "-h", "--help":
                options.help = true
            case "-v", "--version":
                options.version = true
            case "-o", "--output":
                if i + 1 < args.count {
                    i += 1
                    options.outputDir = args[i]
                }
            case "-t", "--top":
                if i + 1 < args.count {
                    i += 1
                    options.cropTop = Int(args[i]) ?? 0
                }
            case "-b", "--bottom":
                if i + 1 < args.count {
                    i += 1
                    options.cropBottom = Int(args[i]) ?? 0
                }
            case "-l", "--left":
                if i + 1 < args.count {
                    i += 1
                    options.cropLeft = Int(args[i]) ?? 0
                }
            case "-r", "--right":
                if i + 1 < args.count {
                    i += 1
                    options.cropRight = Int(args[i]) ?? 0
                }
            case "-f", "--format":
                if i + 1 < args.count {
                    i += 1
                    let formatStr = args[i].lowercased()
                    switch formatStr {
                    case "png": options.format = .png
                    case "jpg", "jpeg": options.format = .jpeg
                    case "heic": options.format = .heic
                    case "tiff": options.format = .tiff
                    default: break
                    }
                }
            case "-q", "--quality":
                if i + 1 < args.count {
                    i += 1
                    if let q = Double(args[i]) {
                        options.quality = min(1.0, max(0.1, q / 100.0))
                    }
                }
            case "-s", "--suffix":
                if i + 1 < args.count {
                    i += 1
                    options.suffix = args[i]
                }
            default:
                // Treat as input file path, but skip system args
                let systemPrefixes = ["-NS", "-Apple", "-com.apple.", "-CF"]
                let systemValues = ["YES", "NO", "true", "false", "1", "0"]
                if !arg.hasPrefix("-") &&
                   !systemPrefixes.contains(where: { arg.hasPrefix($0) }) &&
                   !systemValues.contains(arg) {
                    options.inputPaths.append(arg)
                }
            }
            i += 1
        }

        return options
    }

    /// Print help message
    static func printHelp() {
        let help = """
        CropBatch - Batch image cropping tool

        USAGE:
            CropBatch [OPTIONS] <INPUT_FILES...>

        OPTIONS:
            -h, --help              Show this help message
            -v, --version           Show version information
            -o, --output <DIR>      Output directory (default: same as input)
            -t, --top <PIXELS>      Crop from top edge
            -b, --bottom <PIXELS>   Crop from bottom edge
            -l, --left <PIXELS>     Crop from left edge
            -r, --right <PIXELS>    Crop from right edge
            -f, --format <FORMAT>   Output format: png, jpg, heic, tiff (default: png)
            -q, --quality <1-100>   JPEG/HEIC quality percentage (default: 90)
            -s, --suffix <SUFFIX>   Filename suffix (default: _cropped)

        EXAMPLES:
            CropBatch -t 50 -b 50 image.png
            CropBatch -t 60 -b 34 -f jpg -q 85 *.png
            CropBatch -t 100 -o ./output/ screenshots/*.png

        """
        print(help)
    }

    /// Print version
    static func printVersion() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        print("CropBatch version \(version) (\(build))")
    }

    /// Run CLI mode
    @MainActor
    static func run() async -> Int32 {
        let options = parseArguments()

        if options.help {
            printHelp()
            return 0
        }

        if options.version {
            printVersion()
            return 0
        }

        // Expand glob patterns and resolve paths
        var urls: [URL] = []
        for path in options.inputPaths {
            let expandedPath = (path as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expandedPath)

            // Check if file exists
            if FileManager.default.fileExists(atPath: url.path) {
                urls.append(url)
            } else {
                print("Warning: File not found: \(path)")
            }
        }

        if urls.isEmpty {
            print("Error: No input files specified. Use --help for usage.")
            return 1
        }

        // Create settings
        let cropSettings = CropSettings(
            cropTop: options.cropTop,
            cropBottom: options.cropBottom,
            cropLeft: options.cropLeft,
            cropRight: options.cropRight
        )

        var exportSettings = ExportSettings(
            format: options.format,
            quality: options.quality,
            suffix: options.suffix
        )

        if let outputDir = options.outputDir {
            let expandedPath = (outputDir as NSString).expandingTildeInPath
            let outputURL = URL(fileURLWithPath: expandedPath)

            // Create output directory if needed
            try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            exportSettings.outputDirectory = .custom(outputURL)
        }

        // Load images
        let items = urls.compactMap { url -> ImageItem? in
            guard let image = NSImage(contentsOf: url) else {
                print("Warning: Could not load image: \(url.lastPathComponent)")
                return nil
            }
            return ImageItem(url: url, originalImage: image)
        }

        if items.isEmpty {
            print("Error: No valid images to process")
            return 1
        }

        print("Processing \(items.count) image(s)...")

        // Process images
        do {
            let outputURLs = try await ImageCropService.batchCrop(
                items: items,
                cropSettings: cropSettings,
                exportSettings: exportSettings
            ) { progress in
                // Progress is handled silently in CLI mode
            }

            print("Successfully exported \(outputURLs.count) image(s):")
            for url in outputURLs {
                print("  → \(url.lastPathComponent)")
            }
            return 0
        } catch {
            print("Error: \(error.localizedDescription)")
            return 1
        }
    }
}
