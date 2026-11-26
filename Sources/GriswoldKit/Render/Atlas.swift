import CoreGraphics
import Foundation
import Metal
import simd

/// Pieces of illustrated art. Everything is drawn in code at launch, so the app
/// ships no image files.
public enum Art: Int, CaseIterable {
    case sleigh, reindeerStride, reindeerGather
    case presentRed, presentGreen, presentBlue
    case snowman, splat

    /// Design size in points.
    public var size: CGSize {
        switch self {
        case .sleigh: return CGSize(width: 118, height: 80)
        case .reindeerStride, .reindeerGather: return CGSize(width: 70, height: 58)
        case .presentRed, .presentGreen, .presentBlue: return CGSize(width: 30, height: 32)
        case .snowman: return CGSize(width: 92, height: 128)
        case .splat: return CGSize(width: 150, height: 190)
        }
    }
}

public final class Atlas {
    public let texture: MTLTexture
    private var rects: [SIMD4<Float>] = []

    static let pixelsPerPoint: CGFloat = 3
    static let width = 2048
    static let height = 1024

    public func uv(_ art: Art) -> SIMD4<Float> { rects[art.rawValue] }

    public func size(_ art: Art) -> SIMD2<Float> {
        SIMD2(Float(art.size.width), Float(art.size.height))
    }

    init?(device: MTLDevice, queue: MTLCommandQueue) {
        guard let image = Atlas.render() else { return nil }
        rects = image.rects

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: Atlas.width, height: Atlas.height, mipmapped: true
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        image.pixels.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegionMake2D(0, 0, Atlas.width, Atlas.height),
                mipmapLevel: 0,
                withBytes: raw.baseAddress!,
                bytesPerRow: Atlas.width * 4
            )
        }
        if let buffer = queue.makeCommandBuffer(), let blit = buffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            buffer.commit()
        }
        self.texture = texture
    }

    struct Rendered {
        var pixels: [UInt8]
        var rects: [SIMD4<Float>]
    }

    /// Draws every piece of art into one RGBA bitmap, packed on shelves.
    static func render() -> Rendered? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var rects: [SIMD4<Float>] = []
        let ok: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // Flip so art is authored with the origin at the top-left.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.setLineCap(.round)
            context.setLineJoin(.round)

            let padding: CGFloat = 6
            var cursor = CGPoint(x: padding, y: padding)
            var shelfHeight: CGFloat = 0
            for art in Art.allCases {
                let w = art.size.width * pixelsPerPoint
                let h = art.size.height * pixelsPerPoint
                if cursor.x + w + padding > CGFloat(width) {
                    cursor.x = padding
                    cursor.y += shelfHeight + padding
                    shelfHeight = 0
                }
                shelfHeight = max(shelfHeight, h)
                context.saveGState()
                context.translateBy(x: cursor.x, y: cursor.y)
                context.clip(to: CGRect(x: 0, y: 0, width: w, height: h))
                context.scaleBy(x: pixelsPerPoint, y: pixelsPerPoint)
                ArtPainter.draw(art, in: context)
                context.restoreGState()
                rects.append(SIMD4(
                    Float(cursor.x) / Float(width), Float(cursor.y) / Float(height),
                    Float(cursor.x + w) / Float(width), Float(cursor.y + h) / Float(height)
                ))
                cursor.x += w + padding
            }
            return true
        }
        return ok ? Rendered(pixels: pixels, rects: rects) : nil
    }
}
