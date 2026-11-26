import Foundation

/// Small, fast, seedable generator (xorshift64*). The simulation draws thousands of
/// random numbers a second, and a deterministic seed makes snapshots reproducible.
public struct FastRNG {
    private var state: UInt64

    public init(seed: UInt64 = 0x9E37_79B9_7F4A_7C15) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    @inline(__always)
    public mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }

    /// Uniform in 0..<1.
    @inline(__always)
    public mutating func unit() -> Float {
        Float(next() >> 40) * (1.0 / 16_777_216.0)
    }

    @inline(__always)
    public mutating func range(_ lo: Float, _ hi: Float) -> Float {
        lo + (hi - lo) * unit()
    }

    /// Uniform in -1...1.
    @inline(__always)
    public mutating func signed() -> Float {
        unit() * 2 - 1
    }

    @inline(__always)
    public mutating func chance(_ probability: Float) -> Bool {
        unit() < probability
    }

    public mutating func int(_ upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }
}

/// Stateless hashing and smooth noise used for wind, twinkle and pile shapes.
public enum Noise {
    @inline(__always)
    public static func hash(_ n: Int) -> Float {
        var x = UInt32(truncatingIfNeeded: n) &* 0x27D4_EB2D
        x ^= x >> 15
        x = x &* 0x85EB_CA6B
        x ^= x >> 13
        x = x &* 0xC2B2_AE35
        x ^= x >> 16
        return Float(x & 0x00FF_FFFF) * (1.0 / 16_777_216.0)
    }

    @inline(__always)
    public static func hash(_ a: Int, _ b: Int) -> Float {
        hash(a &* 73_856_093 ^ b &* 19_349_663)
    }

    /// Smooth value noise in 0...1 along one axis.
    public static func value(_ x: Float, seed: Int = 0) -> Float {
        let i = Int(x.rounded(.down))
        let f = x - Float(i)
        let u = f * f * (3 - 2 * f)
        let a = hash(i, seed)
        let b = hash(i + 1, seed)
        return a + (b - a) * u
    }

    /// Two octaves of value noise, roughly -1...1.
    public static func fbm(_ x: Float, seed: Int = 0) -> Float {
        let a = value(x, seed: seed)
        let b = value(x * 2.17 + 13.1, seed: seed &+ 7)
        return (a * 0.67 + b * 0.33) * 2 - 1
    }
}

@inline(__always)
public func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
    min(max(v, lo), hi)
}

@inline(__always)
public func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)
}

@inline(__always)
public func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + (b - a) * t
}
