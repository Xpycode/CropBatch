import AppKit
import CoreGraphics

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

func createTestImage() -> NSImage {
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
    return image
}

func checkPixelColor(image: NSImage, x: Int, y: Int) -> String {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "No CGImage" } 
    
    // Create a 1x1 bitmap context to read the pixel
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
    
    // Translate so that the desired pixel is at 0,0
    // CGImage coordinates: 0,0 is usually bottom-left? or top-left? 
    // Let's draw the whole image into a 1x1 context at offset -x, -y
    // But wait, "drawing" a CGImage usually respects its internal data ordering.
    // If we simply draw the image at (-x, -y), we capture the pixel at (x,y).
    // Note: CGContext coordinate system has 0,0 at bottom-left by default.
    
    // If we want to check pixel at (x, y) where y=0 is BOTTOM.
    context.draw(cgImage, in: CGRect(x: -CGFloat(x), y: -CGFloat(y), width: CGFloat(image.size.width), height: CGFloat(image.size.height)))
    
    let r = Int(pixelData[0])
    let g = Int(pixelData[1])
    let b = Int(pixelData[2])
    
    if r > 200 && b < 50 { return "Red" } 
    if b > 200 && r < 50 { return "Blue" } 
    return "Unknown(\(r),\(g),\(b))"
}

func testCropTop() {
    print("\n--- Testing Crop Top: 20 ---")
    let image = createTestImage() // 100x100. Bottom 50 Blue, Top 50 Red.
    
    // In NSImage drawing (lockFocus): 0,0 is Bottom-Left.
    // So y=0..50 is Blue, y=50..100 is Red.
    
    // If we crop Top 20:
    // We expect the top 20 pixels (y=80..100) to be removed.
    // Remaining range: y=0..80.
    // Result Height: 80.
    // New Top (y=80) should be Red.
    // Bottom (y=0) should be Blue.
    
    let settings = CropSettings(cropTop: 20, cropBottom: 0, cropLeft: 0, cropRight: 0)
    
    do {
        let cropped = try ImageCropService.crop(image, with: settings)
        print("Result Size: \(cropped.size)")
        
        // Check bottom pixel (should be Blue)
        // Using checkPixelColor with y=0 (bottom)
        let bottomColor = checkPixelColor(image: cropped, x: 50, y: 0)
        print("Pixel at bottom (y=0): \(bottomColor)")
        
        // Check top pixel (should be Red)
        // y=79
        let topColor = checkPixelColor(image: cropped, x: 50, y: 79)
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

func testCropBottom() {
    print("\n--- Testing Crop Bottom: 20 ---")
    let image = createTestImage()
    
    // Crop Bottom 20:
    // Remove y=0..20.
    // Remaining range: y=20..100.
    // Result Height: 80.
    // Bottom (new y=0, old y=20) should be Blue.
    // Top (new y=79, old y=99) should be Red.
    
    let settings = CropSettings(cropTop: 0, cropBottom: 20, cropLeft: 0, cropRight: 0)
    
    do {
        let cropped = try ImageCropService.crop(image, with: settings)
        print("Result Size: \(cropped.size)")
        
        let bottomColor = checkPixelColor(image: cropped, x: 50, y: 0)
        print("Pixel at bottom (y=0): \(bottomColor)")
        
        let topColor = checkPixelColor(image: cropped, x: 50, y: 79)
        print("Pixel at top (y=79): \(topColor)")
        
        if bottomColor == "Blue" && topColor == "Red" {
            print("✅ Crop Bottom worked as expected.")
        } else {
             print("❌ Crop Bottom FAILED.")
        }
    } catch {
        print("Error: \(error)")
    }
}

testCropTop()
testCropBottom()
