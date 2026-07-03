@preconcurrency import SDWebImageWebPCoder
@preconcurrency import SDWebImage
import libwebp
import Accelerate
import AppKit
import CoreGraphics

/// Encodes images to WebP — ImageIO's CGImageDestination cannot write WebP on macOS,
/// so this is the only working encode path.
///
/// Lossy goes through SDWebImageWebPCoder. Lossless calls libwebp directly with
/// `picture.use_argb = 1`: the coder hardcodes `use_argb = 0` (YUV420), which
/// chroma-subsamples the pixels *before* the lossless VP8L encode — the file is
/// lossless-format but of already-degraded data (upstream issue #116).
enum WebPEncoder {
    /// libwebp method 0–6 (0=fast, 6=slow/best). Quality choice, not cwebp parity.
    /// Drop to 4 if large-batch WebP encoding feels slow.
    private static let webpMethod = 6

    /// Encodes to in-memory WebP Data. Used by Quick Export.
    static func encodedData(from image: NSImage, quality: Double, lossless: Bool) throws -> Data {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageCropError.failedToGetCGImage
        }
        if lossless {
            return try losslessData(from: cg, effort: quality)
        }
        let srgb = try srgbImage(from: cg)
        let opts: [SDImageCoderOption: Any] = [
            .encodeCompressionQuality: NSNumber(value: max(0, min(1, quality))),
            .encodeWebPMethod: NSNumber(value: webpMethod),
        ]
        guard let data = SDImageWebPCoder.shared.encodedData(with: srgb, format: .webP, options: opts) else {
            throw ImageCropError.failedToWriteImage
        }
        return data
    }

    /// Encodes and writes to disk. Used by the batch/save() path.
    static func encode(_ image: NSImage, to url: URL, quality: Double, lossless: Bool) throws {
        let data = try encodedData(from: image, quality: quality, lossless: lossless)
        try data.write(to: url)
    }

    // MARK: - Lossless via libwebp (VP8L, bit-exact)

    /// True lossless encode. `effort` reuses the quality dial: 1.0 = smallest file,
    /// slowest encode (libwebp quality 100); pixels are identical at every setting.
    private static func losslessData(from cg: CGImage, effort: Double) throws -> Data {
        // Straight (non-premultiplied) sRGB RGBA — CGBitmapContext can't produce
        // unpremultiplied alpha, so convert via vImage like the reference encoders do.
        guard var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        ) else { throw ImageCropError.failedToCreateContext }

        var buffer = vImage_Buffer()
        guard vImageBuffer_InitWithCGImage(&buffer, &format, nil, cg, vImage_Flags(kvImageNoFlags)) == kvImageNoError,
              let pixels = buffer.data else {
            throw ImageCropError.failedToCreateContext
        }
        defer { free(buffer.data) }

        var config = WebPConfig()
        var picture = WebPPicture()
        guard WebPConfigInit(&config) != 0, WebPPictureInit(&picture) != 0 else {
            throw ImageCropError.failedToWriteImage
        }
        config.lossless = 1
        config.quality = Float(max(0, min(1, effort)) * 100)  // compression effort, not fidelity
        config.method = Int32(webpMethod)
        picture.use_argb = 1  // ARGB bitstream — required for true lossless
        picture.width = Int32(cg.width)
        picture.height = Int32(cg.height)

        var writer = WebPMemoryWriter()
        WebPMemoryWriterInit(&writer)
        defer { WebPMemoryWriterClear(&writer) }
        picture.writer = WebPMemoryWrite

        let encoded = withUnsafeMutablePointer(to: &writer) { writerPtr -> Bool in
            picture.custom_ptr = UnsafeMutableRawPointer(writerPtr)
            guard WebPPictureImportRGBA(&picture, pixels.assumingMemoryBound(to: UInt8.self),
                                        Int32(buffer.rowBytes)) != 0 else { return false }
            return WebPEncode(&config, &picture) != 0
        }
        WebPPictureFree(&picture)

        guard encoded, writer.size > 0 else { throw ImageCropError.failedToWriteImage }
        return Data(bytes: writer.mem, count: writer.size)
    }

    // MARK: - Lossy helper

    /// Redraws into an sRGB context so libwebp writes color-consistent pixels;
    /// the coder embeds the matching sRGB ICC profile. A Display-P3 image written
    /// untagged would shift on color-managed viewers.
    private static func srgbImage(from cg: CGImage) throws -> NSImage {
        guard let ctx = CGContext(
            data: nil, width: cg.width, height: cg.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
        ) else { throw ImageCropError.failedToCreateContext }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        guard let out = ctx.makeImage() else { throw ImageCropError.failedToGetCGImage }
        return NSImage(cgImage: out, size: NSSize(width: cg.width, height: cg.height))
    }
}
