import AppKit
import Combine
import IOKit.ps
import simd

/// Runs the show: one overlay per display, the shared window tracker and
/// director, and the rules for when to draw fast, slow, or not at all.
public final class OverlayManager {
    public let settings: Settings
    public let director = Director()
    let tracker = WindowTracker()
    private let renderer: Renderer?
    private let audio = Jingle()
    private var controllers: [CGDirectDisplayID: OverlayController] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var housekeeping: Timer?
    private let epoch = CACurrentMediaTime()

    private var displaysAsleep = false
    private var sessionInactive = false
    private var screenLocked = false
    private var onBattery = false
    private var lastPowerCheck: Double = -100
    private var seenGeneration = -1
    private var frameStamp: Double = -1
    private var appliedMainOnly = false

    private(set) var cursor: CGPoint?
    private(set) var cursorVelocity: SIMD2<Float> = .zero
    private var cursorStamp: Double = 0

    public init(settings: Settings) {
        self.settings = settings
        renderer = Renderer()
        director.scenes = { [weak self] in self?.controllers.values.map(\.scene) ?? [] }
        director.desktopBounds = { [weak self] in
            self?.controllers.values.reduce(CGRect.null) { $0.union($1.scene.frame) } ?? .zero
        }
        director.onSound = { [weak self] cue in
            guard let self, self.settings.config.soundEnabled else { return }
            self.audio.play(cue, volume: Float(self.settings.config.volume))
        }
    }

    public var isAvailable: Bool { renderer != nil }

    /// Seconds since launch. Kept relative so single-precision time stays smooth.
    func now() -> Double { CACurrentMediaTime() - epoch }

    public func start() {
        guard renderer != nil else { return }
        rebuildScreens()

        let centre = NotificationCenter.default
        observe(centre, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.rebuildScreens()
        }
        observe(centre, .NSProcessInfoPowerStateDidChange) { [weak self] in self?.refresh() }

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.displaysAsleep = true
            self?.refresh()
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.displaysAsleep = false
            self?.refresh()
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            self?.sessionInactive = true
            self?.refresh()
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.sessionInactive = false
            self?.refresh()
        }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
            self?.syncWindows(force: true)
        }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.screenLocked = true
            self?.refresh()
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.screenLocked = false
            self?.refresh()
        }

        settings.$config
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.configChanged() }
            .store(in: &cancellables)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        housekeeping = timer
        configChanged()
    }

    private func observe(_ centre: NotificationCenter, _ name: Notification.Name, _ handler: @escaping () -> Void) {
        let token = centre.addObserver(forName: name, object: nil, queue: .main) { _ in handler() }
        observers.append((centre, token))
    }

    public func stop() {
        housekeeping?.invalidate()
        housekeeping = nil
        tracker.stop()
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        cancellables.removeAll()
        controllers.values.forEach { $0.close() }
        controllers.removeAll()
    }

    // MARK: Displays

    private func rebuildScreens() {
        guard let renderer else { return }
        var wanted: [CGDirectDisplayID: NSScreen] = [:]
        let mainOnly = settings.config.mainDisplayOnly
        for (index, screen) in NSScreen.screens.enumerated() {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            // screens[0] is the display with the menu bar.
            if mainOnly, index != 0 { continue }
            wanted[CGDirectDisplayID(number.uint32Value)] = screen
        }
        for (id, controller) in controllers where wanted[id] == nil {
            controller.close()
            controllers[id] = nil
        }
        for (id, screen) in wanted {
            if let existing = controllers[id] {
                existing.update(screen: screen)
            } else {
                controllers[id] = OverlayController(screen: screen, displayID: id, renderer: renderer, manager: self)
            }
        }
        syncWindows(force: true)
        refresh()
    }

    // MARK: Per-frame hooks (called by each display)

    /// Advances the things every display shares, once per instant.
    func beginFrame(now: Double) {
        // Displays draw a few milliseconds apart; treat those as the same instant.
        guard now - frameStamp > 0.004 else { return }
        frameStamp = now
        let config = settings.config
        director.advance(now: now, config: config)
        updateCursor(now: now, enabled: config.cursorPlay && config.snowEnabled)
        if tracker.generation != seenGeneration { syncWindows(force: false) }
    }

    private func updateCursor(now: Double, enabled: Bool) {
        guard enabled, let location = CGEvent(source: nil)?.location else {
            cursor = nil
            cursorVelocity = .zero
            return
        }
        let dt = now - cursorStamp
        if let previous = cursor, dt > 0.0005, dt < 0.25 {
            let instant = SIMD2<Float>(Float(location.x - previous.x), Float(location.y - previous.y)) / Float(dt)
            let limited = simd_clamp(instant, SIMD2(repeating: -2600), SIMD2(repeating: 2600))
            cursorVelocity += (limited - cursorVelocity) * min(Float(dt) * 14, 1)
        } else {
            cursorVelocity = .zero
        }
        cursor = location
        cursorStamp = now
    }

    private func syncWindows(force: Bool) {
        if force { tracker.poll() }
        seenGeneration = tracker.generation
        let config = settings.config
        let fullscreen = NSApp.currentSystemPresentationOptions.contains(.fullScreen)
        let now = self.now()
        let spaceChange = tracker.spaceChangedAt > 0 ? tracker.spaceChangedAt - epoch : -100
        for controller in controllers.values {
            controller.scene.setWindows(tracker.windows, now: now, spaceChangedAt: spaceChange,
                                        fullscreenHint: fullscreen, config: config)
        }
    }

    // MARK: Pacing

    private func configChanged() {
        let config = settings.config
        if config.mainDisplayOnly != appliedMainOnly || controllers.isEmpty {
            appliedMainOnly = config.mainDisplayOnly
            rebuildScreens()
        }
        // Window positions only matter while snow can land on them or hide behind them.
        let needsWindows = config.enabled
            && ((config.snowEnabled && (config.accumulation != .off || config.depthBehindWindows))
                || !config.showOverFullscreen)
        if needsWindows, !tracker.isRunning {
            tracker.start()
        } else if !needsWindows, tracker.isRunning {
            tracker.stop()
        }
        if !config.enabled { director.reset() }
        syncWindows(force: tracker.isRunning)
        refresh()
    }

    private func tick() {
        let now = self.now()
        if now - lastPowerCheck > 15 {
            lastPowerCheck = now
            onBattery = OverlayManager.isOnBattery()
        }
        // Keeps the surprise schedule moving even while every display is idle.
        if !controllers.values.contains(where: { $0.isRunning }) {
            beginFrame(now: now)
        } else if tracker.generation != seenGeneration {
            syncWindows(force: false)
        }
        refresh()
    }

    /// Decides, per display, whether to draw and how often.
    private func refresh() {
        let config = settings.config
        let world = director.world
        let blocked = displaysAsleep || sessionInactive || screenLocked
        let saving = onBattery || ProcessInfo.processInfo.isLowPowerModeEnabled
        for controller in controllers.values {
            let scene = controller.scene
            // With snow or lights on there is always something to draw. Otherwise draw
            // only while something is on screen: a surprise, or the last flakes
            // settling after everything was switched off.
            let always = config.enabled && (config.snowEnabled || config.lightsEnabled)
            let running = !blocked && !scene.isSuspended && (always || scene.hasContent(world: world))
            let rate: Int
            if scene.isCalm(world: world, config: config) {
                rate = 20
            } else {
                switch config.frameRate {
                case .smooth: rate = 60
                case .efficient: rate = 30
                case .auto: rate = saving ? 30 : 60
                }
            }
            controller.setRunning(running, framesPerSecond: rate)
        }
    }

    static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeRetainedValue() as String?
        else { return false }
        return type == kIOPMBatteryPowerKey
    }

    // MARK: Actions

    public func surprise(_ kind: SurpriseKind?) {
        let config = settings.config
        guard config.enabled else { return }
        let pool = SurpriseKind.allCases.filter { kind in
            switch kind {
            case .griswold: return config.lightsEnabled
            case .gust: return config.snowEnabled
            default: return true
            }
        }
        guard let chosen = kind ?? pool.randomElement() else { return }
        director.trigger(chosen, now: now(), config: config)
        refresh()
    }
}
