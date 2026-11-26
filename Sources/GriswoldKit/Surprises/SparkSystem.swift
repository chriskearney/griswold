import Foundation
import simd

/// Glowing particles: sleigh dust, firework stars, popped presents.
public final class SparkSystem {
    struct Spark {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var colour: SIMD3<Float>
        var size: Float
        var life: Float
        var lifetime: Float
        var gravity: Float
        var drag: Float
        var twinkle: Float
    }

    private var sparks: [Spark] = []
    private var rng = FastRNG(seed: 0xF1EE)
    private static let limit = 3200

    public init() {}

    public var isEmpty: Bool { sparks.isEmpty }

    public func emit(at position: SIMD2<Float>, velocity: SIMD2<Float>, colour: SIMD3<Float>,
                     size: Float, life: Float, gravity: Float = 60, drag: Float = 1.2) {
        guard sparks.count < SparkSystem.limit else { return }
        sparks.append(Spark(
            position: position, velocity: velocity, colour: colour, size: size,
            life: life, lifetime: life, gravity: gravity, drag: drag, twinkle: rng.range(0, 6.283)
        ))
    }

    /// A radial burst, as for a firework shell or a popped present.
    public func burst(at position: SIMD2<Float>, count: Int, speed: ClosedRange<Float>,
                      colours: [SIMD3<Float>], size: ClosedRange<Float>, life: ClosedRange<Float>,
                      gravity: Float = 110, drag: Float = 1.5) {
        guard !colours.isEmpty else { return }
        for _ in 0..<count {
            let angle = rng.range(0, 6.283)
            // Square-root keeps the burst from clumping at its centre.
            let magnitude = mix(speed.lowerBound, speed.upperBound, sqrtf(rng.unit()))
            emit(
                at: position,
                velocity: SIMD2(cosf(angle), sinf(angle)) * magnitude,
                colour: colours[rng.int(colours.count)],
                size: rng.range(size.lowerBound, size.upperBound),
                life: rng.range(life.lowerBound, life.upperBound),
                gravity: gravity, drag: drag
            )
        }
    }

    public func update(dt: Float) {
        var i = 0
        while i < sparks.count {
            var s = sparks[i]
            s.life -= dt
            if s.life <= 0 {
                sparks.swapAt(i, sparks.count - 1)
                sparks.removeLast()
                continue
            }
            s.velocity *= max(1 - s.drag * dt, 0)
            s.velocity.y += s.gravity * dt
            s.position += s.velocity * dt
            sparks[i] = s
            i += 1
        }
    }

    public func draw(into batch: RenderBatch, time: Float) {
        for s in sparks {
            let age = s.life / s.lifetime
            let flicker = 0.72 + 0.28 * sinf(time * 17 + s.twinkle)
            let alpha = min(age * 2.2, 1) * flicker
            if s.size >= 6 {
                // Big sparks (firework stars) get a soft bloom of their own colour.
                batch.add(SpriteInstance(
                    pos: s.position, size: SIMD2(repeating: s.size * 4.5),
                    color: SIMD4(s.colour.x, s.colour.y, s.colour.z, alpha * 0.32),
                    shape: Shape.halo, p0: 0.1
                ))
            }
            batch.add(SpriteInstance(
                pos: s.position, size: SIMD2(repeating: s.size * (0.6 + 0.4 * age) * 2),
                color: SIMD4(s.colour.x, s.colour.y, s.colour.z, alpha),
                shape: Shape.glint, p0: 0.55
            ))
        }
    }

    public func removeAll() {
        sparks.removeAll(keepingCapacity: true)
    }
}
