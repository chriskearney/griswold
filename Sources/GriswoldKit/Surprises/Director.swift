import CoreGraphics
import Foundation
import simd

/// Santa's flight across the whole desktop, in global coordinates.
public struct SantaFlight {
    public var startX: Float
    public var endX: Float
    public var baseY: Float
    public var amplitude: Float
    public var direction: Float
    public var elapsed: Float
    public var duration: Float
    public var scale: Float

    /// Spacing between harnessed reindeer, and how far back the sleigh rides.
    public static let reindeerGap: Float = 50
    public static let reindeerCount = 5

    public var progress: Float { clamp(elapsed / duration, 0, 1) }

    /// Global x of the lead reindeer.
    public var leadX: Float { mix(startX, endX, progress) }

    /// Height of the flight path at a global x.
    public func y(atX x: Float) -> Float {
        let travel = abs(endX - startX)
        let u = abs(x - startX) / max(travel, 1)
        return baseY - amplitude * sinf(u * .pi) + amplitude * 0.22 * sinf(u * .pi * 5)
    }

    /// Slope of the path, as a rotation for sprites facing the direction of travel.
    public func tilt(atX x: Float) -> Float {
        let ahead = y(atX: x + direction * 12)
        let behind = y(atX: x - direction * 12)
        return atan2f(ahead - behind, 24) * direction
    }

    public var trainLength: Float {
        (Float(SantaFlight.reindeerCount) * SantaFlight.reindeerGap + 150) * scale
    }
}

/// Conditions shared by every screen for the current frame.
public struct World {
    public var time: Float = 0
    public var wind: Float = 0
    /// 0...1 strength of an active gust.
    public var gust: Float = 0
    public var aurora: Float = 0
    public var boost = LightBoost()
    /// Increments at the instant the Griswold Moment lights everything up.
    public var blazeSerial = 0
    public var santa: SantaFlight?

    public init() {}
}

public enum SoundCue {
    case sleighBells(duration: Double)
    case chime
    case powerUp
}

/// Schedules surprises and owns the ones that span every screen.
public final class Director {
    public private(set) var world = World()
    public var scenes: () -> [ScreenScene] = { [] }
    /// Union of all screens, global coordinates.
    public var desktopBounds: () -> CGRect = { .zero }
    public var onSound: ((SoundCue) -> Void)?

    private var rng = FastRNG(seed: UInt64(Date().timeIntervalSince1970 * 1000) | 1)
    private var lastTime: Double?
    private var nextSurprise: Double?
    private var lastKind: SurpriseKind?
    private var lastFrequency: SurpriseFrequency?

    private var gustStart: Double?
    private var gustDuration: Double = 7
    private var gustDirection: Float = 1
    private var gustStrength: Float = 320
    private var auroraStart: Double?
    private var griswoldStart: Double?
    private var griswoldBlazed = false

    private static let auroraDuration: Double = 46
    private static let griswoldDuration: Double = 11.5

    public init() {}

    /// Brings the shared world up to `now`. Safe to call from every screen each
    /// frame: only the first call for a given instant does any work.
    public func advance(now: Double, config: Config) {
        guard let last = lastTime else {
            lastTime = now
            return
        }
        let dt = Float(min(now - last, 0.1))
        guard dt > 0 else { return }
        lastTime = now
        // Wrapped so single-precision phase arithmetic stays smooth after days of uptime.
        world.time = Float(now.truncatingRemainder(dividingBy: 4096))

        // Ambient wind wanders slowly; the setting scales how far.
        let strength = Float(config.wind)
        var wind = Noise.fbm(Float(now) * 0.045, seed: 3) * 130 * strength
        wind += Noise.fbm(Float(now) * 0.33, seed: 9) * 34 * strength

        if let start = gustStart {
            let u = Float((now - start) / gustDuration)
            if u >= 1 {
                gustStart = nil
                world.gust = 0
            } else {
                let envelope = powf(sinf(u * .pi), 1.5)
                world.gust = envelope
                wind += gustDirection * gustStrength * envelope
            }
        }
        world.wind = wind

        if let start = auroraStart {
            let t = now - start
            if t >= Director.auroraDuration {
                auroraStart = nil
                world.aurora = 0
            } else {
                world.aurora = smoothstep(0, 6, Float(t)) * (1 - smoothstep(Float(Director.auroraDuration) - 8, Float(Director.auroraDuration), Float(t)))
            }
        }

        updateGriswold(now: now)

        if var santa = world.santa {
            santa.elapsed += dt
            world.santa = santa.elapsed >= santa.duration ? nil : santa
        }

        schedule(now: now, config: config)
    }

    // MARK: Scheduling

    private func schedule(now: Double, config: Config) {
        guard config.enabled, let interval = config.surpriseFrequency.interval else {
            nextSurprise = nil
            lastFrequency = config.surpriseFrequency
            return
        }
        if nextSurprise == nil || lastFrequency != config.surpriseFrequency {
            // The first one comes sooner, so a new user sees something before long.
            let first = lastFrequency == nil
            nextSurprise = now + pick(interval) * (first ? 0.25 : 0.6) * seasonalFactor()
            lastFrequency = config.surpriseFrequency
        }
        guard let due = nextSurprise, now >= due else { return }
        nextSurprise = now + pick(interval) * seasonalFactor()
        if let kind = chooseKind(config: config) {
            trigger(kind, now: now, config: config)
        }
    }

    private func pick(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * Double(rng.unit())
    }

    /// Surprises come faster on Christmas Eve and Christmas Day.
    private func seasonalFactor(date: Date = Date()) -> Double {
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        return (parts.month == 12 && (parts.day == 24 || parts.day == 25)) ? 0.55 : 1
    }

    private static func isNewYear(date: Date = Date()) -> Bool {
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        return (parts.month == 12 && parts.day == 31) || (parts.month == 1 && parts.day == 1)
    }

    private func chooseKind(config: Config) -> SurpriseKind? {
        var weighted: [(SurpriseKind, Float)] = []
        for kind in SurpriseKind.allCases where config.isSurpriseEnabled(kind) && kind != lastKind {
            let weight: Float
            switch kind {
            case .santa: weight = 3
            case .shootingStar: weight = 3
            case .gust: weight = config.snowEnabled ? 2 : 0
            case .presents: weight = 2
            case .aurora: weight = 1.5
            case .griswold: weight = config.lightsEnabled ? 1.5 : 0
            case .snowman: weight = 1.5
            case .snowball: weight = 1.5
            case .fireworks: weight = Director.isNewYear() ? 4 : 0
            }
            if weight > 0 { weighted.append((kind, weight)) }
        }
        let total = weighted.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var roll = rng.unit() * total
        for (kind, weight) in weighted {
            roll -= weight
            if roll <= 0 { return kind }
        }
        return weighted.last?.0
    }

    // MARK: Triggers

    /// Starts a surprise right now, as the menu's "Surprise Me" does.
    public func trigger(_ kind: SurpriseKind, now: Double? = nil, config: Config) {
        let now = now ?? lastTime ?? 0
        lastKind = kind
        let available = scenes().filter { !$0.isSuspended }
        switch kind {
        case .santa:
            startSanta()
            if world.santa != nil { onSound?(.sleighBells(duration: Double(world.santa?.duration ?? 8))) }
        case .gust:
            gustStart = now
            gustDuration = Double(rng.range(6, 9))
            gustDirection = rng.chance(0.5) ? 1 : -1
            gustStrength = rng.range(300, 440)
        case .aurora:
            auroraStart = now
        case .griswold:
            griswoldStart = now
            griswoldBlazed = false
        case .shootingStar:
            available.randomElement()?.startShootingStar()
            onSound?(.chime)
        case .presents:
            available.randomElement()?.startPresents()
        case .snowman:
            available.randomElement()?.startSnowman()
        case .snowball:
            available.randomElement()?.startSnowball()
        case .fireworks:
            available.forEach { $0.startFireworks() }
        }
    }

    private func startSanta() {
        let bounds = desktopBounds()
        guard bounds.width > 100 else { return }
        let direction: Float = rng.chance(0.65) ? 1 : -1
        let scale: Float = bounds.height > 1300 ? 1.25 : 1
        let train = (Float(SantaFlight.reindeerCount) * SantaFlight.reindeerGap + 150) * scale
        let left = Float(bounds.minX) - 90
        let right = Float(bounds.maxX) + 90
        let startX = direction > 0 ? left : right
        let endX = direction > 0 ? right + train : left - train
        let speed: Float = rng.range(250, 330) * scale
        world.santa = SantaFlight(
            startX: startX, endX: endX,
            baseY: Float(bounds.minY) + Float(bounds.height) * rng.range(0.24, 0.36),
            amplitude: Float(bounds.height) * rng.range(0.07, 0.13),
            direction: direction, elapsed: 0,
            duration: abs(endX - startX) / speed,
            scale: scale
        )
    }

    private func updateGriswold(now: Double) {
        guard let start = griswoldStart else {
            world.boost = LightBoost()
            return
        }
        let t = Float(now - start)
        var boost = LightBoost()
        if t < 1.5 {
            // The string sputters...
            boost.sputter = 0.15 + 0.5 * (t / 1.5)
        } else if t < 3.7 {
            // ...dies...
            boost.level = 0
        } else if t < Float(Director.griswoldDuration) {
            // ...and comes back with everything it has.
            if !griswoldBlazed {
                griswoldBlazed = true
                world.blazeSerial += 1
                onSound?(.powerUp)
            }
            let since = t - 3.7
            let settle = 1 - smoothstep(6.0, 7.8, since)
            boost.level = 1 + (0.45 + 1.0 * expf(-since * 1.1)) * settle
            boost.bloom = (0.5 + 1.6 * expf(-since * 1.3)) * settle
        } else {
            griswoldStart = nil
        }
        world.boost = boost
    }

    /// Stops anything in flight (used when the app is switched off).
    public func reset() {
        let serial = world.blazeSerial
        world = World()
        world.blazeSerial = serial
        gustStart = nil
        auroraStart = nil
        griswoldStart = nil
        nextSurprise = nil
        lastFrequency = nil
        lastTime = nil
    }
}
