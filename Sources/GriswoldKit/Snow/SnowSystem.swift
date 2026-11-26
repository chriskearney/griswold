import CoreGraphics
import Foundation
import simd

/// What the snow needs to know about its surroundings for one step.
public struct SnowEnvironment {
    public var size: SIMD2<Float>
    /// Horizontal wind, points per second.
    public var wind: Float
    public var time: Float
    public var cursor: SIMD2<Float>?
    public var cursorVelocity: SIMD2<Float> = .zero
    public var flakeScale: Float = 1
    public var surfaces: SurfaceMap?
    public var ground: SnowPile?

    public init(size: SIMD2<Float>, wind: Float, time: Float) {
        self.size = size
        self.wind = wind
        self.time = time
    }
}

/// Spatial index of the ledges snow can land on, bucketed by x.
public final class SurfaceMap {
    public struct Entry {
        public var lo: Float
        public var hi: Float
        public var y: Float
        public var pile: SnowPile
    }

    private static let bucketWidth: Float = 48
    public private(set) var entries: [Entry] = []
    private var buckets: [[Int32]] = []

    public init(width: Float) {
        buckets = Array(repeating: [], count: max(Int(width / SurfaceMap.bucketWidth) + 1, 1))
    }

    public func add(_ entry: Entry) {
        let index = Int32(entries.count)
        entries.append(entry)
        let first = max(Int(entry.lo / SurfaceMap.bucketWidth), 0)
        let last = min(Int(entry.hi / SurfaceMap.bucketWidth), buckets.count - 1)
        guard first <= last else { return }
        for b in first...last { buckets[b].append(index) }
    }

    /// The surface a particle at `x` crosses while moving from `y0` down to `y1`, if any.
    @inline(__always)
    public func hit(x: Float, from y0: Float, to y1: Float) -> (pile: SnowPile, y: Float)? {
        let b = Int(x / SurfaceMap.bucketWidth)
        guard b >= 0, b < buckets.count else { return nil }
        for index in buckets[b] {
            let entry = entries[Int(index)]
            guard x >= entry.lo, x < entry.hi, entry.y >= y0 - 1 else { continue }
            let surface = entry.y - entry.pile.height(atX: x)
            if y0 <= surface, y1 >= surface {
                return (entry.pile, surface)
            }
        }
        return nil
    }
}

struct Flake {
    var x: Float
    var y: Float
    var vx: Float
    var vy: Float
    var radius: Float
    var fall: Float
    var phase: Float
    var swayFrequency: Float
    var swayAmount: Float
    var rotation: Float
    var spin: Float
    var alpha: Float
    /// Snow carried, as an area in square points.
    var amount: Float
    var life: Float
    var layer: UInt8
    var kind: UInt8
    var lands: Bool
}

/// Falling snow: three depth layers of flakes plus short-lived clumps and powder.
public final class SnowSystem {
    static let far: UInt8 = 0
    static let mid: UInt8 = 1
    static let near: UInt8 = 2
    static let bokeh: UInt8 = 3

    static let kindDot: UInt8 = 0
    static let kindCrystal: UInt8 = 1
    static let kindClump: UInt8 = 2
    static let kindPowder: UInt8 = 3

    private(set) var flakes: [Flake] = []
    private(set) var loose: [Flake] = []
    private var rng: FastRNG
    public var target = 0

    public init(seed: UInt64 = 0xA11CE) {
        rng = FastRNG(seed: seed)
    }

    public var isIdle: Bool { flakes.isEmpty && loose.isEmpty && target == 0 }
    public var count: Int { flakes.count + loose.count }

    /// How many flakes a screen of this size should carry at a given intensity.
    public static func targetCount(intensity: Float, size: SIMD2<Float>) -> Int {
        guard intensity > 0.001 else { return 0 }
        let reference: Float = 1440 * 900
        let area = min(size.x * size.y / reference, 4.5)
        let density = mix(50, 1500, powf(clamp(intensity, 0, 1), 1.6))
        return min(Int(density * area), 5200)
    }

    private func makeFlake(size: SIMD2<Float>, scale: Float, anywhere: Bool) -> Flake {
        let roll = rng.unit()
        var layer = SnowSystem.far
        var radius: Float
        var alpha: Float
        var kind = SnowSystem.kindDot
        var lands = false
        if roll < 0.40 {
            radius = rng.range(0.8, 1.5)
            alpha = rng.range(0.45, 0.65)
        } else if roll < 0.74 {
            layer = SnowSystem.mid
            radius = rng.range(1.3, 2.3)
            alpha = rng.range(0.65, 0.85)
            lands = rng.chance(0.5)
        } else if roll < 0.975 {
            layer = SnowSystem.near
            radius = rng.range(2.0, 3.6)
            alpha = rng.range(0.82, 0.97)
            lands = true
            if radius > 2.9, rng.chance(0.42) {
                kind = SnowSystem.kindCrystal
                radius = rng.range(4.5, 7.5)
                alpha = rng.range(0.7, 0.92)
            }
        } else {
            // A few big, soft, out-of-focus flakes right in front of the lens.
            layer = SnowSystem.bokeh
            radius = rng.range(7, 13)
            alpha = rng.range(0.16, 0.30)
        }
        radius *= scale
        let visual = kind == SnowSystem.kindCrystal ? radius * 0.55 : radius
        let fall: Float
        switch layer {
        case SnowSystem.far: fall = rng.range(26, 44)
        case SnowSystem.mid: fall = rng.range(46, 72)
        case SnowSystem.near: fall = kind == SnowSystem.kindCrystal ? rng.range(52, 78) : rng.range(74, 118)
        default: fall = rng.range(150, 210)
        }
        return Flake(
            x: rng.range(-60, size.x + 60),
            y: anywhere ? rng.range(-40, size.y) : rng.range(-90, -8),
            vx: 0, vy: fall,
            radius: radius, fall: fall,
            phase: rng.range(0, 6.283),
            swayFrequency: rng.range(0.5, 1.6),
            swayAmount: rng.range(6, 22) * (layer == SnowSystem.far ? 0.6 : 1),
            rotation: rng.range(0, 6.283),
            spin: rng.range(-1.1, 1.1),
            alpha: alpha,
            amount: visual * visual * 2.4,
            life: 0,
            layer: layer, kind: kind, lands: lands
        )
    }

    /// A lump of snow knocked loose from a pile.
    public func addClump(x: Float, y: Float, velocity: SIMD2<Float>, amount: Float) {
        guard loose.count < 2400 else { return }
        let radius = clamp(sqrtf(amount) * 0.62, 2.2, 7.5)
        loose.append(Flake(
            x: x + rng.signed() * 3, y: y + rng.signed() * 2,
            vx: velocity.x + rng.signed() * 26, vy: velocity.y + rng.range(-30, 40),
            radius: radius, fall: 0,
            phase: rng.unit(), swayFrequency: 0, swayAmount: 0,
            rotation: rng.range(0, 6.283), spin: rng.range(-3, 3),
            alpha: 0.96, amount: amount, life: 6,
            layer: SnowSystem.near, kind: SnowSystem.kindClump, lands: true
        ))
    }

    /// Fine powder that drifts and fades; purely decorative.
    public func addPowder(x: Float, y: Float, velocity: SIMD2<Float>, count: Int = 1, life: Float = 0.9) {
        guard loose.count < 2400 else { return }
        for _ in 0..<count {
            loose.append(Flake(
                x: x + rng.signed() * 4, y: y + rng.signed() * 2,
                vx: velocity.x + rng.signed() * 30, vy: velocity.y + rng.signed() * 22,
                radius: rng.range(0.8, 2.0), fall: 0,
                phase: 0, swayFrequency: 0, swayAmount: 0,
                rotation: 0, spin: 0,
                alpha: rng.range(0.5, 0.9), amount: 0, life: life * rng.range(0.6, 1.2),
                layer: SnowSystem.near, kind: SnowSystem.kindPowder, lands: false
            ))
        }
    }

    public func update(dt: Float, env: SnowEnvironment) {
        let size = env.size
        // Grow toward the target a little each frame so a density change eases in.
        if flakes.count < target {
            let add = min(target - flakes.count, max(target / 90, 6))
            let empty = flakes.isEmpty
            for _ in 0..<add {
                flakes.append(makeFlake(size: size, scale: env.flakeScale, anywhere: empty))
            }
            if empty {
                // First fill: scatter the whole target so the screen does not start bare.
                while flakes.count < target {
                    flakes.append(makeFlake(size: size, scale: env.flakeScale, anywhere: true))
                }
            }
        }

        let velocityEase = min(dt * 2.6, 1)
        let cursorRadius: Float = 95
        let cursorSpeed = simd_length(env.cursorVelocity)
        let cursorActive = env.cursor != nil && cursorSpeed > 40
        let cursor = env.cursor ?? .zero
        let groundBase = size.y

        var i = 0
        while i < flakes.count {
            var f = flakes[i]
            let layerWind: Float
            switch f.layer {
            case SnowSystem.far: layerWind = 0.55
            case SnowSystem.mid: layerWind = 0.8
            case SnowSystem.near: layerWind = 1.0
            default: layerWind = 1.35
            }
            let sway = sinf(f.phase + env.time * f.swayFrequency) * f.swayAmount
            f.vx += (env.wind * layerWind + sway - f.vx) * velocityEase
            f.vy += (f.fall - f.vy) * velocityEase

            if cursorActive, f.layer != SnowSystem.far {
                let dx = f.x - cursor.x
                let dy = f.y - cursor.y
                let d2 = dx * dx + dy * dy
                if d2 < cursorRadius * cursorRadius {
                    let d = sqrtf(d2) + 0.001
                    let strength = (1 - d / cursorRadius)
                    // Dragged along with the pointer, and nudged aside.
                    f.vx += (env.cursorVelocity.x * 0.9 + dx / d * cursorSpeed * 0.35 - f.vx) * strength * min(dt * 9, 1)
                    f.vy += (env.cursorVelocity.y * 0.9 + dy / d * cursorSpeed * 0.35 - f.vy) * strength * min(dt * 9, 1)
                }
            }

            let previousY = f.y
            f.x += f.vx * dt
            f.y += f.vy * dt
            f.rotation += f.spin * dt

            var respawn = false
            if f.lands, f.vy > 0, let surfaces = env.surfaces,
               let hit = surfaces.hit(x: f.x, from: previousY, to: f.y) {
                if hit.pile.deposit(x: f.x, amount: f.amount) {
                    respawn = true
                }
            }
            if !respawn {
                if let ground = env.ground, f.layer != SnowSystem.bokeh, f.layer != SnowSystem.far {
                    if f.y >= groundBase - ground.height(atX: f.x) {
                        ground.deposit(x: f.x, amount: f.amount * 0.8)
                        respawn = true
                    }
                } else if f.y > groundBase + f.radius + 4 {
                    respawn = true
                }
            }
            if f.y > groundBase + 30 { respawn = true }

            if f.x < -70 { f.x += size.x + 130 } else if f.x > size.x + 70 { f.x -= size.x + 130 }

            if respawn {
                if flakes.count > target {
                    flakes.swapAt(i, flakes.count - 1)
                    flakes.removeLast()
                    continue
                }
                f = makeFlake(size: size, scale: env.flakeScale, anywhere: false)
            }
            flakes[i] = f
            i += 1
        }

        // Clumps and powder.
        i = 0
        while i < loose.count {
            var f = loose[i]
            var dead = false
            f.life -= dt
            if f.kind == SnowSystem.kindClump {
                f.vy = min(f.vy + 980 * dt, 640)
                f.vx += (env.wind * 0.4 - f.vx) * min(dt * 1.2, 1)
                let previousY = f.y
                f.x += f.vx * dt
                f.y += f.vy * dt
                f.rotation += f.spin * dt
                if f.vy > 0, let surfaces = env.surfaces,
                   let hit = surfaces.hit(x: f.x, from: previousY, to: f.y) {
                    hit.pile.deposit(x: f.x, amount: f.amount * 0.9, force: hit.pile.height(atX: f.x) < hit.pile.maxHeight * 1.25)
                    addPowder(x: f.x, y: hit.y, velocity: SIMD2(f.vx * 0.3, -30), count: 2, life: 0.5)
                    dead = true
                } else if let ground = env.ground, f.y >= groundBase - ground.height(atX: f.x) {
                    ground.deposit(x: f.x, amount: f.amount * 0.9, force: ground.height(atX: f.x) < ground.maxHeight * 1.25)
                    addPowder(x: f.x, y: f.y, velocity: SIMD2(f.vx * 0.3, -34), count: 2, life: 0.5)
                    dead = true
                } else if f.y > groundBase + 20 || f.life <= 0 {
                    dead = true
                }
            } else {
                f.vx += (env.wind * 1.2 - f.vx) * min(dt * 1.5, 1)
                f.vy += 60 * dt
                f.x += f.vx * dt
                f.y += f.vy * dt
                dead = f.life <= 0
            }
            if dead {
                loose.swapAt(i, loose.count - 1)
                loose.removeLast()
                continue
            }
            loose[i] = f
            i += 1
        }
    }

    /// Draws the far flakes. With `hidden` rectangles they vanish behind windows,
    /// which is what makes the snowfall read as having depth.
    public func drawBack(into batch: RenderBatch, hidden: [CGRect]) {
        for f in flakes where f.layer == SnowSystem.far {
            if !hidden.isEmpty {
                let point = CGPoint(x: CGFloat(f.x), y: CGFloat(f.y))
                var covered = false
                for rect in hidden where rect.contains(point) {
                    covered = true
                    break
                }
                if covered { continue }
            }
            batch.add(SpriteInstance(
                pos: SIMD2(f.x, f.y), size: SIMD2(repeating: f.radius * 2.6),
                color: SIMD4(0.93, 0.96, 1, f.alpha), shape: Shape.dot, p0: 0.15
            ))
        }
    }

    /// Draws everything in front of the windows.
    public func drawFront(into batch: RenderBatch) {
        for f in flakes where f.layer != SnowSystem.far {
            if f.kind == SnowSystem.kindCrystal {
                batch.add(SpriteInstance(
                    pos: SIMD2(f.x, f.y), size: SIMD2(repeating: f.radius * 2),
                    color: SIMD4(1, 1, 1, f.alpha), rot: f.rotation, shape: Shape.crystal
                ))
            } else if f.layer == SnowSystem.bokeh {
                batch.add(SpriteInstance(
                    pos: SIMD2(f.x, f.y), size: SIMD2(repeating: f.radius * 2),
                    color: SIMD4(1, 1, 1, f.alpha), shape: Shape.dot, p0: 0.05
                ))
            } else {
                batch.add(SpriteInstance(
                    pos: SIMD2(f.x, f.y), size: SIMD2(repeating: f.radius * 2.4),
                    color: SIMD4(1, 1, 1, f.alpha), shape: Shape.dot,
                    p0: f.layer == SnowSystem.near ? 0.42 : 0.28
                ))
            }
        }
        for f in loose {
            if f.kind == SnowSystem.kindClump {
                batch.add(SpriteInstance(
                    pos: SIMD2(f.x, f.y), size: SIMD2(repeating: f.radius * 2.3),
                    color: SIMD4(0.97, 0.985, 1, f.alpha), rot: f.rotation, shape: Shape.clump, p0: f.phase
                ))
            } else {
                batch.add(SpriteInstance(
                    pos: SIMD2(f.x, f.y), size: SIMD2(repeating: f.radius * 2.6),
                    color: SIMD4(1, 1, 1, f.alpha * min(f.life * 2.5, 1)), shape: Shape.dot, p0: 0.1
                ))
            }
        }
    }

    public func removeAll() {
        flakes.removeAll(keepingCapacity: true)
        loose.removeAll(keepingCapacity: true)
    }
}
