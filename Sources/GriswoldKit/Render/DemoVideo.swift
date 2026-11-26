import AppKit
import AVFoundation
import CoreGraphics
import CoreText
import Metal
import simd

/// Renders a short captioned demo film with the real simulation, over a
/// stand-in desktop. Nothing here is used by the running app.
public enum DemoVideo {
    static let size = CGSize(width: 1280, height: 720)
    /// Pixels per point: 1.5 gives 1920 x 1080, 1 gives 1280 x 720.
    private static var scale: CGFloat = 1.5
    static let duration: Double = 46
    static let menuBar: CGFloat = 24

    private enum Kind { case terminal, editor, monitor }
    private struct Window {
        var id: UInt32
        var rect: CGRect
        var kind: Kind
        var title: String
    }

    // The script: what is on screen when.
    private static let captions: [(from: Double, to: Double, text: String)] = [
        (4.2, 8.3, "Snow piles up on your windows."),
        (8.7, 13.8, "Move a window and it falls off."),
        (14.2, 19.4, "Sometimes a squirrel gets loose."),
        (19.8, 24.8, "Or somebody greases the sled."),
        (25.2, 30.8, "Frost creeps in. Wipe it off."),
        (31.2, 40.6, "And every so often, the lights do this."),
    ]

    private static func smooth(_ t: Double, _ a: Double, _ b: Double) -> CGFloat {
        let u = min(max((t - a) / (b - a), 0), 1)
        return CGFloat(u * u * (3 - 2 * u))
    }

    /// Where the terminal window is at time `t`: dragged aside, then part of the way back.
    private static func terminalOrigin(at t: Double) -> CGPoint {
        let base = CGPoint(x: 500, y: 250)
        let out = smooth(t, 9.3, 10.7)
        let back = smooth(t, 11.7, 13.0)
        return CGPoint(x: base.x + 200 * out - 70 * back, y: base.y + 44 * out - 96 * back)
    }

    /// The pointer's position and opacity at time `t`, if it is on screen.
    private static func pointer(at t: Double) -> (position: CGPoint, alpha: CGFloat)? {
        func along(_ points: [CGPoint], _ u: CGFloat) -> CGPoint {
            let scaled = u * CGFloat(points.count - 1)
            let index = min(Int(scaled), points.count - 2)
            let f = scaled - CGFloat(index)
            return CGPoint(x: points[index].x + (points[index + 1].x - points[index].x) * f,
                           y: points[index].y + (points[index + 1].y - points[index].y) * f)
        }
        if t >= 8.3, t < 14.4 {
            // Comes in, takes hold of the terminal's title bar, drags it, lets go.
            let grip = CGPoint(x: terminalOrigin(at: t).x + 330, y: terminalOrigin(at: t).y + 15)
            let arrive = smooth(t, 8.4, 9.2)
            let leave = smooth(t, 13.2, 14.2)
            let start = CGPoint(x: 880, y: 560)
            let end = CGPoint(x: 1010, y: 610)
            var p = CGPoint(x: start.x + (grip.x - start.x) * arrive, y: start.y + (grip.y - start.y) * arrive)
            p = CGPoint(x: p.x + (end.x - p.x) * leave, y: p.y + (end.y - p.y) * leave)
            return (p, min(smooth(t, 8.3, 8.6), 1 - smooth(t, 14.0, 14.4)))
        }
        if t >= 25.4, t < 31.0 {
            let path = [CGPoint(x: 240, y: 190), CGPoint(x: 90, y: 60), CGPoint(x: 380, y: 44), CGPoint(x: 640, y: 70),
                        CGPoint(x: 900, y: 40), CGPoint(x: 1170, y: 66), CGPoint(x: 1236, y: 250), CGPoint(x: 1216, y: 470),
                        CGPoint(x: 1100, y: 560)]
            return (along(path, smooth(t, 25.8, 30.4)), min(smooth(t, 25.4, 25.8), 1 - smooth(t, 30.6, 31.0)))
        }
        return nil
    }

    public static func render(to url: URL, framesPerSecond: Int = 60, limit: Double? = nil,
                              pixelsPerPoint: Double = 1.5, bitRate: Int = 8_000_000, poster: URL? = nil,
                              progress: (Double) -> Void = { _ in }) -> Bool {
        scale = CGFloat(pixelsPerPoint)
        guard let renderer = Renderer() else { return false }
        let pixelWidth = Int(size.width * scale), pixelHeight = Int(size.height * scale)
        let total = min(limit ?? duration, duration)
        let frames = Int(total * Double(framesPerSecond))
        let step = 1.0 / Double(framesPerSecond)

        // --- Encoder ---
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return false }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: framesPerSecond,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: pixelWidth,
            kCVPixelBufferHeightKey as String: pixelHeight,
        ])
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)

        // --- World ---
        let frame = CGRect(origin: .zero, size: size)
        let scene = ScreenScene(frame: frame, topInset: Float(menuBar), seed: 11)
        let director = Director()
        director.scenes = { [scene] }
        director.desktopBounds = { frame }
        var config = Config()
        config.surpriseFrequency = .off
        config.snowIntensity = 0.5
        config.accumulation = .deep
        config.bulbScale = 1.25
        config.spacing = 1.1
        config.glow = 0.85

        // Front to back.
        var windows = [
            Window(id: 1, rect: CGRect(origin: terminalOrigin(at: 0), size: CGSize(width: 640, height: 392)), kind: .terminal, title: "griswold — zsh"),
            Window(id: 2, rect: CGRect(x: 916, y: 62, width: 306, height: 204), kind: .monitor, title: "Activity"),
            Window(id: 3, rect: CGRect(x: 52, y: 104, width: 610, height: 474), kind: .editor, title: "SnowPile.swift"),
        ]
        func infos() -> [WindowInfo] { windows.map { WindowInfo(id: $0.id, frame: $0.rect) } }

        // Let the snow settle before the camera rolls.
        var now = 0.0
        scene.setWindows(infos(), now: now, spaceChangedAt: -100, fullscreenHint: false, config: config)
        director.advance(now: now, config: config)
        while now < 150 {
            now += 1.0 / 60
            director.advance(now: now, config: config)
            scene.step(dt: 1.0 / 60, now: now, config: config, world: director.world, cursor: nil, cursorVelocity: .zero)
        }
        let start = now

        // --- GPU resources ---
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Renderer.pixelFormat, width: pixelWidth, height: pixelHeight, mipmapped: false
        )
        targetDescriptor.usage = [.renderTarget, .shaderRead]
        targetDescriptor.storageMode = .shared
        guard let target = renderer.device.makeTexture(descriptor: targetDescriptor) else { return false }
        let viewport = SIMD2(Float(size.width), Float(size.height))
        let buffers = (0..<4).map { _ in FrameBuffers() }
        let frostMask = FrostMaskTexture()
        let batch = RenderBatch()
        var backdrop = texture(device: renderer.device) { paintDesktop($0, windows: windows) }
        var overlay: MTLTexture?
        var overlayKey = ""
        var fired: Set<String> = []
        var lastPointer: CGPoint?

        for index in 0..<frames {
            let t = Double(index) * step
            now = start + t

            // Script: move the terminal, fire the surprises.
            let origin = terminalOrigin(at: t)
            if origin != windows[0].rect.origin {
                windows[0].rect.origin = origin
                scene.setWindows(infos(), now: now, spaceChangedAt: -100, fullscreenHint: false, config: config)
                backdrop = texture(device: renderer.device) { paintDesktop($0, windows: windows) }
            }
            func once(_ key: String, at time: Double, _ action: () -> Void) {
                if t >= time, !fired.contains(key) {
                    fired.insert(key)
                    action()
                }
            }
            once("frost", at: 16.5) { director.trigger(.frost, now: now, config: config) }
            once("squirrel", at: 14.4) { director.trigger(.squirrel, now: now, config: config) }
            once("sled", at: 19.9) { director.trigger(.sled, now: now, config: config) }
            once("melt", at: 30.6) { director.meltFrost(now: now) }
            once("griswold", at: 31.3) { director.trigger(.griswold, now: now, config: config) }
            once("santa", at: 37.2) { director.trigger(.santa, now: now, config: config) }

            let hand = pointer(at: t)
            var velocity = SIMD2<Float>.zero
            if let hand, let last = lastPointer {
                velocity = SIMD2(Float(hand.position.x - last.x), Float(hand.position.y - last.y)) / Float(step)
            }
            lastPointer = hand?.position
            director.advance(now: now, config: config)
            scene.step(dt: Float(step), now: now, config: config, world: director.world,
                       cursor: hand?.position, cursorVelocity: velocity)

            // Titles and captions are drawn into one overlay, redrawn only when they change.
            var card: (key: String, alpha: CGFloat, draw: (CGContext) -> Void)?
            if t < 3.9 {
                card = ("title", min(smooth(t, 0.3, 1.0), 1 - smooth(t, 3.2, 3.9)), { paintTitle($0) })
            } else if t >= 40.9 {
                card = ("end", smooth(t, 40.9, 41.7), { paintEndCard($0) })
            } else if let caption = captions.first(where: { t >= $0.from && t < $0.to }) {
                card = (caption.text, min(smooth(t, caption.from, caption.from + 0.35), 1 - smooth(t, caption.to - 0.35, caption.to)),
                        { paintCaption($0, caption.text) })
            }
            if let card, card.key != overlayKey {
                overlayKey = card.key
                overlay = texture(device: renderer.device, draw: card.draw)
            }

            // --- Draw ---
            guard let commands = renderer.queue.makeCommandBuffer() else { return false }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return false }
            let time = director.world.time
            func full(_ alpha: Float) -> RenderBatch {
                let b = RenderBatch()
                b.add(SpriteInstance(pos: viewport * 0.5, size: viewport, color: SIMD4(1, 1, 1, alpha), shape: Shape.atlas))
                return b
            }
            if let backdrop {
                renderer.encode(full(1), buffers: buffers[0], encoder: encoder, viewport: viewport,
                                scale: Float(scale), time: time, texture: backdrop)
            }
            batch.reset()
            scene.build(batch, atlas: renderer.atlas, world: director.world, config: config)
            if let hand, hand.alpha > 0.01 {
                let extent = renderer.atlas.size(.pointer)
                batch.add(SpriteInstance(
                    pos: SIMD2(Float(hand.position.x) + extent.x * 0.5 - 3, Float(hand.position.y) + extent.y * 0.5 - 2),
                    size: extent, color: SIMD4(1, 1, 1, Float(hand.alpha)), uv: renderer.atlas.uv(.pointer), shape: Shape.atlas
                ))
            }
            renderer.encode(batch, buffers: buffers[1], encoder: encoder, viewport: viewport, scale: Float(scale),
                            time: time, mask: frostMask.texture(for: scene, device: renderer.device))
            if let card, let overlay, card.alpha > 0.01 {
                renderer.encode(full(Float(card.alpha)), buffers: buffers[2], encoder: encoder, viewport: viewport,
                                scale: Float(scale), time: time, texture: overlay)
            }
            encoder.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()

            // --- Encode ---
            while !input.isReadyForMoreMediaData { usleep(2000) }
            guard let pool = adaptor.pixelBufferPool else { return false }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard let pixelBuffer else { return false }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                target.getBytes(base, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                from: MTLRegionMake2D(0, 0, pixelWidth, pixelHeight), mipmapLevel: 0)
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(framesPerSecond))) else {
                return false
            }
            // The still shown before the film plays: six seconds in, snow on every window.
            if let poster, index == min(6 * framesPerSecond, frames - 1) {
                var still = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
                still.withUnsafeMutableBytes { raw in
                    target.getBytes(raw.baseAddress!, bytesPerRow: pixelWidth * 4,
                                    from: MTLRegionMake2D(0, 0, pixelWidth, pixelHeight), mipmapLevel: 0)
                }
                let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
                if let provider = CGDataProvider(data: Data(still) as CFData),
                   let image = CGImage(width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                                       bytesPerRow: pixelWidth * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider, decode: nil,
                                       shouldInterpolate: true, intent: .defaultIntent) {
                    Snapshot.write(image, to: poster)
                }
            }
            if index % 30 == 0 { progress(Double(index) / Double(frames)) }
        }

        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        progress(1)
        return writer.status == .completed
    }

    // MARK: Painting

    /// Draws into a full-frame bitmap (points, origin top-left) and uploads it.
    private static func texture(device: MTLDevice, draw: (CGContext) -> Void) -> MTLTexture? {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let ok: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let c = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            c.translateBy(x: 0, y: CGFloat(height))
            c.scaleBy(x: scale, y: -scale)
            draw(c)
            return true
        }
        guard ok else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        pixels.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: raw.baseAddress!, bytesPerRow: width * 4)
        }
        return texture
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor { ArtPainter.rgb(r, g, b, a) }
    private static func mono(_ size: CGFloat, bold: Bool = false) -> CTFont {
        CTFontCreateWithName((bold ? "Menlo-Bold" : "Menlo-Regular") as CFString, size, nil)
    }

    private static func paintDesktop(_ c: CGContext, windows: [Window]) {
        DesktopPainter.paint(c, size: size, windows: [], topInset: menuBar, dark: true)
        for window in windows.reversed() {
            let rect = window.rect
            let path = CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: -16), blur: 38, color: CGColor(gray: 0, alpha: 0.55))
            c.setFillColor(window.kind == .terminal ? rgb(0x12, 0x14, 0x1C) : rgb(0x1D, 0x1F, 0x27))
            c.addPath(path)
            c.fillPath()
            c.restoreGState()

            c.saveGState()
            c.addPath(path)
            c.clip()
            c.setFillColor(rgb(0x2A, 0x2C, 0x37))
            c.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 30))
            for (i, colour) in [rgb(0xFF, 0x5F, 0x57), rgb(0xFE, 0xBC, 0x2E), rgb(0x28, 0xC8, 0x40)].enumerated() {
                c.setFillColor(colour)
                c.fillEllipse(in: CGRect(x: rect.minX + 12 + CGFloat(i) * 19, y: rect.minY + 9.5, width: 11.5, height: 11.5))
            }
            BrandArt.draw(c, window.title, at: CGPoint(x: rect.midX, y: rect.minY + 19.5),
                          font: NSFont.systemFont(ofSize: 12, weight: .semibold) as CTFont,
                          colour: CGColor(gray: 1, alpha: 0.62), centred: true)
            let body = CGRect(x: rect.minX, y: rect.minY + 30, width: rect.width, height: rect.height - 30)
            switch window.kind {
            case .terminal: paintTerminal(c, in: body)
            case .editor: paintEditor(c, in: body)
            case .monitor: paintMonitor(c, in: body)
            }
            c.restoreGState()
            c.addPath(path)
            c.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
            c.setLineWidth(1)
            c.strokePath()
        }
    }

    private static func paintTerminal(_ c: CGContext, in body: CGRect) {
        let font = mono(10.6), bold = mono(10.6, bold: true)
        let line: CGFloat = 14.2
        let green = rgb(0x5F, 0xD7, 0x7A), text = rgb(0xD7, 0xDD, 0xEA), dim = rgb(0x8A, 0x93, 0xA8)
        var y = body.minY + 20
        let x = body.minX + 16
        BrandArt.draw(c, "griswold@northpole", at: CGPoint(x: x, y: y), font: bold, colour: green)
        BrandArt.draw(c, " ~ % neofetch", at: CGPoint(x: x + 115, y: y), font: font, colour: text)
        y += line * 1.5

        // The macOS logo neofetch prints, in its usual stripes.
        let logo = [
            "                    'c.", "                 ,xNMM.", "               .OMMMMo", "               OMMM0,",
            "     .;loddo:' loolloddol;.", "   cKMMMMMMMMMMNWMMMMMMMMMM0:", " .KMMMMMMMMMMMMMMMMMMMMMMMWd.",
            " XMMMMMMMMMMMMMMMMMMMMMMMX.", ";MMMMMMMMMMMMMMMMMMMMMMMM:", ":MMMMMMMMMMMMMMMMMMMMMMMM:",
            ".MMMMMMMMMMMMMMMMMMMMMMMMX.", " kMMMMMMMMMMMMMMMMMMMMMMMMWd.", " .XMMMMMMMMMMMMMMMMMMMMMMMMMMk",
            "  .XMMMMMMMMMMMMMMMMMMMMMMMMK.", "    kMMMMMMMMMMMMMMMMMMMMMMd", "     ;KMMMMMMMWXXWMMMMMMMk.",
            "       .cooc,.    .,coo:.",
        ]
        let stripes = [rgb(0x5F, 0xD7, 0x5F), rgb(0x5F, 0xD7, 0x5F), rgb(0x5F, 0xD7, 0x5F), rgb(0x5F, 0xD7, 0x5F),
                       rgb(0x5F, 0xD7, 0x5F), rgb(0xEB, 0xD0, 0x4A), rgb(0xEB, 0xD0, 0x4A), rgb(0xF0, 0x93, 0x3B),
                       rgb(0xF0, 0x93, 0x3B), rgb(0xE5, 0x4B, 0x4B), rgb(0xE5, 0x4B, 0x4B), rgb(0xB5, 0x6C, 0xE0),
                       rgb(0xB5, 0x6C, 0xE0), rgb(0xB5, 0x6C, 0xE0), rgb(0x4F, 0x9D, 0xF0), rgb(0x4F, 0x9D, 0xF0),
                       rgb(0x4F, 0x9D, 0xF0)]
        let info: [(String, String)] = [
            ("", "griswold@northpole"), ("", "------------------"),
            ("OS", "macOS 27.2 arm64"), ("Host", "MacBook Pro"), ("Kernel", "27.2.0"), ("Uptime", "25 days"),
            ("Shell", "zsh 5.9"), ("WM", "Quartz Compositor"), ("Terminal", "Apple_Terminal"),
            ("CPU", "Apple silicon"), ("Memory", "9187MiB / 36864MiB"),
            ("Lights", "25,000 (twinkle)"), ("Snow", "accumulating"), ("Squirrels", "1 (loose)"),
        ]
        let infoX = x + 222
        for (row, text) in logo.enumerated() {
            BrandArt.draw(c, text, at: CGPoint(x: x, y: y + CGFloat(row) * line), font: bold, colour: stripes[row])
        }
        for (row, entry) in info.enumerated() {
            let rowY = y + CGFloat(row) * line
            if entry.0.isEmpty {
                BrandArt.draw(c, entry.1, at: CGPoint(x: infoX, y: rowY), font: bold, colour: row == 0 ? green : dim)
            } else {
                BrandArt.draw(c, entry.0, at: CGPoint(x: infoX, y: rowY), font: bold, colour: rgb(0xEB, 0xD0, 0x4A))
                let offset = CGFloat(entry.0.count) * 6.38
                BrandArt.draw(c, ": " + entry.1, at: CGPoint(x: infoX + offset, y: rowY), font: font, colour: text)
            }
        }
        // The colour blocks neofetch ends with.
        let blocks = [rgb(0x2E, 0x34, 0x40), rgb(0xE5, 0x4B, 0x4B), rgb(0x5F, 0xD7, 0x5F), rgb(0xEB, 0xD0, 0x4A),
                      rgb(0x4F, 0x9D, 0xF0), rgb(0xB5, 0x6C, 0xE0), rgb(0x4F, 0xC8, 0xD8), rgb(0xD7, 0xDD, 0xEA)]
        let blockY = y + CGFloat(info.count) * line + 4
        for (i, colour) in blocks.enumerated() {
            c.setFillColor(colour)
            c.fill(CGRect(x: infoX + CGFloat(i) * 19, y: blockY - 9, width: 19, height: 13))
        }
        let promptY = y + CGFloat(logo.count) * line + 12
        BrandArt.draw(c, "griswold@northpole", at: CGPoint(x: x, y: promptY), font: bold, colour: green)
        BrandArt.draw(c, " ~ %", at: CGPoint(x: x + 115, y: promptY), font: font, colour: text)
        c.setFillColor(text)
        c.fill(CGRect(x: x + 148, y: promptY - 10, width: 7, height: 13))
    }

    private static func paintEditor(_ c: CGContext, in body: CGRect) {
        // A gutter and a real excerpt from this app's snow code.
        c.setFillColor(rgb(0x18, 0x1A, 0x21))
        c.fill(CGRect(x: body.minX, y: body.minY, width: 40, height: body.height))
        let font = mono(10.4)
        let pink = rgb(0xF2, 0x7A, 0xB0), teal = rgb(0x6B, 0xD5, 0xC9), plain = rgb(0xD7, 0xDD, 0xEA)
        let comment = rgb(0x7F, 0x92, 0x86), number = rgb(0xE8, 0xB8, 0x6A)
        let lines: [[(String, CGColor)]] = [
            [("/// Adds snow at `x`. `amount` is an area in square points.", comment)],
            [("@discardableResult", pink)],
            [("public func ", pink), ("deposit", teal), ("(x: ", plain), ("Float", teal), (", amount: ", plain), ("Float", teal), (") -> ", plain), ("Bool", teal), (" {", plain)],
            [("    let ", pink), ("i = ", plain), ("Int", teal), ("((x - originX) / ", plain), ("SnowPile", teal), (".cell)", plain)],
            [("    guard ", pink), ("i >= ", plain), ("0", number), (", i < heights.count ", plain), ("else", pink), (" { ", plain), ("return false", pink), (" }", plain)],
            [("    let ", pink), ("cap = limit(at: i)", plain)],
            [("    // Fill more reluctantly near the top, so piles round off.", comment)],
            [("    if ", pink), ("heights[i] / cap >= ", plain), ("1", number), (" { ", plain), ("return false", pink), (" }", plain)],
            [],
            [("    // A flake is wider than one cell; the overlap is what keeps", comment)],
            [("    // the surface from looking like a bar chart.", comment)],
            [("    let ", pink), ("rise = amount / ", plain), ("SnowPile", teal), (".cell", plain)],
            [("    heights[i] += rise * ", plain), ("0.30", number)],
            [("    heights[max(i - ", plain), ("1", number), (", ", plain), ("0", number), (")] += rise * ", plain), ("0.25", number)],
            [("    heights[min(i + ", plain), ("1", number), (", last)] += rise * ", plain), ("0.25", number)],
            [("    heights[max(i - ", plain), ("2", number), (", ", plain), ("0", number), (")] += rise * ", plain), ("0.10", number)],
            [("    heights[min(i + ", plain), ("2", number), (", last)] += rise * ", plain), ("0.10", number)],
            [("    settled = ", plain), ("false", pink)],
            [("    return true", pink)],
            [("}", plain)],
            [],
            [("/// Lets over-steep columns slump onto their neighbours.", comment)],
            [("public func ", pink), ("relax", teal), ("() {", plain)],
            [("    guard ", pink), ("!settled, heights.count > ", plain), ("1", number), (" else", pink), (" { ", plain), ("return", pink), (" }", plain)],
            [("    let ", pink), ("maxStep: ", plain), ("Float", teal), (" = ", plain), ("0.85", number), (" * ", plain), ("SnowPile", teal), (".cell", plain)],
            [("    var ", pink), ("moved = ", plain), ("false", pink)],
            [("    for ", pink), ("i ", plain), ("in ", pink), ("0", number), ("..<(heights.count - ", plain), ("1", number), (") {", plain)],
            [("        let ", pink), ("difference = heights[i] - heights[i + ", plain), ("1", number), ("]", plain)],
        ]
        var y = body.minY + 20
        for (index, segments) in lines.enumerated() {
            BrandArt.draw(c, String(format: "%3d", index + 41), at: CGPoint(x: body.minX + 10, y: y), font: font, colour: rgb(0x5A, 0x62, 0x76))
            var x = body.minX + 52
            for (text, colour) in segments {
                BrandArt.draw(c, text, at: CGPoint(x: x, y: y), font: font, colour: colour)
                x += CGFloat(text.count) * 6.26
            }
            y += 15.2
            if y > body.maxY - 8 { break }
        }
    }

    private static func paintMonitor(_ c: CGContext, in body: CGRect) {
        let font = mono(9.6)
        let dim = rgb(0x8A, 0x93, 0xA8)
        let loads: [CGFloat] = [0.34, 0.22, 0.41, 0.18, 0.09, 0.12, 0.06, 0.08]
        var y = body.minY + 20
        for (core, load) in loads.enumerated() {
            BrandArt.draw(c, "\(core)", at: CGPoint(x: body.minX + 14, y: y), font: font, colour: dim)
            let track = CGRect(x: body.minX + 30, y: y - 8, width: body.width - 86, height: 9)
            c.setFillColor(rgb(255, 255, 255, 0.07))
            c.addPath(CGPath(roundedRect: track, cornerWidth: 3, cornerHeight: 3, transform: nil))
            c.fillPath()
            c.setFillColor(load > 0.3 ? rgb(0xEB, 0xD0, 0x4A) : rgb(0x5F, 0xD7, 0x7A))
            c.addPath(CGPath(roundedRect: CGRect(x: track.minX, y: track.minY, width: track.width * load, height: 9),
                             cornerWidth: 3, cornerHeight: 3, transform: nil))
            c.fillPath()
            BrandArt.draw(c, String(format: "%2.0f%%", load * 100), at: CGPoint(x: track.maxX + 8, y: y), font: font, colour: dim)
            y += 16.5
        }
        BrandArt.draw(c, "Mem", at: CGPoint(x: body.minX + 14, y: y + 6), font: font, colour: dim)
        let track = CGRect(x: body.minX + 40, y: y - 2, width: body.width - 96, height: 9)
        c.setFillColor(rgb(255, 255, 255, 0.07))
        c.addPath(CGPath(roundedRect: track, cornerWidth: 3, cornerHeight: 3, transform: nil))
        c.fillPath()
        c.setFillColor(rgb(0x4F, 0x9D, 0xF0))
        c.addPath(CGPath(roundedRect: CGRect(x: track.minX, y: track.minY, width: track.width * 0.25, height: 9),
                         cornerWidth: 3, cornerHeight: 3, transform: nil))
        c.fillPath()
        BrandArt.draw(c, "25%", at: CGPoint(x: track.maxX + 8, y: y + 6), font: font, colour: dim)
    }

    private static func paintCaption(_ c: CGContext, _ text: String) {
        let font = BrandArt.roundedFont(size: 27, weight: .bold)
        let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let width = CTLineGetBoundsWithOptions(line, .useOpticalBounds).width
        let pill = CGRect(x: size.width / 2 - width / 2 - 24, y: size.height - 96, width: width + 48, height: 52)
        c.setFillColor(rgb(6, 9, 22, 0.78))
        c.addPath(CGPath(roundedRect: pill, cornerWidth: 26, cornerHeight: 26, transform: nil))
        c.fillPath()
        c.setStrokeColor(CGColor(gray: 1, alpha: 0.16))
        c.setLineWidth(1)
        c.addPath(CGPath(roundedRect: pill.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 25.5, cornerHeight: 25.5, transform: nil))
        c.strokePath()
        BrandArt.draw(c, text, at: CGPoint(x: size.width / 2, y: pill.maxY - 17), font: font,
                      colour: CGColor(gray: 1, alpha: 1), centred: true)
    }

    private static func paintTitle(_ c: CGContext) {
        c.setFillColor(rgb(5, 8, 22, 0.55))
        c.fill(CGRect(origin: .zero, size: size))
        if let icon = BrandArt.icon() {
            c.saveGState()
            c.translateBy(x: size.width / 2 - 62, y: 176 + 124)
            c.scaleBy(x: 1, y: -1)
            c.draw(icon, in: CGRect(x: 0, y: 0, width: 124, height: 124))
            c.restoreGState()
        }
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -6), blur: 28, color: CGColor(gray: 0, alpha: 0.6))
        BrandArt.draw(c, "Griswold", at: CGPoint(x: size.width / 2, y: 420), font: BrandArt.roundedFont(size: 118, weight: .heavy),
                      colour: CGColor(gray: 1, alpha: 1), centred: true, tracking: -2)
        BrandArt.draw(c, "Snow and Christmas lights for your Mac", at: CGPoint(x: size.width / 2, y: 478),
                      font: BrandArt.roundedFont(size: 32, weight: .semibold), colour: CGColor(gray: 1, alpha: 0.9), centred: true)
        c.restoreGState()
    }

    private static func paintEndCard(_ c: CGContext) {
        c.setFillColor(rgb(5, 8, 22, 0.62))
        c.fill(CGRect(origin: .zero, size: size))
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -6), blur: 28, color: CGColor(gray: 0, alpha: 0.6))
        BrandArt.draw(c, "Griswold", at: CGPoint(x: size.width / 2, y: 330), font: BrandArt.roundedFont(size: 104, weight: .heavy),
                      colour: CGColor(gray: 1, alpha: 1), centred: true, tracking: -2)
        BrandArt.draw(c, "Free and open source, for macOS", at: CGPoint(x: size.width / 2, y: 392),
                      font: BrandArt.roundedFont(size: 30, weight: .semibold), colour: CGColor(gray: 1, alpha: 0.9), centred: true)
        BrandArt.draw(c, "chonkbase.net/griswold", at: CGPoint(x: size.width / 2, y: 462),
                      font: BrandArt.roundedFont(size: 40, weight: .bold), colour: rgb(0xF2, 0xC1, 0x4B), centred: true)
        c.restoreGState()
    }
}
