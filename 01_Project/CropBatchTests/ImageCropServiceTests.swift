import XCTest
import CoreGraphics
@testable import CropBatch

final class ImageCropServiceTests: XCTestCase {

    // MARK: - Helpers

    private func createTestCGImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    // MARK: - splitIntoGrid

    func testSplitIntoGrid2x2() {
        let image = createTestCGImage(width: 100, height: 100)
        let tiles = ImageCropService.splitIntoGrid(image: image, rows: 2, cols: 2)

        XCTAssertEqual(tiles.count, 4)
        for tile in tiles {
            XCTAssertEqual(tile.image.width, 50)
            XCTAssertEqual(tile.image.height, 50)
        }
    }

    func testSplitIntoGrid3x3() {
        // 100 / 3 = 33 remainder 1 → tiles 1-2 are 33px wide, tile 3 is 34px (absorbs remainder)
        let image = createTestCGImage(width: 100, height: 100)
        let tiles = ImageCropService.splitIntoGrid(image: image, rows: 3, cols: 3)

        XCTAssertEqual(tiles.count, 9)

        let row1Tiles = tiles.filter { $0.row == 1 }.sorted { $0.col < $1.col }
        XCTAssertEqual(row1Tiles[0].image.width, 33)
        XCTAssertEqual(row1Tiles[1].image.width, 33)
        XCTAssertEqual(row1Tiles[2].image.width, 34)
    }

    func testSplitIntoGrid1x1() {
        let image = createTestCGImage(width: 100, height: 100)
        let tiles = ImageCropService.splitIntoGrid(image: image, rows: 1, cols: 1)

        XCTAssertEqual(tiles.count, 1)
        XCTAssertEqual(tiles[0].image.width, image.width)
        XCTAssertEqual(tiles[0].image.height, image.height)
    }

    func testSplitIntoGrid1x3() {
        // 1 row, 3 cols → 3 horizontal strips
        let image = createTestCGImage(width: 99, height: 60)
        let tiles = ImageCropService.splitIntoGrid(image: image, rows: 1, cols: 3)

        XCTAssertEqual(tiles.count, 3)
        for tile in tiles {
            XCTAssertEqual(tile.row, 1)
            XCTAssertEqual(tile.image.height, 60)
        }
        XCTAssertEqual(tiles[0].image.width, 33)
        XCTAssertEqual(tiles[1].image.width, 33)
        XCTAssertEqual(tiles[2].image.width, 33)
    }

    func testSplitIntoGridNonEvenDivision() {
        // 101 / 2 = 50 remainder 1 → first tile 50px, last tile 51px
        let image = createTestCGImage(width: 101, height: 101)
        let tiles = ImageCropService.splitIntoGrid(image: image, rows: 2, cols: 2)

        XCTAssertEqual(tiles.count, 4)

        let topLeft     = tiles.first { $0.row == 1 && $0.col == 1 }!
        let topRight    = tiles.first { $0.row == 1 && $0.col == 2 }!
        let bottomLeft  = tiles.first { $0.row == 2 && $0.col == 1 }!
        let bottomRight = tiles.first { $0.row == 2 && $0.col == 2 }!

        XCTAssertEqual(topLeft.image.width, 50)
        XCTAssertEqual(topLeft.image.height, 50)

        XCTAssertEqual(topRight.image.width, 51)   // last col absorbs remainder
        XCTAssertEqual(topRight.image.height, 50)

        XCTAssertEqual(bottomLeft.image.width, 50)
        XCTAssertEqual(bottomLeft.image.height, 51) // last row absorbs remainder

        XCTAssertEqual(bottomRight.image.width, 51)
        XCTAssertEqual(bottomRight.image.height, 51)
    }

    // MARK: - calculateResizedSize

    func testResizeModeNone() {
        var settings = ResizeSettings()
        settings.mode = .none
        let result = ImageCropService.calculateResizedSize(
            from: CGSize(width: 1000, height: 500),
            with: settings
        )
        XCTAssertNil(result)
    }

    func testResizeModeExactSizeWithAspectRatio() {
        var settings = ResizeSettings()
        settings.mode = .exactSize
        settings.width = 400
        settings.height = 400
        settings.maintainAspectRatio = true

        // 1000x500, aspect 2:1 → fits in 400x400 as 400x200
        let result = ImageCropService.calculateResizedSize(
            from: CGSize(width: 1000, height: 500),
            with: settings
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.width, 400, accuracy: 0.001)
        XCTAssertEqual(result!.height, 200, accuracy: 0.001)
    }

    func testResizeModeMaxWidth() {
        var settings = ResizeSettings()
        settings.mode = .maxWidth
        settings.width = 800

        // 1000x500 scaled to maxWidth 800 → 800x400
        let result = ImageCropService.calculateResizedSize(
            from: CGSize(width: 1000, height: 500),
            with: settings
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.width, 800, accuracy: 0.001)
        XCTAssertEqual(result!.height, 400, accuracy: 0.001)
    }

    func testResizeModeMaxWidthNoResize() {
        var settings = ResizeSettings()
        settings.mode = .maxWidth
        settings.width = 800

        // 500x250 is already narrower than 800 → nil (no resize needed)
        let result = ImageCropService.calculateResizedSize(
            from: CGSize(width: 500, height: 250),
            with: settings
        )

        XCTAssertNil(result)
    }

    func testResizeModePercentage() {
        var settings = ResizeSettings()
        settings.mode = .percentage
        settings.percentage = 50.0

        let result = ImageCropService.calculateResizedSize(
            from: CGSize(width: 1000, height: 500),
            with: settings
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.width, 500, accuracy: 0.001)
        XCTAssertEqual(result!.height, 250, accuracy: 0.001)
    }
}
