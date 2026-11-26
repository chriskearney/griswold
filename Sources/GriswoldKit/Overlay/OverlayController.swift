import AppKit
import MetalKit
import simd

/// A click-through, transparent window that covers one display.
final class OverlayWindow: NSWindow {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        // Above the Dock and menu bar, below menus and alerts.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the window, Metal view and scene for one display.
final class OverlayController: NSObject, MTKViewDelegate {
    let displayID: CGDirectDisplayID
    let scene: ScreenScene
    private let window: OverlayWindow
    private let view: MTKView
    private let renderer: Renderer
    private weak var manager: OverlayManager?
    private let batch = RenderBatch()
    private let buffers = FrameBuffers()
    private let frostMask = FrostMaskTexture()
    private var lastFrame: Double?
    private(set) var isRunning = false

    init(screen: NSScreen, displayID: CGDirectDisplayID, renderer: Renderer, manager: OverlayManager) {
        self.displayID = displayID
        self.renderer = renderer
        self.manager = manager
        let geometry = OverlayController.geometry(for: screen, displayID: displayID)
        scene = ScreenScene(frame: geometry.frame, topInset: geometry.topInset, seed: UInt64(displayID))

        window = OverlayWindow(frame: screen.frame)
        view = MTKView(frame: CGRect(origin: .zero, size: screen.frame.size), device: renderer.device)
        view.colorPixelFormat = Renderer.pixelFormat
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.autoresizingMask = [.width, .height]
        view.layer?.isOpaque = false
        // The drawable is sized by hand (see `applyDrawableSize`).
        view.autoResizeDrawable = false
        super.init()
        view.delegate = self
        window.contentView = view
        // Two buffers are enough for a view that never falls behind, and each
        // one is a full-screen surface.
        (view.layer as? CAMetalLayer)?.maximumDrawableCount = 2
        applyDrawableSize(for: screen)
    }

    /// Most displays render at native resolution. Very large ones (5K and up)
    /// render a little under it: snow and glow are soft by nature, and a
    /// full-resolution 6K overlay costs a quarter of a gigabyte for no visible gain.
    private static let pixelBudget: CGFloat = 10_000_000

    private func applyDrawableSize(for screen: NSScreen) {
        let points = screen.frame.size
        guard points.width > 0, points.height > 0 else { return }
        let fitted = (OverlayController.pixelBudget / (points.width * points.height)).squareRoot()
        let scale = max(1, min(screen.backingScaleFactor, fitted))
        let size = CGSize(width: (points.width * scale).rounded(), height: (points.height * scale).rounded())
        if view.drawableSize != size { view.drawableSize = size }
    }

    /// The display's rectangle in global top-left coordinates, and its menu bar height.
    static func geometry(for screen: NSScreen, displayID: CGDirectDisplayID) -> (frame: CGRect, topInset: Float) {
        let frame = CGDisplayBounds(displayID)
        let inset = screen.frame.maxY - screen.visibleFrame.maxY
        return (frame, Float(max(inset, 0)))
    }

    func update(screen: NSScreen) {
        let geometry = OverlayController.geometry(for: screen, displayID: displayID)
        scene.resize(frame: geometry.frame, topInset: geometry.topInset)
        if window.frame != screen.frame {
            window.setFrame(screen.frame, display: false)
        }
        applyDrawableSize(for: screen)
    }

    func setRunning(_ running: Bool, framesPerSecond: Int) {
        if view.preferredFramesPerSecond != framesPerSecond {
            view.preferredFramesPerSecond = framesPerSecond
        }
        guard running != isRunning else { return }
        isRunning = running
        if running {
            lastFrame = nil
            window.orderFrontRegardless()
            view.isPaused = false
        } else {
            view.isPaused = true
            window.orderOut(nil)
        }
    }

    func close() {
        view.isPaused = true
        view.delegate = nil
        window.orderOut(nil)
        window.close()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let manager else { return }
        let now = manager.now()
        let dt = Float(min(max(now - (lastFrame ?? now - 1.0 / 60.0), 0), 1.0 / 12.0))
        lastFrame = now

        let config = manager.settings.config
        manager.beginFrame(now: now)
        let world = manager.director.world
        scene.step(dt: dt, now: now, config: config, world: world,
                   cursor: manager.cursor, cursorVelocity: manager.cursorVelocity)

        batch.reset()
        scene.build(batch, atlas: renderer.atlas, world: world, config: config)

        guard
            let drawable = view.currentDrawable,
            let pass = view.currentRenderPassDescriptor,
            let commands = renderer.queue.makeCommandBuffer(),
            let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        let bounds = view.bounds.size
        let scale = bounds.width > 0 ? Float(view.drawableSize.width / bounds.width) : 2
        renderer.encode(batch, buffers: buffers, encoder: encoder,
                        viewport: SIMD2(Float(bounds.width), Float(bounds.height)),
                        scale: scale, time: world.time,
                        mask: frostMask.texture(for: scene, device: renderer.device))
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }
}
