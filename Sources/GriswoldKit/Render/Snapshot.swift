import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd
import UniformTypeIdentifiers

/// Renders the real simulation into an image, over a painted stand-in desktop.
///
/// Used to check the look without a display, and to produce the pictures on the
/// website: what you see there is drawn by the same code that runs on a Mac.
public enum Snapshot {
    public struct Options {
        public var size = CGSize(width: 1440, height: 900)
        public var scale: CGFloat = 2
        /// How long the simulation runs before the picture is taken.
        public var seconds: Double = 150
        public var config = Config()
        public var windows: [CGRect] = []
        public var surprise: SurpriseKind?
        /// How long before the picture the surprise starts.
        public var lead: Double = 3
        public var topInset: CGFloat = 26
        public var darkWindows = true
        public var transparent = false

        public init() {}
    }

    public static func defaultWindows(for size: CGSize) -> [CGRect] {
        let w = size.width
        let h = size.height
        return [
            CGRect(x: w * 0.36, y: h * 0.40, width: w * 0.40, height: h * 0.44),
            CGRect(x: w * 0.08, y: h * 0.20, width: w * 0.42, height: h * 0.52),
            CGRect(x: w * 0.62, y: h * 0.14, width: w * 0.30, height: h * 0.40),
        ]
    }

    public static func render(_ options: Options) -> CGImage? {
        guard let renderer = Renderer() else { return nil }
        let size = options.size
        let pixelWidth = Int(size.width * options.scale)
        let pixelHeight = Int(size.height * options.scale)

        let frame = CGRect(origin: .zero, size: size)
        let scene = ScreenScene(frame: frame, topInset: Float(options.topInset), seed: 7)
        let director = Director()
        director.scenes = { [scene] }
        director.desktopBounds = { frame }

        var config = options.config
        config.surpriseFrequency = .off
        let windows = options.windows.enumerated().map { WindowInfo(id: UInt32($0.offset + 1), frame: $0.element) }
        scene.setWindows(windows, now: 0, spaceChangedAt: -100, fullscreenHint: false, config: config)

        let step = 1.0 / 60.0
        var now = 0.0
        var fired = options.surprise == nil
        director.advance(now: now, config: config)
        while now < options.seconds {
            now += step
            if !fired, now >= options.seconds - options.lead, let kind = options.surprise {
                director.trigger(kind, now: now, config: config)
                fired = true
            }
            director.advance(now: now, config: config)
            scene.step(dt: Float(step), now: now, config: config, world: director.world,
                       cursor: nil, cursorVelocity: .zero)
        }

        let batch = RenderBatch()
        scene.build(batch, atlas: renderer.atlas, world: director.world, config: config)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Renderer.pixelFormat, width: pixelWidth, height: pixelHeight, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard
            let target = renderer.device.makeTexture(descriptor: descriptor),
            let commands = renderer.queue.makeCommandBuffer()
        else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return nil }

        let viewport = SIMD2(Float(size.width), Float(size.height))
        let buffers = FrameBuffers()
        let backdropBuffers = FrameBuffers()
        if !options.transparent,
           let backdrop = DesktopPainter.texture(
               device: renderer.device, size: size, scale: options.scale,
               windows: options.windows, topInset: options.topInset, dark: options.darkWindows
           ) {
            let backdropBatch = RenderBatch()
            backdropBatch.add(SpriteInstance(
                pos: viewport * 0.5, size: viewport, color: SIMD4(1, 1, 1, 1), shape: Shape.atlas
            ))
            renderer.encode(backdropBatch, buffers: backdropBuffers, encoder: encoder, viewport: viewport,
                            scale: Float(options.scale), time: Float(now), texture: backdrop)
        }
        renderer.encode(batch, buffers: buffers, encoder: encoder, viewport: viewport,
                        scale: Float(options.scale), time: Float(now))
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()

        var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        pixels.withUnsafeMutableBytes { raw in
            target.getBytes(raw.baseAddress!, bytesPerRow: pixelWidth * 4,
                            from: MTLRegionMake2D(0, 0, pixelWidth, pixelHeight), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        return CGImage(
            width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: pixelWidth * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    @discardableResult
    public static func write(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    /// The art atlas as an image, for checking the illustrations.
    public static func atlasImage() -> CGImage? {
        guard let rendered = Atlas.render(),
              let provider = CGDataProvider(data: Data(rendered.pixels) as CFData) else { return nil }
        return CGImage(
            width: Atlas.width, height: Atlas.height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: Atlas.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}

/// Paints a plausible desktop: wallpaper, a menu bar, and a few windows.
enum DesktopPainter {
    static func texture(device: MTLDevice, size: CGSize, scale: CGFloat, windows: [CGRect],
                        topInset: CGFloat, dark: Bool) -> MTLTexture? {
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let ok: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let c = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            c.translateBy(x: 0, y: CGFloat(height))
            c.scaleBy(x: scale, y: -scale)
            paint(c, size: size, windows: windows, topInset: topInset, dark: dark)
            return true
        }
        guard ok else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false
        )
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        pixels.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: raw.baseAddress!, bytesPerRow: width * 4)
        }
        return texture
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
        ArtPainter.rgb(r, g, b, a)
    }

    static func paint(_ c: CGContext, size: CGSize, windows: [CGRect], topInset: CGFloat, dark: Bool) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        // Wallpaper: a winter night, deep blue up top easing into a cold glow at the horizon.
        if let sky = CGGradient(colorsSpace: space, colors: [
            rgb(0x07, 0x0B, 0x1E), rgb(0x0E, 0x1B, 0x3F), rgb(0x1E, 0x3A, 0x6B), rgb(0x3D, 0x5F, 0x8E),
        ] as CFArray, locations: [0, 0.42, 0.8, 1]) {
            c.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        if let glow = CGGradient(colorsSpace: space, colors: [
            rgb(0x7B, 0x5C, 0xD6, 0.34), rgb(0x7B, 0x5C, 0xD6, 0),
        ] as CFArray, locations: [0, 1]) {
            c.drawRadialGradient(glow, startCenter: CGPoint(x: size.width * 0.78, y: size.height * 0.2),
                                 startRadius: 0, endCenter: CGPoint(x: size.width * 0.78, y: size.height * 0.2),
                                 endRadius: size.width * 0.5, options: [])
        }
        // Distant hills.
        for (index, tone) in [rgb(0x16, 0x2A, 0x52), rgb(0x10, 0x1F, 0x40)].enumerated() {
            let baseline = size.height * (0.80 + CGFloat(index) * 0.07)
            c.setFillColor(tone)
            c.beginPath()
            c.move(to: CGPoint(x: 0, y: size.height))
            var x: CGFloat = 0
            while x <= size.width + 40 {
                let y = baseline - sin(x * 0.0042 + CGFloat(index) * 2.1) * 36 - sin(x * 0.011 + CGFloat(index)) * 12
                c.addLine(to: CGPoint(x: x, y: y))
                x += 20
            }
            c.addLine(to: CGPoint(x: size.width, y: size.height))
            c.closePath()
            c.fillPath()
        }

        // Windows, back to front.
        for (index, rect) in windows.enumerated().reversed() {
            window(c, rect: rect, dark: dark, variant: index)
        }

        // Menu bar.
        if topInset > 0 {
            c.setFillColor(rgb(0x10, 0x16, 0x2C, 0.72))
            c.fill(CGRect(x: 0, y: 0, width: size.width, height: topInset))
            c.setFillColor(rgb(255, 255, 255, 0.86))
            var x: CGFloat = 18
            for width in [CGFloat(14), 52, 30, 30, 36, 46, 34] {
                c.addPath(CGPath(roundedRect: CGRect(x: x, y: topInset / 2 - 3, width: width, height: 6),
                                 cornerWidth: 3, cornerHeight: 3, transform: nil))
                x += width + 16
            }
            x = size.width - 20
            for width in [CGFloat(64), 16, 16, 16, 20] {
                x -= width
                c.addPath(CGPath(roundedRect: CGRect(x: x, y: topInset / 2 - 3, width: width, height: 6),
                                 cornerWidth: 3, cornerHeight: 3, transform: nil))
                x -= 14
            }
            c.fillPath()
        }
    }

    private static func window(_ c: CGContext, rect: CGRect, dark: Bool, variant: Int) {
        let radius: CGFloat = 12
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -16), blur: 38, color: CGColor(gray: 0, alpha: 0.55))
        c.setFillColor(dark ? rgb(0x1D, 0x1F, 0x27) : rgb(0xF6, 0xF6, 0xF8))
        c.addPath(path)
        c.fillPath()
        c.restoreGState()

        c.saveGState()
        c.addPath(path)
        c.clip()
        let bar: CGFloat = 38
        c.setFillColor(dark ? rgb(0x2A, 0x2C, 0x37) : rgb(0xE9, 0xE9, 0xEE))
        c.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: bar))
        for (i, colour) in [rgb(0xFF, 0x5F, 0x57), rgb(0xFE, 0xBC, 0x2E), rgb(0x28, 0xC8, 0x40)].enumerated() {
            c.setFillColor(colour)
            c.fillEllipse(in: CGRect(x: rect.minX + 14 + CGFloat(i) * 20, y: rect.minY + 13, width: 12, height: 12))
        }
        let ink = dark ? rgb(255, 255, 255, 0.13) : rgb(0, 0, 0, 0.10)
        let strong = dark ? rgb(255, 255, 255, 0.24) : rgb(0, 0, 0, 0.2)
        c.setFillColor(strong)
        c.addPath(CGPath(roundedRect: CGRect(x: rect.midX - 50, y: rect.minY + 15, width: 100, height: 8),
                         cornerWidth: 4, cornerHeight: 4, transform: nil))
        c.fillPath()

        // Placeholder content: a sidebar and lines, or a grid, by variant.
        let content = rect.insetBy(dx: 0, dy: 0).divided(atDistance: bar, from: .minYEdge).remainder
        if variant % 3 == 1 {
            c.setFillColor(dark ? rgb(0x23, 0x25, 0x2F) : rgb(0xEE, 0xEE, 0xF2))
            c.fill(CGRect(x: content.minX, y: content.minY, width: 150, height: content.height))
            c.setFillColor(ink)
            var y = content.minY + 20
            while y < content.maxY - 16 {
                c.addPath(CGPath(roundedRect: CGRect(x: content.minX + 18, y: y, width: 90 + CGFloat((Int(y) * 7) % 30), height: 8),
                                 cornerWidth: 4, cornerHeight: 4, transform: nil))
                y += 26
            }
            c.fillPath()
            y = content.minY + 24
            var row = 0
            while y < content.maxY - 16 {
                let width = (content.width - 210) * (0.55 + 0.4 * CGFloat((row * 37) % 10) / 10)
                c.setFillColor(row % 5 == 0 ? strong : ink)
                c.addPath(CGPath(roundedRect: CGRect(x: content.minX + 180, y: y, width: width, height: 9),
                                 cornerWidth: 4.5, cornerHeight: 4.5, transform: nil))
                c.fillPath()
                y += 24
                row += 1
            }
        } else if variant % 3 == 2 {
            let columns = 3
            let gap: CGFloat = 14
            let cell = (content.width - gap * CGFloat(columns + 1)) / CGFloat(columns)
            var y = content.minY + gap
            var n = 0
            let tints = [rgb(0x4C, 0x7D, 0xF0, 0.55), rgb(0xE0, 0x5A, 0x6C, 0.55), rgb(0x3C, 0xB8, 0x7A, 0.55),
                         rgb(0xE2, 0xA8, 0x3C, 0.55), rgb(0x8D, 0x6B, 0xE8, 0.55), rgb(0x39, 0xB5, 0xC8, 0.55)]
            while y + cell * 0.7 < content.maxY {
                for col in 0..<columns {
                    c.setFillColor(tints[n % tints.count])
                    c.addPath(CGPath(roundedRect: CGRect(x: content.minX + gap + CGFloat(col) * (cell + gap), y: y,
                                                         width: cell, height: cell * 0.7),
                                     cornerWidth: 8, cornerHeight: 8, transform: nil))
                    c.fillPath()
                    n += 1
                }
                y += cell * 0.7 + gap
            }
        } else {
            // A terminal-ish column of text.
            var y = content.minY + 20
            var row = 0
            let accents = [rgb(0x6C, 0xD4, 0x8E, 0.75), rgb(0x7F, 0xB4, 0xFF, 0.75), rgb(0xF2, 0xC1, 0x4B, 0.75)]
            while y < content.maxY - 14 {
                let indent = CGFloat((row * 13) % 4) * 18
                c.setFillColor(accents[row % accents.count])
                c.addPath(CGPath(roundedRect: CGRect(x: content.minX + 20 + indent, y: y, width: 44, height: 8),
                                 cornerWidth: 4, cornerHeight: 4, transform: nil))
                c.fillPath()
                c.setFillColor(ink)
                let width = (content.width - 130 - indent) * (0.35 + 0.6 * CGFloat((row * 53) % 10) / 10)
                c.addPath(CGPath(roundedRect: CGRect(x: content.minX + 74 + indent, y: y, width: max(width, 30), height: 8),
                                 cornerWidth: 4, cornerHeight: 4, transform: nil))
                c.fillPath()
                y += 22
                row += 1
            }
        }
        c.restoreGState()
        c.addPath(path)
        c.setStrokeColor(dark ? rgb(255, 255, 255, 0.14) : rgb(0, 0, 0, 0.16))
        c.setLineWidth(1)
        c.strokePath()
    }
}
