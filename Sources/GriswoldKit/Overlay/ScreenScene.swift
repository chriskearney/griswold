import CoreGraphics
import Foundation
import simd

/// Everything that happens on one display: its snow, the piles on its windows,
/// its string of lights, and whichever surprises are playing there.
///
/// Coordinates are points with the origin at the display's top-left, y down.
public final class ScreenScene {
    /// The display's rectangle in global coordinates (origin top-left of the main display).
    public private(set) var frame: CGRect
    /// Height of the menu bar on this display, 0 if hidden.
    public private(set) var topInset: Float
    public var size: SIMD2<Float> { SIMD2(Float(frame.width), Float(frame.height)) }
    /// True while a full-screen app owns this display and the user has asked us to stay out of it.
    public private(set) var isSuspended = false

    private let snow: SnowSystem
    private var piles: [UInt32: SnowPile] = [:]
    private var pileSpans: [UInt32: Span] = [:]
    private var missingSince: [UInt32: Double] = [:]
    private var stash: [UInt32: (pile: SnowPile, at: Double)] = [:]
    private var ground: SnowPile
    private var ledges: [Ledge] = []
    private var surfaces: SurfaceMap
    private var hidden: [CGRect] = []
    private var windowFrames: [UInt32: CGRect] = [:]
    private var lastSync: Double = 0
    private var spaceChangedAt: Double = -100

    private var lights: LightString?
    private var lightsOpacity: Float = 0
    private let sparks = SparkSystem()
    private var rng: FastRNG
    private var seenBlaze = 0
    private var time: Float = 0

    // Surprises that live on a single screen.
    private struct ShootingStar {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var age: Float
        var duration: Float
        var length: Float
    }
    private struct Present {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var rotation: Float
        var spin: Float
        var art: Art
        var scale: Float
        var delay: Float
        var age: Float
        var lifetime: Float
        var resting: Bool
    }
    private struct Snowman {
        var x: Float
        var age: Float
        var duration: Float
    }
    private struct Snowball {
        var centre: SIMD2<Float>
        var age: Float
        var rotation: Float
        var scale: Float
        var landed: Bool
    }
    private struct Shell {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var delay: Float
        var colours: [SIMD3<Float>]
    }
    private var stars: [ShootingStar] = []
    private var presents: [Present] = []
    private var snowman: Snowman?
    private var snowballs: [Snowball] = []
    private var shells: [Shell] = []

    public init(frame: CGRect, topInset: Float, seed: UInt64 = 1) {
        self.frame = frame
        self.topInset = topInset
        snow = SnowSystem(seed: 0xA11CE &+ seed &* 977)
        rng = FastRNG(seed: 0xBEEF &+ seed &* 131)
        ground = SnowPile(id: 0, originX: 0, width: Float(frame.width), y: Float(frame.height), maxHeight: 0, tapered: false)
        surfaces = SurfaceMap(width: Float(frame.width))
    }

    /// Called when the display's geometry changes.
    public func resize(frame: CGRect, topInset: Float) {
        guard frame != self.frame || topInset != self.topInset else { return }
        let widthChanged = frame.size != self.frame.size
        self.frame = frame
        self.topInset = topInset
        if widthChanged {
            ground = SnowPile(id: 0, originX: 0, width: Float(frame.width), y: Float(frame.height), maxHeight: 0, tapered: false)
            piles.removeAll()
            pileSpans.removeAll()
            ledges.removeAll()
            surfaces = SurfaceMap(width: Float(frame.width))
            snow.removeAll()
            lights = nil
        }
    }

    // MARK: Windows

    /// Feeds in the latest window list (front to back, global coordinates).
    public func setWindows(_ windows: [WindowInfo], now: Double, spaceChangedAt: Double,
                           fullscreenHint: Bool, config: Config) {
        self.spaceChangedAt = spaceChangedAt
        let fullscreen = LedgeFinder.hasFullscreenWindow(windows: windows, screen: frame)
            || (fullscreenHint && windows.contains { covers($0.frame) })
        isSuspended = fullscreen && !config.showOverFullscreen

        let origin = frame.origin
        windowFrames.removeAll(keepingCapacity: true)
        hidden.removeAll(keepingCapacity: true)
        for window in windows where window.frame.intersects(frame) {
            let local = window.frame.offsetBy(dx: -origin.x, dy: -origin.y)
            windowFrames[window.id] = local
            hidden.append(local.insetBy(dx: 1, dy: 1))
        }

        let accumulate = config.snowEnabled && config.accumulation != .off && !isSuspended
        ledges = accumulate ? LedgeFinder.ledges(windows: windows, screen: frame, topInset: topInset) : []
        var firstLedge: [UInt32: Ledge] = [:]
        for ledge in ledges where firstLedge[ledge.windowID] == nil {
            firstLedge[ledge.windowID] = ledge
        }

        let elapsed = Float(max(now - lastSync, 1.0 / 60.0))
        lastSync = now

        for (id, pile) in piles {
            if let ledge = firstLedge[id] {
                missingSince[id] = nil
                let old = pileSpans[id] ?? Span(pile.originX, pile.originX + pile.width)
                let dy = ledge.y - pile.y
                let dLeft = ledge.windowSpan.lo - old.lo
                let dRight = ledge.windowSpan.hi - old.hi
                let moved = abs(dy) > 1.5 || (abs(dLeft) > 1.5 && abs(dRight - dLeft) < 1.5)
                if moved {
                    // The window was dragged out from under its snow.
                    let velocity = SIMD2<Float>(
                        clamp(dLeft / elapsed * 0.3, -420, 420),
                        clamp(dy / elapsed * 0.3, -260, 420)
                    )
                    shed(pile, velocity: velocity)
                    pile.y = ledge.y
                    pile.reshape(originX: ledge.windowSpan.lo, width: ledge.windowSpan.length)
                } else if abs(dLeft) > 0.5 || abs(dRight) > 0.5 {
                    pile.reshape(originX: ledge.windowSpan.lo, width: ledge.windowSpan.length)
                }
                pileSpans[id] = ledge.windowSpan
            } else if let local = windowFrames[id] {
                // Still here but its top edge is covered: keep the snow unless it moved.
                missingSince[id] = nil
                if abs(Float(local.minY) - pile.y) > 1.5 || abs(Float(local.minX) - pile.originX) > 1.5 {
                    piles[id] = nil
                    pileSpans[id] = nil
                }
            } else if missingSince[id] == nil {
                missingSince[id] = now
            }
        }

        for (id, ledge) in firstLedge where piles[id] == nil {
            if let stashed = stash.removeValue(forKey: id),
               abs(stashed.pile.y - ledge.y) < 1.5, abs(stashed.pile.originX - ledge.windowSpan.lo) < 1.5 {
                piles[id] = stashed.pile
            } else {
                piles[id] = SnowPile(
                    id: id, originX: ledge.windowSpan.lo, width: ledge.windowSpan.length, y: ledge.y,
                    maxHeight: config.accumulation.maxHeight, tapered: true
                )
            }
            pileSpans[id] = ledge.windowSpan
        }

        let map = SurfaceMap(width: Float(frame.width))
        for ledge in ledges {
            guard let pile = piles[ledge.windowID] else { continue }
            map.add(SurfaceMap.Entry(lo: ledge.span.lo, hi: ledge.span.hi, y: ledge.y, pile: pile))
        }
        surfaces = map
    }

    private func covers(_ rect: CGRect) -> Bool {
        abs(rect.width - frame.width) < 2 && rect.height >= frame.height - 44 && abs(rect.maxY - frame.maxY) < 2
    }

    private func shed(_ pile: SnowPile, velocity: SIMD2<Float>) {
        for chunk in pile.shed() {
            snow.addClump(x: chunk.x, y: chunk.y, velocity: velocity, amount: chunk.amount)
            if rng.chance(0.5) {
                snow.addPowder(x: chunk.x, y: chunk.y, velocity: velocity * 0.5, count: 1, life: 0.8)
            }
        }
    }

    /// Windows that vanished: closed ones drop their snow, ones left behind on
    /// another Space keep it for when the user comes back.
    private func resolveMissing(now: Double) {
        guard !missingSince.isEmpty else { return }
        for (id, since) in missingSince where now - since > 0.3 {
            missingSince[id] = nil
            guard let pile = piles.removeValue(forKey: id) else { continue }
            pileSpans[id] = nil
            if abs(now - spaceChangedAt) < 2.0 || abs(since - spaceChangedAt) < 2.0 {
                if !pile.isEmpty { stash[id] = (pile, now) }
            } else {
                shed(pile, velocity: .zero)
            }
        }
        if stash.count > 80 {
            stash = stash.filter { now - $0.value.at < 900 }
        }
    }

    // MARK: Simulation

    public func step(dt: Float, now: Double, config: Config, world: World,
                     cursor: CGPoint?, cursorVelocity: SIMD2<Float>) {
        time = world.time
        let active = config.enabled && !isSuspended
        let snowing = active && config.snowEnabled
        let size = self.size

        snow.target = snowing ? SnowSystem.targetCount(intensity: Float(config.snowIntensity), size: size) : 0

        let pileLimit: Float = snowing ? config.accumulation.maxHeight : 0
        for pile in piles.values {
            pile.maxHeight = pileLimit
            if pileLimit <= 0 { pile.melt(dt * 3) } else { pile.settleToLimit(rate: dt * 4) }
            pile.relax()
        }
        let groundLimit = (snowing && config.groundSnow) ? pileLimit * 1.5 : 0
        ground.maxHeight = groundLimit
        if groundLimit <= 0 { ground.melt(dt * 3) } else { ground.settleToLimit(rate: dt * 4) }
        ground.relax()

        var env = SnowEnvironment(size: size, wind: world.wind, time: time)
        env.flakeScale = Float(config.flakeSize)
        env.surfaces = pileLimit > 0 ? surfaces : nil
        env.ground = groundLimit > 0 ? ground : nil
        if config.cursorPlay, let cursor, frame.insetBy(dx: -100, dy: -100).contains(cursor) {
            env.cursor = SIMD2(Float(cursor.x - frame.minX), Float(cursor.y - frame.minY))
            env.cursorVelocity = cursorVelocity
        }
        snow.update(dt: dt, env: env)

        // A strong gust blows spindrift off the tops of the piles.
        if world.gust > 0.3, pileLimit > 0 {
            let chance = dt * 1.4 * world.gust
            for entry in surfaces.entries {
                for point in entry.pile.skim(&rng, probability: chance, amount: 0.22)
                where point.x >= entry.lo && point.x < entry.hi {
                    snow.addPowder(x: point.x, y: point.y, velocity: SIMD2(world.wind * 0.7, -26), count: 1, life: 1.1)
                }
            }
            for point in ground.skim(&rng, probability: chance * 0.4, amount: 0.2) {
                snow.addPowder(x: point.x, y: point.y, velocity: SIMD2(world.wind * 0.7, -30), count: 1, life: 1.1)
            }
        }

        resolveMissing(now: now)
        piles = piles.filter { id, pile in
            windowFrames[id] != nil || missingSince[id] != nil || !pile.isEmpty
        }

        // Lights fade rather than snap when switched or re-hung.
        let wantLights = active && config.lightsEnabled
        if wantLights {
            let layout = LightString.Layout(size: size, topInset: topInset, config: config)
            if lights?.layout != layout {
                lights = LightString(layout: layout)
            }
        }
        lightsOpacity += ((wantLights ? 1 : 0) - lightsOpacity) * min(dt * 5, 1)
        if !wantLights, lightsOpacity < 0.01 {
            lights = nil
            lightsOpacity = 0
        }

        if world.blazeSerial != seenBlaze {
            seenBlaze = world.blazeSerial
            if wantLights { blazeSparks(config: config) }
        }

        updateSurprises(dt: dt, world: world)
        sparks.update(dt: dt)
    }

    /// False when there is nothing on this display worth a frame.
    public func hasContent(world: World) -> Bool {
        if isSuspended { return false }
        return !snow.isIdle || lights != nil || !sparks.isEmpty || !stars.isEmpty || !presents.isEmpty
            || snowman != nil || !snowballs.isEmpty || !shells.isEmpty || world.aurora > 0.001
            || world.santa != nil || !ground.isEmpty || piles.values.contains { !$0.isEmpty }
    }

    /// True when the picture only changes slowly (steady lights, settled snow).
    public func isCalm(world: World, config: Config) -> Bool {
        snow.isIdle && sparks.isEmpty && stars.isEmpty && presents.isEmpty && snowman == nil
            && snowballs.isEmpty && shells.isEmpty && world.aurora <= 0.001 && world.santa == nil
            && world.boost.level == 1 && world.boost.sputter == 0
            && (lights == nil || config.pattern == .steady || config.pattern == .breathe)
    }

    // MARK: Surprises

    public func startShootingStar() {
        let size = self.size
        let leftToRight = rng.chance(0.5)
        let angle = rng.range(0.22, 0.5)
        let speed = rng.range(900, 1350)
        let start = SIMD2<Float>(
            leftToRight ? rng.range(size.x * 0.05, size.x * 0.55) : rng.range(size.x * 0.45, size.x * 0.95),
            topInset + rng.range(20, size.y * 0.28)
        )
        stars.append(ShootingStar(
            position: start,
            velocity: SIMD2(cosf(angle) * (leftToRight ? 1 : -1), sinf(angle)) * speed,
            age: 0, duration: rng.range(0.75, 1.15), length: rng.range(170, 260)
        ))
    }

    public func startPresents() {
        let size = self.size
        let count = 6 + rng.int(5)
        let arts: [Art] = [.presentRed, .presentGreen, .presentBlue]
        for i in 0..<count {
            presents.append(Present(
                position: SIMD2(rng.range(size.x * 0.08, size.x * 0.92), -30),
                velocity: SIMD2(rng.signed() * 50, rng.range(40, 120)),
                rotation: rng.signed() * 0.6, spin: rng.signed() * 3.2,
                art: arts[rng.int(arts.count)], scale: rng.range(0.95, 1.35),
                delay: Float(i) * rng.range(0.18, 0.5), age: 0, lifetime: rng.range(13, 18), resting: false
            ))
        }
    }

    public func startSnowman() {
        guard snowman == nil else { return }
        let size = self.size
        // Off to one side, clear of the Dock.
        let x = rng.chance(0.5) ? rng.range(70, size.x * 0.16 + 70) : rng.range(size.x * 0.84 - 70, size.x - 70)
        snowman = Snowman(x: x, age: 0, duration: rng.range(34, 46))
    }

    public func startSnowball() {
        let size = self.size
        snowballs.append(Snowball(
            centre: SIMD2(rng.range(size.x * 0.15, size.x * 0.85), rng.range(size.y * 0.18, size.y * 0.6)),
            age: 0, rotation: rng.signed() * 0.3, scale: rng.range(0.9, 1.35), landed: false
        ))
    }

    public func startFireworks() {
        let size = self.size
        let palettes: [[SIMD3<Float>]] = [
            [SIMD3(1.0, 0.25, 0.22), SIMD3(1.0, 0.75, 0.6)],
            [SIMD3(0.2, 0.9, 0.4), SIMD3(0.8, 1.0, 0.8)],
            [SIMD3(1.0, 0.8, 0.25), SIMD3(1.0, 0.95, 0.7)],
            [SIMD3(0.35, 0.6, 1.0), SIMD3(0.85, 0.92, 1.0)],
            [SIMD3(0.9, 0.4, 1.0), SIMD3(1.0, 0.8, 1.0)],
        ]
        var delay: Float = 0
        for _ in 0..<(11 + rng.int(5)) {
            shells.append(Shell(
                position: SIMD2(rng.range(size.x * 0.15, size.x * 0.85), size.y + 10),
                // Launch speed chosen so the shell tops out in the upper half of the screen.
                velocity: SIMD2(rng.signed() * 60, -sqrtf(2 * 520 * size.y * rng.range(0.5, 0.78))),
                delay: delay, colours: palettes[rng.int(palettes.count)]
            ))
            // Mostly quick volleys, with the odd pause for breath.
            delay += rng.chance(0.3) ? rng.range(0.9, 1.6) : rng.range(0.12, 0.5)
        }
    }

    private func blazeSparks(config: Config) {
        let size = self.size
        let colours = Palettes.colors(for: config.palette, customHex: config.customColorHex)
            + [SIMD3<Float>(1, 0.95, 0.8)]
        var x: Float = 30
        let y = (config.belowMenuBar ? topInset : 0) + 14
        while x < size.x {
            if config.edgeTop {
                sparks.burst(at: SIMD2(x, y), count: 5, speed: 40...240, colours: colours,
                             size: 3...7, life: 0.6...1.6, gravity: 240, drag: 1.0)
            }
            x += rng.range(50, 90)
        }
        var sideY = y + 30
        while sideY < size.y {
            if config.edgeLeft {
                sparks.burst(at: SIMD2(8, sideY), count: 3, speed: 40...200, colours: colours,
                             size: 3...6, life: 0.6...1.4, gravity: 240, drag: 1.0)
            }
            if config.edgeRight {
                sparks.burst(at: SIMD2(size.x - 8, sideY), count: 3, speed: 40...200, colours: colours,
                             size: 3...6, life: 0.6...1.4, gravity: 240, drag: 1.0)
            }
            sideY += rng.range(60, 110)
        }
    }

    private func groundY(at x: Float) -> Float {
        size.y - ground.height(atX: x)
    }

    private func updateSurprises(dt: Float, world: World) {
        let size = self.size

        // Santa leaves a trail of dust on whichever screens he is over.
        if let santa = world.santa {
            let sleighX = santa.leadX - santa.direction * (Float(SantaFlight.reindeerCount) * SantaFlight.reindeerGap + 70) * santa.scale
            let localX = sleighX - Float(frame.minX) - santa.direction * 46 * santa.scale
            let localY = santa.y(atX: sleighX) - Float(frame.minY) + 14 * santa.scale
            if localX > -40, localX < size.x + 40 {
                let wanted = dt * 85
                var count = Int(wanted)
                if rng.chance(wanted - Float(count)) { count += 1 }
                for _ in 0..<count {
                    let gold = rng.chance(0.7)
                    sparks.emit(
                        at: SIMD2(localX + rng.signed() * 10, localY + rng.signed() * 14),
                        velocity: SIMD2(-santa.direction * rng.range(20, 90), rng.range(-20, 34)),
                        colour: gold ? SIMD3(1.0, 0.82, 0.36) : SIMD3(1, 0.97, 0.9),
                        size: rng.range(2.5, 6.5), life: rng.range(0.7, 1.9), gravity: 46, drag: 0.9
                    )
                }
            }
        }

        var i = 0
        while i < stars.count {
            stars[i].age += dt
            stars[i].position += stars[i].velocity * dt
            if rng.chance(dt * 40) {
                sparks.emit(at: stars[i].position, velocity: stars[i].velocity * 0.05 + SIMD2(rng.signed() * 20, rng.signed() * 20),
                            colour: SIMD3(0.85, 0.93, 1), size: rng.range(2, 4), life: rng.range(0.3, 0.7), gravity: 20)
            }
            if stars[i].age >= stars[i].duration { stars.remove(at: i) } else { i += 1 }
        }

        i = 0
        while i < presents.count {
            var p = presents[i]
            if p.delay > 0 {
                p.delay -= dt
                presents[i] = p
                i += 1
                continue
            }
            p.age += dt
            let half = Float(p.art.size.height) * p.scale * 0.5 - 1
            if p.resting {
                // Stay put only while something is still underneath.
                let bottom = p.position.y + half
                if let hit = surfaces.hit(x: p.position.x, from: bottom - 5, to: bottom + 5) {
                    p.position.y = hit.y - half
                } else if abs(groundY(at: p.position.x) - bottom) < 6 {
                    p.position.y = groundY(at: p.position.x) - half
                } else {
                    p.resting = false
                    p.spin = rng.signed() * 2
                }
                p.rotation *= max(1 - dt * 8, 0)
            } else {
                p.velocity.y = min(p.velocity.y + 760 * dt, 900)
                p.velocity.x += (world.wind * 0.25 - p.velocity.x) * min(dt * 0.6, 1)
                let previousBottom = p.position.y + half
                p.position += p.velocity * dt
                p.rotation += p.spin * dt
                let bottom = p.position.y + half
                var surface: Float?
                if p.velocity.y > 0, let hit = surfaces.hit(x: p.position.x, from: previousBottom, to: bottom) {
                    surface = hit.y
                } else if bottom >= groundY(at: p.position.x) {
                    surface = groundY(at: p.position.x)
                }
                if let surface {
                    p.position.y = surface - half
                    snow.addPowder(x: p.position.x, y: surface, velocity: SIMD2(0, -30), count: 3, life: 0.5)
                    if p.velocity.y < 130 {
                        p.resting = true
                        p.velocity = .zero
                    } else {
                        p.velocity.y *= -0.36
                        p.velocity.x *= 0.6
                        p.spin *= 0.4
                    }
                }
            }
            if p.age >= p.lifetime || p.position.y > size.y + 80 {
                if p.position.y <= size.y + 40 {
                    sparks.burst(at: p.position, count: 22, speed: 40...210,
                                 colours: [SIMD3(1.0, 0.82, 0.36), SIMD3(1, 0.3, 0.3), SIMD3(0.4, 1, 0.55), SIMD3(1, 1, 1)],
                                 size: 3...7, life: 0.5...1.3)
                }
                presents.remove(at: i)
                continue
            }
            presents[i] = p
            i += 1
        }

        if var s = snowman {
            if s.age == 0 {
                snow.addPowder(x: s.x, y: groundY(at: s.x) - 8, velocity: SIMD2(0, -70), count: 26, life: 1.0)
            }
            s.age += dt
            snowman = s.age >= s.duration ? nil : s
        }

        i = 0
        while i < snowballs.count {
            var b = snowballs[i]
            b.age += dt
            if !b.landed, b.age >= 0.28 {
                b.landed = true
                for _ in 0..<44 {
                    let angle = rng.range(0, 6.283)
                    let speed = rng.range(60, 330)
                    snow.addPowder(x: b.centre.x, y: b.centre.y,
                                   velocity: SIMD2(cosf(angle), sinf(angle)) * speed, count: 1, life: 0.9)
                }
                for _ in 0..<12 {
                    let angle = rng.range(0, 6.283)
                    let speed = rng.range(80, 260)
                    snow.addClump(x: b.centre.x + cosf(angle) * 20, y: b.centre.y + sinf(angle) * 20,
                                  velocity: SIMD2(cosf(angle) * speed, sinf(angle) * speed - 80), amount: rng.range(8, 26))
                }
            }
            if b.age > 9 { snowballs.remove(at: i) } else {
                snowballs[i] = b
                i += 1
            }
        }

        i = 0
        while i < shells.count {
            var s = shells[i]
            if s.delay > 0 {
                s.delay -= dt
                shells[i] = s
                i += 1
                continue
            }
            s.velocity.y += 520 * dt
            s.position += s.velocity * dt
            sparks.emit(at: s.position, velocity: SIMD2(rng.signed() * 14, rng.range(20, 70)),
                        colour: SIMD3(1, 0.86, 0.55), size: rng.range(2, 3.5), life: rng.range(0.25, 0.5), gravity: 30)
            if s.velocity.y > -70 {
                sparks.burst(at: s.position, count: 130 + rng.int(70), speed: 80...430,
                             colours: s.colours, size: 6...13, life: 1.4...2.9, gravity: 90, drag: 1.35)
                sparks.burst(at: s.position, count: 10, speed: 0...40,
                             colours: [SIMD3(1, 1, 1)], size: 26...44, life: 0.2...0.45, gravity: 0, drag: 2)
                shells.remove(at: i)
                continue
            }
            shells[i] = s
            i += 1
        }
    }

    // MARK: Drawing

    /// Builds this frame's draw list, back to front.
    public func build(_ batch: RenderBatch, atlas: Atlas, world: World, config: Config) {
        let size = self.size
        guard !isSuspended else { return }

        if world.aurora > 0.001 {
            let band = min(size.y * 0.42, 480)
            batch.add(SpriteInstance(
                pos: SIMD2(size.x * 0.5, topInset + band * 0.5), size: SIMD2(size.x, band),
                color: SIMD4(1, 1, 1, 1), shape: Shape.aurora, p0: world.aurora * 0.5, p1: Float(frame.minX)
            ))
        }

        for star in stars {
            let direction = simd_normalize(star.velocity)
            let fade = powf(sinf(.pi * clamp(star.age / star.duration, 0, 1)), 0.6)
            batch.add(SpriteInstance(
                pos: star.position - direction * (star.length * 0.43), size: SIMD2(star.length, 9),
                color: SIMD4(0.86, 0.93, 1, fade), rot: atan2f(direction.y, direction.x),
                shape: Shape.streak, p0: 0.6
            ))
        }

        snow.drawBack(into: batch, hidden: config.depthBehindWindows ? hidden : [])

        for ledge in ledges {
            piles[ledge.windowID]?.draw(into: batch, from: ledge.span.lo, to: ledge.span.hi)
        }
        ground.draw(into: batch, from: 0, to: size.x)

        if let s = snowman {
            let art = Art.snowman
            let base = atlas.size(art) * 0.92
            let pop = 1 - expf(-s.age * 5.5) * cosf(s.age * 10)
            let leaving = smoothstep(s.duration - 1.6, s.duration, s.age)
            let sy = pop * (1 - leaving * 0.94)
            let sx = pop * (1 + leaving * 0.22)
            let footing = groundY(at: s.x) + 5
            batch.add(SpriteInstance(
                pos: SIMD2(s.x, footing - base.y * sy * 0.5), size: SIMD2(base.x * sx, base.y * sy),
                color: SIMD4(1, 1, 1, 1 - leaving * 0.5), uv: atlas.uv(art),
                rot: sinf(s.age * 1.3) * 0.03 * (1 - leaving), shape: Shape.atlas
            ))
        }

        for p in presents where p.delay <= 0 {
            let fade = min((p.lifetime - p.age) * 4, 1)
            batch.add(SpriteInstance(
                pos: p.position, size: atlas.size(p.art) * p.scale,
                color: SIMD4(1, 1, 1, clamp(fade, 0, 1)), uv: atlas.uv(p.art), rot: p.rotation, shape: Shape.atlas
            ))
        }

        snow.drawFront(into: batch)

        if let santa = world.santa {
            drawSanta(santa, into: batch, atlas: atlas)
        }
        sparks.draw(into: batch, time: time)

        for b in snowballs {
            if !b.landed {
                let grow = b.age / 0.28
                batch.add(SpriteInstance(
                    pos: b.centre, size: SIMD2(repeating: mix(8, 70, grow * grow) * b.scale),
                    color: SIMD4(1, 1, 1, 0.95), shape: Shape.dot, p0: 0.78
                ))
            } else {
                let t = b.age - 0.28
                let squash = 1 + 0.22 * expf(-t * 10)
                let slide = 5 * t + 3.2 * t * t
                let alpha = 1 - smoothstep(4.5, 8.6, t)
                let base = atlas.size(.splat) * b.scale
                batch.add(SpriteInstance(
                    pos: SIMD2(b.centre.x, b.centre.y + 30 * b.scale + slide), size: base * squash,
                    color: SIMD4(1, 1, 1, alpha), uv: atlas.uv(.splat), rot: b.rotation, shape: Shape.atlas
                ))
            }
        }

        if let lights, lightsOpacity > 0.01 {
            lights.draw(into: batch, time: time, config: config, wind: world.wind, boost: world.boost,
                        opacity: lightsOpacity)
        }
    }

    private func drawSanta(_ santa: SantaFlight, into batch: RenderBatch, atlas: Atlas) {
        let size = self.size
        let origin = SIMD2<Float>(Float(frame.minX), Float(frame.minY))
        let d = santa.direction
        let s = santa.scale
        let margin: Float = 160 * s

        func flipped(_ uv: SIMD4<Float>) -> SIMD4<Float> {
            d > 0 ? uv : SIMD4(uv.z, uv.y, uv.x, uv.w)
        }

        // Positions first, so the reins can be drawn underneath the sprites.
        var deer: [(centre: SIMD2<Float>, tilt: Float, index: Int)] = []
        for k in 0..<SantaFlight.reindeerCount {
            let gx = santa.leadX - d * Float(k) * SantaFlight.reindeerGap * s
            let gy = santa.y(atX: gx) + sinf(santa.elapsed * 6.2 + Float(k) * 1.1) * 3.5 * s
            deer.append((SIMD2(gx, gy) - origin, santa.tilt(atX: gx), k))
        }
        let sleighX = santa.leadX - d * (Float(SantaFlight.reindeerCount) * SantaFlight.reindeerGap + 62) * s
        let sleighCentre = SIMD2(sleighX, santa.y(atX: sleighX) + sinf(santa.elapsed * 3.1) * 3 * s) - origin
        let sleighTilt = santa.tilt(atX: sleighX)

        let lead = deer[0].centre.x
        let tail = sleighCentre.x
        guard max(lead, tail) > -margin, min(lead, tail) < size.x + margin else { return }

        let deerSize = atlas.size(.reindeerStride) * s
        let sleighSize = atlas.size(.sleigh) * s
        let harness = SIMD2<Float>(
            Float(ArtPainter.reindeerHarness.x) - Float(Art.reindeerStride.size.width) * 0.5,
            Float(ArtPainter.reindeerHarness.y) - Float(Art.reindeerStride.size.height) * 0.5
        ) * s
        let hand = SIMD2<Float>(
            Float(ArtPainter.sleighHand.x) - Float(Art.sleigh.size.width) * 0.5,
            Float(ArtPainter.sleighHand.y) - Float(Art.sleigh.size.height) * 0.5
        ) * s

        var reins: [SIMD2<Float>] = [sleighCentre + SIMD2(hand.x * d, hand.y)]
        for entry in deer.reversed() {
            reins.append(entry.centre + SIMD2(harness.x * d, harness.y))
        }
        batch.polyline(reins, width: 1.1 * s, color: SIMD4(0.42, 0.25, 0.12, 0.95))

        for entry in deer.reversed() {
            let stride = Int(santa.elapsed * 7 + Float(entry.index) * 0.5) % 2 == 0
            let art: Art = stride ? .reindeerStride : .reindeerGather
            batch.add(SpriteInstance(
                pos: entry.centre, size: deerSize, color: SIMD4(1, 1, 1, 1),
                uv: flipped(atlas.uv(art)), rot: entry.tilt * d, shape: Shape.atlas
            ))
        }
        batch.add(SpriteInstance(
            pos: sleighCentre, size: sleighSize, color: SIMD4(1, 1, 1, 1),
            uv: flipped(atlas.uv(.sleigh)), rot: sleighTilt * d, shape: Shape.atlas
        ))

        // The lead reindeer's nose glows.
        let nose = SIMD2<Float>(
            Float(ArtPainter.reindeerNose.x) - Float(Art.reindeerStride.size.width) * 0.5,
            Float(ArtPainter.reindeerNose.y) - Float(Art.reindeerStride.size.height) * 0.5
        ) * s
        let nosePosition = deer[0].centre + SIMD2(nose.x * d, nose.y)
        let pulse = 0.8 + 0.2 * sinf(santa.elapsed * 5)
        batch.add(SpriteInstance(
            pos: nosePosition, size: SIMD2(repeating: 46 * s), color: SIMD4(1, 0.12, 0.10, pulse),
            shape: Shape.halo, p0: 0.3
        ))
        batch.add(SpriteInstance(
            pos: nosePosition, size: SIMD2(repeating: 5.2 * s), color: SIMD4(1, 0.22, 0.18, 1),
            shape: Shape.dot, p0: 0.6
        ))
    }
}
