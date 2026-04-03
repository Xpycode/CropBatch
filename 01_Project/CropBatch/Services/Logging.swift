import Foundation
import os

enum CropBatchLogger {
    static let ui = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.xpycode.CropBatch", category: "UI")
    static let export = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.xpycode.CropBatch", category: "Export")
    static let storage = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.xpycode.CropBatch", category: "Storage")
}
