import Foundation
import simd

public enum Palettes {
    public static func colors(for palette: LightPalette, customHex: String) -> [SIMD3<Float>] {
        switch palette {
        case .classic:
            return [SIMD3(1.0, 0.15, 0.13), SIMD3(1.0, 0.78, 0.12), SIMD3(0.10, 0.86, 0.32),
                    SIMD3(0.15, 0.42, 1.0), SIMD3(1.0, 0.44, 0.08)]
        case .warmWhite: return [SIMD3(1.0, 0.80, 0.50)]
        case .coolWhite: return [SIMD3(0.84, 0.93, 1.0)]
        case .redGreen: return [SIMD3(1.0, 0.15, 0.13), SIMD3(0.10, 0.86, 0.32)]
        case .candyCane: return [SIMD3(1.0, 0.13, 0.16), SIMD3(1.0, 0.96, 0.92)]
        case .icy: return [SIMD3(0.30, 0.62, 1.0), SIMD3(0.86, 0.95, 1.0), SIMD3(0.40, 0.90, 1.0)]
        case .gold: return [SIMD3(1.0, 0.72, 0.20), SIMD3(1.0, 0.86, 0.48)]
        case .retro:
            return [SIMD3(0.92, 0.20, 0.15), SIMD3(0.97, 0.55, 0.10), SIMD3(0.16, 0.64, 0.36),
                    SIMD3(0.15, 0.38, 0.82), SIMD3(0.88, 0.28, 0.55), SIMD3(0.95, 0.82, 0.28)]
        case .pastel:
            return [SIMD3(1.0, 0.66, 0.75), SIMD3(0.68, 0.85, 1.0), SIMD3(0.74, 0.96, 0.78),
                    SIMD3(1.0, 0.90, 0.64), SIMD3(0.83, 0.75, 1.0)]
        case .rainbow:
            return (0..<12).map { hue(Float($0) / 12) }
        case .custom:
            return [color(hex: customHex) ?? SIMD3(1, 0.27, 0.23)]
        }
    }

    public static func hue(_ h: Float) -> SIMD3<Float> {
        let x = h - h.rounded(.down)
        let r = abs(x * 6 - 3) - 1
        let g = 2 - abs(x * 6 - 2)
        let b = 2 - abs(x * 6 - 4)
        let rgb = SIMD3(clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1))
        // Pull slightly toward white so saturated hues still read as lit glass.
        return rgb * 0.88 + SIMD3(repeating: 0.12)
    }

    public static func color(hex: String) -> SIMD3<Float>? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        return SIMD3(Float((value >> 16) & 0xFF) / 255, Float((value >> 8) & 0xFF) / 255, Float(value & 0xFF) / 255)
    }
}

/// Brightness of one bulb under a pattern. Pure, so it can be tested and reused.
public enum LightPatterns {
    public struct Sample {
        public var level: Float
        /// 0...1, how far the bulb is pushed toward white (flashes, comet heads).
        public var white: Float
    }

    private static let showReel: [LightPattern] = [
        .twinkle, .chase, .wave, .sparkle, .meteor, .channelFade, .alternate, .breathe,
    ]

    public static func sample(_ pattern: LightPattern, index i: Int, count n: Int,
                              slot: Int, slots: Int, time t: Float, seed: Float) -> Sample {
        switch pattern {
        case .steady:
            return Sample(level: 1, white: 0)
        case .twinkle:
            let v = Noise.value(t * 0.9 + seed * 100, seed: i)
            return Sample(level: 0.28 + 0.72 * smoothstep(0.25, 0.65, v), white: 0)
        case .chase:
            var phase = Float(i) / 4 - t * 0.9
            phase -= phase.rounded(.down)
            let lit = smoothstep(0.0, 0.10, phase) * (1 - smoothstep(0.26, 0.48, phase))
            return Sample(level: 0.12 + 0.88 * lit, white: 0)
        case .wave:
            let x = 0.5 + 0.5 * sinf(Float(i) * 0.42 - t * 2.6)
            return Sample(level: 0.12 + 0.88 * powf(x, 1.6), white: 0)
        case .breathe:
            let x = 0.5 + 0.5 * sinf(t * 1.5)
            return Sample(level: 0.16 + 0.84 * x * x * (3 - 2 * x), white: 0)
        case .alternate:
            let s = smoothstep(-0.3, 0.3, sinf(t * 1.7))
            return Sample(level: 0.12 + 0.88 * (i % 2 == 0 ? s : 1 - s), white: 0)
        case .sparkle:
            let frame = (t * 9).rounded(.down)
            if Noise.hash(i, Int(frame)) > 0.955 {
                let f = 1 - (t * 9 - frame)
                return Sample(level: 0.72 + 0.9 * f, white: f)
            }
            return Sample(level: 0.72, white: 0)
        case .meteor:
            guard n > 0 else { return Sample(level: 1, white: 0) }
            let comets = max(n / 70, 1)
            var level: Float = 0.10
            var white: Float = 0
            for k in 0..<comets {
                var head = t * 0.11 + Float(k) / Float(comets)
                head = (head - head.rounded(.down)) * Float(n)
                var behind = head - Float(i)
                if behind < 0 { behind += Float(n) }
                level += expf(-behind / 7) * 1.2
                white += expf(-behind / 2) * 0.7
            }
            return Sample(level: min(level, 1.5), white: min(white, 1))
        case .channelFade:
            let x = 0.5 + 0.5 * sinf(t * 1.3 - Float(slot) / Float(max(slots, 1)) * 2 * .pi)
            return Sample(level: 0.10 + 0.90 * smoothstep(0.15, 0.85, x), white: 0)
        case .showtime:
            let segment: Float = 14
            let position = t / segment
            let index = Int(position.rounded(.down))
            let within = (position - Float(index)) * segment
            let current = showReel[((index % showReel.count) + showReel.count) % showReel.count]
            let a = sample(current, index: i, count: n, slot: slot, slots: slots, time: t, seed: seed)
            guard within > segment - 1.2 else { return a }
            let next = showReel[(((index + 1) % showReel.count) + showReel.count) % showReel.count]
            let b = sample(next, index: i, count: n, slot: slot, slots: slots, time: t, seed: seed)
            let blend = smoothstep(segment - 1.2, segment, within)
            return Sample(level: mix(a.level, b.level, blend), white: mix(a.white, b.white, blend))
        }
    }
}

/// How an event (the Griswold Moment) overrides the lights for a while.
public struct LightBoost {
    /// Multiplies every bulb: 0 is blackout, 1 is normal, above 1 is overdrive.
    public var level: Float = 1
    /// Extra halo size, 0 for none.
    public var bloom: Float = 0
    /// 0...1 chance per bulb per frame of sputtering dark.
    public var sputter: Float = 0
    /// 0...1, how far the whole desktop browns out while the lights hog the power.
    public var dim: Float = 0

    public init() {}
}

/// A string of lights hung around one screen.
public final class LightString {
    struct Bulb {
        /// Where the bulb hangs from.
        var anchor: SIMD2<Float>
        /// Distance below the anchor along the hang direction (icicle strands).
        var drop: Float
        /// Rest angle: 0 points straight down.
        var angle: Float
        var seed: Float
        /// Position in the whole string, for running patterns.
        var order: Int
        var slot: Int
        var swings: Bool
    }

    /// Settings that change the physical layout; a new value means re-hanging.
    public struct Layout: Equatable {
        public var size: SIMD2<Float>
        public var topInset: Float
        public var style: BulbStyle
        public var scale: Float
        public var spacing: Float
        public var top: Bool
        public var left: Bool
        public var right: Bool
        public var bottom: Bool

        public init(size: SIMD2<Float>, topInset: Float, config: Config) {
            self.size = size
            self.topInset = config.belowMenuBar ? topInset : 0
            style = config.bulbStyle
            scale = Float(config.bulbScale)
            spacing = Float(config.spacing)
            top = config.edgeTop
            left = config.edgeLeft
            right = config.edgeRight
            bottom = config.edgeBottom
        }
    }

    public let layout: Layout
    private var bulbs: [Bulb] = []
    private var wires: [[SIMD2<Float>]] = []
    /// Icicle strands: index range of their bulbs, drawn with a hanging wire.
    private var strands: [Range<Int>] = []
    private let bulbSize: SIMD2<Float>
    private let shaderStyle: Float
    private var rng = FastRNG(seed: 0x51AB)

    public var bulbCount: Int { bulbs.count }

    public init(layout: Layout) {
        self.layout = layout
        let s = layout.scale
        switch layout.style {
        case .c9:
            bulbSize = SIMD2(11, 22) * s
            shaderStyle = 0
        case .mini, .icicle:
            bulbSize = SIMD2(6.2, 13.6) * s
            shaderStyle = 1
        case .globe:
            bulbSize = SIMD2(14.5, 18.1) * s
            shaderStyle = 2
        case .star:
            bulbSize = SIMD2(18, 18) * s
            shaderStyle = 3
        }
        build()
    }

    private func build() {
        let w = layout.size.x
        let h = layout.size.y
        let s = layout.scale
        let pitch: Float
        let perScallop: Int
        switch layout.style {
        case .c9: pitch = 40; perScallop = 3
        case .mini: pitch = 23; perScallop = 4
        case .globe: pitch = 46; perScallop = 3
        case .star: pitch = 46; perScallop = 3
        case .icicle: pitch = 15; perScallop = 6
        }
        let step = pitch * layout.spacing * max(s, 0.75)
        let topY = layout.topInset + 2.5
        let sideTop = topY + 6
        let sideBottom = h - 10
        var order = 0

        /// Hangs bulbs along a straight run from `a` to `b`, with the wire
        /// sagging toward `sagDirection` between clips.
        func run(from a: SIMD2<Float>, to b: SIMD2<Float>, sagDirection: SIMD2<Float>, sag: Float,
                 angle: Float, swings: Bool, icicles: Bool) {
            let length = simd_length(b - a)
            guard length > step else { return }
            let count = max(Int(length / step), 1)
            let scallops = max(count / perScallop, 1)
            let total = scallops * perScallop
            let direction = (b - a) / length
            let scallopLength = length / Float(scallops)
            var wire: [SIMD2<Float>] = []
            for sIndex in 0..<scallops {
                let start = a + direction * (Float(sIndex) * scallopLength)
                let segments = 10
                for k in 0...segments where !(sIndex > 0 && k == 0) {
                    let t = Float(k) / Float(segments)
                    wire.append(start + direction * (t * scallopLength) + sagDirection * (sag * 4 * t * (1 - t)))
                }
            }
            wires.append(wire)
            let lengths = [3, 5, 2, 4, 6, 3, 5, 2, 4, 7, 3, 4]
            for index in 0..<total {
                let within = (Float(index % perScallop) + 0.5) / Float(perScallop)
                let along = (Float(index / perScallop) + within) * scallopLength
                let anchor = a + direction * along + sagDirection * (sag * 4 * within * (1 - within))
                if icicles {
                    let strandSeed = rng.unit()
                    let first = bulbs.count
                    let drops = lengths[index % lengths.count]
                    for d in 0..<drops {
                        bulbs.append(Bulb(
                            anchor: anchor, drop: Float(d) * 11.5 * s + 1, angle: angle,
                            seed: strandSeed, order: order, slot: order, swings: swings
                        ))
                        order += 1
                    }
                    strands.append(first..<bulbs.count)
                } else {
                    bulbs.append(Bulb(
                        anchor: anchor, drop: 0, angle: angle + rng.signed() * 0.16,
                        seed: rng.unit(), order: order, slot: order, swings: swings
                    ))
                    order += 1
                }
            }
        }

        let inset: Float = 12
        let isIcicle = layout.style == .icicle
        // Clockwise from the bottom-left, so running patterns travel the whole frame.
        if layout.left {
            run(from: SIMD2(3.5, sideBottom), to: SIMD2(3.5, sideTop), sagDirection: SIMD2(1, 0), sag: 4.5 * s,
                angle: -0.86, swings: true, icicles: false)
        }
        if layout.top {
            run(from: SIMD2(inset, topY), to: SIMD2(w - inset, topY), sagDirection: SIMD2(0, 1),
                sag: (isIcicle ? 3 : 7) * s, angle: 0, swings: true, icicles: isIcicle)
        }
        if layout.right {
            run(from: SIMD2(w - 3.5, sideTop), to: SIMD2(w - 3.5, sideBottom), sagDirection: SIMD2(-1, 0), sag: 4.5 * s,
                angle: 0.86, swings: true, icicles: false)
        }
        if layout.bottom {
            run(from: SIMD2(w - inset, h - 3), to: SIMD2(inset, h - 3), sagDirection: SIMD2(0, -1), sag: 2.5 * s,
                angle: .pi, swings: false, icicles: false)
        }
    }

    /// Draws wires, halos and bulbs.
    public func draw(into batch: RenderBatch, time: Float, config: Config, wind: Float, boost: LightBoost,
                     opacity: Float = 1) {
        guard !bulbs.isEmpty, opacity > 0.01 else { return }
        let colors = Palettes.colors(for: config.palette, customHex: config.customColorHex)
        let slots = colors.count
        let patternTime = time * (0.35 + 1.9 * Float(config.lightSpeed))
        let brightness = Float(config.brightness)
        let glow = Float(config.glow)
        let wireColor = SIMD4<Float>(0.035, 0.17, 0.10, 0.92 * opacity)
        let lean = clamp(wind / 420, -0.42, 0.42)
        let count = bulbs.count

        for wire in wires {
            batch.polyline(wire, width: 1.5, color: wireColor)
        }

        // Resolve each bulb once, then emit strand wires, halos, and bulbs in that order.
        struct Resolved {
            var centre: SIMD2<Float>
            var rotation: Float
            var colour: SIMD3<Float>
            var lit: Float
        }
        var resolved: [Resolved] = []
        resolved.reserveCapacity(count)
        let half = bulbSize.y * 0.5 - 1

        for bulb in bulbs {
            var angle = bulb.angle
            if bulb.swings {
                angle += sinf(time * 1.35 + bulb.seed * 6.283) * 0.045 - lean * (0.55 + 0.45 * bulb.seed)
            }
            let direction = SIMD2<Float>(-sinf(angle), cosf(angle))
            let slot = bulb.slot % slots
            var colour = colors[slot]
            let sample = LightPatterns.sample(
                config.pattern, index: bulb.order, count: count, slot: slot, slots: slots,
                time: patternTime, seed: bulb.seed
            )
            var lit = sample.level * brightness * boost.level
            if boost.sputter > 0, Noise.hash(bulb.order, Int(time * 24)) < boost.sputter { lit *= 0.08 }
            if sample.white > 0 {
                colour = colour + (SIMD3(repeating: 1) - colour) * (sample.white * 0.7)
            }
            resolved.append(Resolved(
                centre: bulb.anchor + direction * (bulb.drop + half),
                rotation: angle, colour: colour, lit: lit
            ))
        }

        for strand in strands where strand.count > 1 {
            let top = bulbs[strand.lowerBound].anchor
            let last = resolved[strand.upperBound - 1].centre
            batch.polyline([top, last], width: 1.0, color: wireColor)
        }

        let haloBase = max(bulbSize.x * 4.0, 36) * (0.7 + 0.9 * glow) * (1 + boost.bloom)
        if glow > 0.02 {
            for r in resolved where r.lit > 0.06 {
                let strength = min(r.lit, 1.6)
                batch.add(SpriteInstance(
                    pos: r.centre, size: SIMD2(repeating: haloBase * (0.75 + 0.25 * strength)),
                    color: SIMD4(r.colour.x, r.colour.y, r.colour.z, strength * glow * 0.9 * opacity),
                    shape: Shape.halo, p0: 0.16
                ))
            }
        }
        for r in resolved {
            batch.add(SpriteInstance(
                pos: r.centre, size: bulbSize,
                color: SIMD4(r.colour.x, r.colour.y, r.colour.z, opacity),
                rot: r.rotation, shape: Shape.bulb, p0: r.lit, p1: shaderStyle
            ))
        }
    }
}
