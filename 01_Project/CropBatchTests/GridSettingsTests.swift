import XCTest
@testable import CropBatch

final class GridSettingsTests: XCTestCase {

    func testDefaultValues() {
        let settings = GridSettings()
        XCTAssertEqual(settings.isEnabled, false)
        XCTAssertEqual(settings.columns, 2)
        XCTAssertEqual(settings.rows, 2)
        XCTAssertEqual(settings.namingSuffix, "_{row}_{col}")
    }

    func testEquatableTwoDefaultsAreEqual() {
        let a = GridSettings()
        let b = GridSettings()
        XCTAssertEqual(a, b)
    }

    func testEquatableChangingFieldMakesUnequal() {
        let a = GridSettings()
        var b = GridSettings()
        b.columns = 3
        XCTAssertNotEqual(a, b)
    }

    func testCodableRoundTrip() throws {
        var original = GridSettings()
        original.isEnabled = true
        original.columns = 3
        original.rows = 4
        original.namingSuffix = "_{row}-{col}"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GridSettings.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testNamingSuffixTokenReplacement() {
        let settings = GridSettings()
        let suffix = settings.namingSuffix
            .replacingOccurrences(of: "{row}", with: "2")
            .replacingOccurrences(of: "{col}", with: "3")
        XCTAssertEqual(suffix, "_2_3")
    }
}
