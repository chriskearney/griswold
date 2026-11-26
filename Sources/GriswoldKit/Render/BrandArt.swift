import AppKit
import CoreGraphics
import CoreText
import Foundation
import Metal
import simd

/// Draws the app icon and the disk image background with the same bulbs and
/// snow the app itself draws, so the branding can never drift from the product.
public enum BrandArt {
    /// A square canvas rendered through the real pipeline: a painted backdrop
    /// plus whatever the caller adds to the batch.
    private static func render(size: CGSize, scale: CGFloat,
                               backdrop: (CGContext) -> Void,
                               content: (RenderBatch) -> Void) -> CGImage? {
        guard let renderer = Renderer() else { return nil }
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let painted: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let c = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            c.translateBy(x: 0, y: CGFloat(height))
            c.scaleBy(x: scale, y: -scale)
            backdrop(c)
            return true
        }
        guard painted else { return nil }
        let backdropDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false
        )
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Renderer.pixelFormat, width: width, height: height, mipmapped: false
        )
        targetDescriptor.usage = [.renderTarget, .shaderRead]
        targetDescriptor.storageMode = .shared
        guard
            let backdropTexture = renderer.device.makeTexture(descriptor: backdropDescriptor),
            let target = renderer.device.makeTexture(descriptor: targetDescriptor),
            let commands = renderer.queue.makeCommandBuffer()
        else { return nil }
        pixels.withUnsafeBytes { raw in
            backdropTexture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                                    withBytes: raw.baseAddress!, bytesPerRow: width * 4)
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return nil }

        let viewport = SIMD2(Float(size.width), Float(size.height))
        let backdropBatch = RenderBatch()
        backdropBatch.add(SpriteInstance(pos: viewport * 0.5, size: viewport, color: SIMD4(1, 1, 1, 1), shape: Shape.atlas))
        renderer.encode(backdropBatch, buffers: FrameBuffers(), encoder: encoder, viewport: viewport,
                        scale: Float(scale), time: 0, texture: backdropTexture)
        let batch = RenderBatch()
        content(batch)
        renderer.encode(batch, buffers: FrameBuffers(), encoder: encoder, viewport: viewport,
                        scale: Float(scale), time: 0)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()

        var out = [UInt8](repeating: 0, count: width * height * 4)
        out.withUnsafeMutableBytes { raw in
            target.getBytes(raw.baseAddress!, bytesPerRow: width * 4,
                            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData) else { return nil }
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: info),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
        ArtPainter.rgb(r, g, b, a)
    }

    private static func nightSky(_ c: CGContext, size: CGSize) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        if let sky = CGGradient(colorsSpace: space, colors: [
            rgb(0x08, 0x0C, 0x24), rgb(0x12, 0x1F, 0x4D), rgb(0x27, 0x47, 0x80),
        ] as CFArray, locations: [0, 0.55, 1]) {
            c.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        if let glow = CGGradient(colorsSpace: space, colors: [
            rgb(0x8A, 0x63, 0xE0, 0.38), rgb(0x8A, 0x63, 0xE0, 0),
        ] as CFArray, locations: [0, 1]) {
            let centre = CGPoint(x: size.width * 0.72, y: size.height * 0.30)
            c.drawRadialGradient(glow, startCenter: centre, startRadius: 0, endCenter: centre,
                                 endRadius: size.width * 0.62, options: [])
        }
    }

    /// A rounded drift of snow along the bottom of a canvas.
    private static func drift(_ c: CGContext, size: CGSize, height: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -10, y: size.height + 10))
        path.addLine(to: CGPoint(x: -10, y: size.height - height * 0.55))
        path.addCurve(to: CGPoint(x: size.width * 0.52, y: size.height - height * 0.82),
                      control1: CGPoint(x: size.width * 0.16, y: size.height - height * 1.18),
                      control2: CGPoint(x: size.width * 0.34, y: size.height - height * 0.50))
        path.addCurve(to: CGPoint(x: size.width + 10, y: size.height - height * 0.70),
                      control1: CGPoint(x: size.width * 0.70, y: size.height - height * 1.14),
                      control2: CGPoint(x: size.width * 0.86, y: size.height - height * 1.02))
        path.addLine(to: CGPoint(x: size.width + 10, y: size.height + 10))
        path.closeSubpath()
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [rgb(255, 255, 255), rgb(0xE4, 0xEE, 0xFA), rgb(0xB9, 0xCE, 0xEA)] as CFArray,
            locations: [0, 0.45, 1]
        ) else { return }
        c.saveGState()
        c.addPath(path)
        c.clip()
        c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height - height * 1.1),
                             end: CGPoint(x: 0, y: size.height), options: [.drawsAfterEndLocation])
        c.restoreGState()
    }

    /// Bulbs along a draped wire, added straight to a batch.
    private static func drape(_ batch: RenderBatch, from a: SIMD2<Float>, to b: SIMD2<Float>, sag: Float,
                              bulbs: Int, bulbWidth: Float, wire: Float, glow: Float, seed: UInt64) {
        var rng = FastRNG(seed: seed)
        var points: [SIMD2<Float>] = []
        for i in 0...48 {
            let t = Float(i) / 48
            points.append(a + (b - a) * t + SIMD2(0, sag * 4 * t * (1 - t)))
        }
        batch.polyline(points, width: wire, color: SIMD4(0.04, 0.22, 0.13, 1), feather: wire * 0.3)
        let colours = Palettes.colors(for: .classic, customHex: "")
        let size = SIMD2<Float>(bulbWidth, bulbWidth * 2)
        var placed: [(SIMD2<Float>, Float, SIMD3<Float>)] = []
        for i in 0..<bulbs {
            let t = (Float(i) + 0.5) / Float(bulbs)
            let anchor = a + (b - a) * t + SIMD2(0, sag * 4 * t * (1 - t))
            // Lean with the slope of the wire, plus a little disorder.
            let slope = sag * 4 * (1 - 2 * t) / (b.x - a.x)
            let angle = -atanf(slope) * 0.5 + rng.signed() * 0.12
            let direction = SIMD2<Float>(-sinf(angle), cosf(angle))
            placed.append((anchor + direction * (size.y * 0.5 - wire), angle, colours[i % colours.count]))
        }
        for (centre, _, colour) in placed {
            batch.add(SpriteInstance(
                pos: centre, size: SIMD2(repeating: bulbWidth * 4.6),
                color: SIMD4(colour.x, colour.y, colour.z, glow), shape: Shape.halo, p0: 0.12
            ))
        }
        for (centre, angle, colour) in placed {
            batch.add(SpriteInstance(
                pos: centre, size: size, color: SIMD4(colour.x, colour.y, colour.z, 1),
                rot: angle, shape: Shape.bulb, p0: 1.05, p1: 0
            ))
        }
    }

    private static func flurry(_ batch: RenderBatch, in rect: CGRect, count: Int, radius: ClosedRange<Float>, seed: UInt64) {
        var rng = FastRNG(seed: seed)
        for _ in 0..<count {
            let r = rng.range(radius.lowerBound, radius.upperBound)
            let position = SIMD2<Float>(
                Float(rect.minX) + rng.unit() * Float(rect.width),
                Float(rect.minY) + rng.unit() * Float(rect.height)
            )
            if r > radius.upperBound * 0.72 {
                batch.add(SpriteInstance(pos: position, size: SIMD2(repeating: r * 3.4),
                                         color: SIMD4(1, 1, 1, 0.9), rot: rng.range(0, 1), shape: Shape.crystal))
            } else {
                batch.add(SpriteInstance(pos: position, size: SIMD2(repeating: r * 2.4),
                                         color: SIMD4(1, 1, 1, rng.range(0.55, 0.95)), shape: Shape.dot, p0: 0.35))
            }
        }
    }

    // MARK: App icon

    /// The 1024-point app icon: lights over a snowdrift, on the macOS icon shape.
    public static func icon() -> CGImage? {
        let side: CGFloat = 1024
        let size = CGSize(width: side, height: side)
        let artwork = render(size: size, scale: 1, backdrop: { c in
            nightSky(c, size: size)
            drift(c, size: size, height: 330)
        }, content: { batch in
            flurry(batch, in: CGRect(x: 110, y: 120, width: 804, height: 520), count: 46, radius: 5...19, seed: 21)
            drape(batch, from: SIMD2(60, 196), to: SIMD2(964, 196), sag: 150, bulbs: 5,
                  bulbWidth: 124, wire: 11, glow: 0.62, seed: 5)
        })
        guard let artwork else { return nil }

        // Mask to the standard icon shape and add its soft shadow.
        guard let c = CGContext(
            data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: CGColor(gray: 0, alpha: 0.32))
        c.setFillColor(rgb(0x0C, 0x14, 0x33))
        c.addPath(shape)
        c.fillPath()
        c.restoreGState()
        c.saveGState()
        c.addPath(shape)
        c.clip()
        // The artwork fills the plate; it was composed for the full canvas, so
        // scale it into the plate rather than cropping the corners off.
        c.draw(artwork, in: plate)
        c.restoreGState()
        c.addPath(CGPath(roundedRect: plate.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 183.5, cornerHeight: 183.5, transform: nil))
        c.setStrokeColor(CGColor(gray: 1, alpha: 0.16))
        c.setLineWidth(3)
        c.strokePath()
        return c.makeImage()
    }

    // MARK: Disk image background

    /// Background for the installer window: where to drag, and to where.
    public static func diskImageBackground(scale: CGFloat) -> CGImage? {
        let size = CGSize(width: 660, height: 420)
        return render(size: size, scale: scale, backdrop: { c in
            nightSky(c, size: size)
            drift(c, size: size, height: 96)
            // Arrow from the app to the Applications folder.
            let y: CGFloat = 214
            c.setStrokeColor(CGColor(gray: 1, alpha: 0.78))
            c.setLineWidth(5)
            c.setLineCap(.round)
            c.setLineJoin(.round)
            c.beginPath()
            c.move(to: CGPoint(x: 286, y: y))
            c.addLine(to: CGPoint(x: 372, y: y))
            c.move(to: CGPoint(x: 356, y: y - 15))
            c.addLine(to: CGPoint(x: 374, y: y))
            c.addLine(to: CGPoint(x: 356, y: y + 15))
            c.strokePath()
            text(c, "Drag Griswold into Applications", at: CGPoint(x: size.width / 2, y: 86), size: 19, weight: 0.3)
        }, content: { batch in
            flurry(batch, in: CGRect(x: 0, y: 60, width: 660, height: 280), count: 60, radius: 1.2...4.2, seed: 9)
            drape(batch, from: SIMD2(-20, 4), to: SIMD2(680, 4), sag: 30, bulbs: 13,
                  bulbWidth: 14, wire: 1.6, glow: 0.6, seed: 3)
        })
    }

    /// The system's rounded face, as used for the app's own title.
    static func roundedFont(size: CGFloat, weight: NSFont.Weight) -> CTFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded),
           let rounded = NSFont(descriptor: descriptor, size: size) {
            return rounded as CTFont
        }
        return base as CTFont
    }

    private static func text(_ c: CGContext, _ string: String, at centre: CGPoint, size: CGFloat, weight: CGFloat) {
        draw(c, string, at: centre, font: roundedFont(size: size, weight: .medium),
             colour: CGColor(gray: 1, alpha: 0.92), centred: true)
    }

    /// Draws one line of text in a context whose y axis points down.
    static func draw(_ c: CGContext, _ string: String, at point: CGPoint, font: CTFont, colour: CGColor,
                     centred: Bool = false, tracking: CGFloat = 0) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour,
            NSAttributedString.Key(kCTKernAttributeName as String): tracking,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        // Flip back locally so glyphs are upright.
        c.saveGState()
        c.translateBy(x: centred ? point.x - bounds.width / 2 : point.x, y: point.y)
        c.scaleBy(x: 1, y: -1)
        c.textPosition = .zero
        CTLineDraw(line, c)
        c.restoreGState()
    }

    // MARK: Link preview

    /// The 1200 x 630 card shown when the website is shared in Messages, X, Slack and so on.
    public static func linkPreview(scale: CGFloat = 2) -> CGImage? {
        var options = Snapshot.Options()
        options.size = CGSize(width: 1200, height: 630)
        options.scale = scale
        options.seconds = 140
        options.topInset = 0
        options.surprise = .santa
        options.lead = 3.3
        options.config.snowIntensity = 0.5
        options.config.accumulation = .deep
        options.config.bulbScale = 1.35
        options.config.spacing = 1.1
        options.config.glow = 0.9
        options.config.pattern = .steady
        options.config.edgeBottom = false
        options.windows = [
            CGRect(x: 640, y: 318, width: 470, height: 420),
            CGRect(x: 786, y: 196, width: 330, height: 300),
        ]
        let icon = BrandArt.icon()
        options.decorate = { c, _ in
            if let icon {
                // Core Graphics draws images bottom-up; flip around the icon's own box.
                c.saveGState()
                c.translateBy(x: 62, y: 190 + 132)
                c.scaleBy(x: 1, y: -1)
                c.draw(icon, in: CGRect(x: 0, y: 0, width: 132, height: 132))
                c.restoreGState()
            }
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: -6), blur: 26, color: CGColor(gray: 0, alpha: 0.55))
            draw(c, "Griswold", at: CGPoint(x: 74, y: 430), font: roundedFont(size: 118, weight: .heavy),
                 colour: CGColor(gray: 1, alpha: 1), tracking: -2)
            draw(c, "Snow, lights and the occasional", at: CGPoint(x: 80, y: 492),
                 font: roundedFont(size: 34, weight: .medium), colour: CGColor(gray: 1, alpha: 0.86))
            draw(c, "sleigh, for your Mac.", at: CGPoint(x: 80, y: 536),
                 font: roundedFont(size: 34, weight: .medium), colour: CGColor(gray: 1, alpha: 0.86))
            c.restoreGState()
        }
        return Snapshot.render(options)
    }
}
