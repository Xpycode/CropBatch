import AppKit
import CoreGraphics
import ImageIO

func testOrientation() {
    // 1. Create a bitmap (100x50) - Landscape
    let width = 100
    let height = 50
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    
    // Color it Red
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.red.setFill()
    NSRect(x: 0, y: 0, width: 100, height: 50).fill()
    NSGraphicsContext.restoreGraphicsState()
    
    // 2. Set Orientation to 6 (Rotate 90 CW)
    // This means the image is stored as 100x50, but should be displayed as 50x100
    bitmap.setValue(NSNumber(value: 6), forKey: NSImageRep.sharedPropertyKey("orientation") ?? "orientation") // "orientation" key might differ in exact string but NSImageRep has property keys.
    // Actually, NSImage uses a specific key for CGImagePropertyOrientation.
    // Let's use the CGImageProperty directly if possible.
    // NSBitmapImageRep has a property 'value(forProperty:)'
    bitmap.setProperty(NSBitmapImageRep.PropertyKey.compressionMethod, withValue: 1) // dummy
    // Setting orientation on NSBitmapImageRep is tricky directly via keys. 
    // It's often better to create an NSImage and set the size/representation.
    
    let image = NSImage(size: NSSize(width: 50, height: 100)) // Logical size (Portrait)
    image.addRepresentation(bitmap)
    
    // 3. Get CGImage
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("Failed to get CGImage")
        return
    }
    
    print("Logical NSImage Size: \(image.size)")
    print("CGImage Size: \(cgImage.width)x\(cgImage.height)")
    
    if cgImage.width == 100 && cgImage.height == 50 {
        print("❌ CGImage returns RAW dimensions (Landscape). Orientation NOT applied.")
    } else if cgImage.width == 50 && cgImage.height == 100 {
        print("✅ CGImage returns Display dimensions (Portrait). Orientation APPLIED.")
    } else {
        print("❓ Unexpected CGImage size.")
    }
}

testOrientation()
