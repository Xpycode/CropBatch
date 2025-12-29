import Foundation
import CoreGraphics

func checkAspectRatio(width: Double, height: Double, imageWidth: Double, imageHeight: Double) -> Bool {
    let cgRatio = width / height
    let nsRatio = imageWidth / imageHeight
    
    // Allow small epsilon for floating point errors
    return abs(cgRatio - nsRatio) < 0.01
}

print("Checking 100x50 (CG) vs 100x50 (NS): \(checkAspectRatio(width: 100, height: 50, imageWidth: 100, imageHeight: 50))")
print("Checking 100x50 (CG) vs 50x100 (NS): \(checkAspectRatio(width: 100, height: 50, imageWidth: 50, imageHeight: 100))")
print("Checking 200x100 (CG @2x) vs 100x50 (NS): \(checkAspectRatio(width: 200, height: 100, imageWidth: 100, imageHeight: 50))")
