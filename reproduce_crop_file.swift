import AppKit
import CoreGraphics
import Foundation

// --- Mocking parts of the app ---

struct CropSettings {
    var cropTop: Int = 0
    var cropBottom: Int = 0
    var cropLeft: Int = 0
    var cropRight: Int = 0
}

enum ImageCropError: Error {
    case failedToGetCGImage
    case invalidCropRegion
}

class ImageCropService {
    static func crop(_ image: NSImage, with settings: CropSettings) throws -> NSImage {
        // This is the line in question. Does it return a CGImage with consistent orientation?
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageCropError.failedToGetCGImage
        }

        let originalWidth = cgImage.width
        let originalHeight = cgImage.height

        // Current implementation in the app:
        let cropRect = CGRect(
            x: settings.cropLeft,
            y: settings.cropBottom,
            width: originalWidth - settings.cropLeft - settings.cropRight,
            height: originalHeight - settings.cropTop - settings.cropBottom
        )

        print("Original Size: \(originalWidth)x\(originalHeight)")
        print("Settings: Top:\(settings.cropTop) Bottom:\(settings.cropBottom)")
        print("Crop Rect (x,y,w,h): \(cropRect.origin.x), \(cropRect.origin.y), \(cropRect.width), \(cropRect.height)")

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            throw ImageCropError.invalidCropRegion
        }

        return NSImage(cgImage: croppedCGImage, size: NSSize(width: cropRect.width, height: cropRect.height))
    }
}

// --- Test Logic ---

func createAndSaveTestImage(path: String) {
    let width = 100
    let height = 100
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size)
    
    image.lockFocus()
    // Draw Bottom Half Blue (0 to 50)
    NSColor.blue.setFill()
    NSRect(x: 0, y: 0, width: 100, height: 50).fill()
    // Draw Top Half Red (50 to 100)
    NSColor.red.setFill()
    NSRect(x: 0, y: 50, width: 100, height: 50).fill()
    image.unlockFocus()
    
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG data")
        return
    }
    
    try? pngData.write(to: URL(fileURLWithPath: path))
}

func checkPixelColor(image: NSImage, x: Int, y: Int) -> String {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "No CGImage" }
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var pixelData = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
        data: &pixelData,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    
    // Check pixel at x, y (y=0 is bottom visually)
    context.draw(cgImage, in: CGRect(x: -CGFloat(x), y: -CGFloat(y), width: CGFloat(image.size.width), height: CGFloat(image.size.height)))
    
    let r = Int(pixelData[0])
    let g = Int(pixelData[1])
    let b = Int(pixelData[2])
    
    if r > 200 && b < 50 { return "Red" }
    if b > 200 && r < 50 { return "Blue" }
    return "Unknown(\(r),\(g),\(b))"
}

func testCropTopWithFile() {
    let path = "test_image.png"
    createAndSaveTestImage(path: path)
    
    print("\n--- Testing Crop Top: 20 (From File) ---")
    guard let image = NSImage(contentsOfFile: path) else {
        print("Failed to load image")
        return
    }
    
    let settings = CropSettings(cropTop: 20, cropBottom: 0, cropLeft: 0, cropRight: 0)
    
    do {
        let cropped = try ImageCropService.crop(image, with: settings)
        print("Result Size: \(cropped.size)")
        
        let bottomColor = checkPixelColor(image: cropped, x: 50, y: 0) // Should be Blue
        let topColor = checkPixelColor(image: cropped, x: 50, y: 79)   // Should be Red
        
        print("Pixel at bottom (y=0): \(bottomColor)")
        print("Pixel at top (y=79): \(topColor)")
        
        if bottomColor == "Blue" && topColor == "Red" {
            print("✅ Crop Top worked as expected.")
        } else {
            print("❌ Crop Top FAILED. Expected Bottom:Blue, Top:Red.")
        }
        
    } catch {
        print("Error: \(error)")
    }
}

testCropTopWithFile()
