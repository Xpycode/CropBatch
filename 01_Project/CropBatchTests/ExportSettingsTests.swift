import XCTest
import AppKit
@testable import CropBatch

final class ExportSettingsTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a temporary file on disk and returns its URL.
    /// ImageItem.init reads file size from disk, so a real file is required.
    private func makeTempFileURL(name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data().write(to: url)
        }
        return url
    }

    private func makeDummyImage() -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10))
    }

    // MARK: - RenameSettings.processPattern

    func testPatternWithName() {
        var settings = RenameSettings()
        settings.pattern = "{name}_edited"
        let result = settings.processPattern(originalName: "photo", index: 0)
        XCTAssertEqual(result, "photo_edited")
    }

    func testPatternWithCounter() {
        // startIndex=1, zeroPadding=2, index=0 → paddedCounter = "01"
        var settings = RenameSettings()
        settings.pattern = "{name}_{counter}"
        settings.startIndex = 1
        settings.zeroPadding = 2
        let result = settings.processPattern(originalName: "photo", index: 0)
        XCTAssertEqual(result, "photo_01")
    }

    func testPatternWithIndex() {
        // {index} is 1-based, so index=4 → "5"
        var settings = RenameSettings()
        settings.pattern = "img_{index}"
        let result = settings.processPattern(originalName: "anything", index: 4)
        XCTAssertEqual(result, "img_5")
    }

    // MARK: - ExportSettings.outputURL

    func testOutputURLSuffixMode() {
        var settings = ExportSettings()
        settings.renameSettings.mode = .keepOriginal
        settings.suffix = "_cropped"
        settings.format = .png

        let inputURL = URL(fileURLWithPath: "/tmp/photo.png")
        let output = settings.outputURL(for: inputURL)

        XCTAssertEqual(output.lastPathComponent, "photo_cropped.png")
        XCTAssertEqual(output.deletingLastPathComponent().path, "/tmp")
    }

    func testOutputURLPatternMode() {
        var settings = ExportSettings()
        settings.renameSettings.mode = .pattern
        settings.renameSettings.pattern = "{name}_export"
        settings.format = .png

        let inputURL = URL(fileURLWithPath: "/tmp/photo.png")
        let output = settings.outputURL(for: inputURL, index: 0)

        XCTAssertEqual(output.lastPathComponent, "photo_export.png")
    }

    func testOutputURLOverwriteMode() {
        var settings = ExportSettings()
        settings.outputDirectory = .overwriteOriginal

        let inputURL = URL(fileURLWithPath: "/tmp/photo.png")
        let output = settings.outputURL(for: inputURL)

        XCTAssertEqual(output, inputURL)
    }

    func testOutputURLGridOverload() {
        var settings = ExportSettings()
        settings.renameSettings.mode = .keepOriginal
        settings.suffix = "_cropped"
        settings.format = .png
        settings.gridSettings.namingSuffix = "_{row}_{col}"

        let inputURL = URL(fileURLWithPath: "/tmp/photo.png")
        let output = settings.outputURL(for: inputURL, index: 0, gridRow: 2, gridCol: 3)

        XCTAssertEqual(output.lastPathComponent, "photo_cropped_2_3.png")
    }

    // MARK: - ExportSettings.findBatchCollision

    func testNoBatchCollision() throws {
        var settings = ExportSettings()
        settings.renameSettings.mode = .keepOriginal
        settings.suffix = "_cropped"

        let url1 = try makeTempFileURL(name: "alpha.png")
        let url2 = try makeTempFileURL(name: "beta.png")

        let item1 = ImageItem(url: url1, originalImage: makeDummyImage())
        let item2 = ImageItem(url: url2, originalImage: makeDummyImage())

        let collision = settings.findBatchCollision(items: [item1, item2])
        XCTAssertNil(collision)
    }

    func testBatchCollisionDetected() throws {
        // Pattern mode with no counter/index token causes every item to produce the same output name
        var settings = ExportSettings()
        settings.renameSettings.mode = .pattern
        settings.renameSettings.pattern = "fixed_name"
        settings.format = .png

        let url1 = try makeTempFileURL(name: "img1.png")
        let url2 = try makeTempFileURL(name: "img2.png")

        let item1 = ImageItem(url: url1, originalImage: makeDummyImage())
        let item2 = ImageItem(url: url2, originalImage: makeDummyImage())

        let collision = settings.findBatchCollision(items: [item1, item2])
        XCTAssertNotNil(collision)
        XCTAssertEqual(collision, "fixed_name.png")
    }

    // MARK: - Lossless persistence

    func testCodableRoundTripsLossless() throws {
        var settings = ExportSettings()
        settings.format = .webp
        settings.lossless = true

        let encoded = try JSONEncoder().encode(ExportSettingsCodable(from: settings))
        let decoded = try JSONDecoder().decode(ExportSettingsCodable.self, from: encoded)

        XCTAssertTrue(decoded.toExportSettings().lossless)
    }

    func testLegacyProfileWithoutLosslessDecodesToFalse() throws {
        // Simulates a profile saved before the lossless field existed
        let legacyJSON = """
        {"format":"WebP","quality":0.9,"suffix":"_cropped","preserveOriginalFormat":false,\
        "resizeSettings":{"mode":"None","width":1920,"height":1080,"percentage":50,"maintainAspectRatio":true},\
        "renameSettings":{"mode":"Keep Original","pattern":"{name}_{counter}","startIndex":1,"zeroPadding":2}}
        """
        let decoded = try JSONDecoder().decode(ExportSettingsCodable.self, from: Data(legacyJSON.utf8))
        XCTAssertFalse(decoded.toExportSettings().lossless)
    }

    // MARK: - ExportFormat.supportsTransparency (corner-radius alpha, v1.6)

    func testSupportsTransparencyOnlyPNGAndWebP() {
        // Corner radius needs alpha: PNG and WebP keep it; the rest don't.
        XCTAssertTrue(ExportFormat.png.supportsTransparency)
        XCTAssertTrue(ExportFormat.webp.supportsTransparency)
        XCTAssertFalse(ExportFormat.jpeg.supportsTransparency)
        XCTAssertFalse(ExportFormat.heic.supportsTransparency)
        XCTAssertFalse(ExportFormat.tiff.supportsTransparency)
    }

    // MARK: - Save-in-Place validation with corner radius (relaxed to PNG *or* WebP)

    func testOverwriteWithCornerRadiusAllowsWebPOriginals() throws {
        // v1.6: a WebP original can carry corner-radius transparency in-place.
        var settings = ExportSettings()
        settings.outputDirectory = .overwriteOriginal

        let pngItem = ImageItem(url: try makeTempFileURL(name: "shot.png"), originalImage: makeDummyImage())
        let webpItem = ImageItem(url: try makeTempFileURL(name: "shot.webp"), originalImage: makeDummyImage())

        let error = settings.validateOverwriteMode(cornerRadiusEnabled: true, items: [pngItem, webpItem])
        XCTAssertNil(error, "PNG + WebP originals should both be allowed with corner radius")
    }

    func testOverwriteWithCornerRadiusBlocksJPEGOriginals() throws {
        // JPEG has no alpha channel, so overwriting it in place with corner radius must be blocked.
        var settings = ExportSettings()
        settings.outputDirectory = .overwriteOriginal

        let jpegItem = ImageItem(url: try makeTempFileURL(name: "photo.jpg"), originalImage: makeDummyImage())

        let error = settings.validateOverwriteMode(cornerRadiusEnabled: true, items: [jpegItem])
        XCTAssertNotNil(error, "A JPEG original should block corner-radius Save-in-Place")
    }
}
