import Foundation
import simd

/// Snow resting on a horizontal edge, stored as a row of column heights.
///
/// A height field is cheap to simulate and still looks right: flakes add to the
/// column they hit, and columns that get too steep spill onto their neighbours.
public final class SnowPile {
    /// Width of one column, in points.
    public static let cell: Float = 3

    public let id: UInt32
    /// Left end of column 0.
    public private(set) var originX: Float
    /// The edge the snow sits on.
    public var y: Float
    public private(set) var heights: [Float]
    public var maxHeight: Float
    /// Window piles thin out toward their ends; the ground does not.
    public let tapered: Bool
    private let seed: Int
    private var settled = true

    public init(id: UInt32, originX: Float, width: Float, y: Float, maxHeight: Float, tapered: Bool) {
        self.id = id
        self.originX = originX
        self.y = y
        self.maxHeight = maxHeight
        self.tapered = tapered
        seed = Int(id) &* 7919 &+ 13
        heights = Array(repeating: 0, count: max(Int((width / SnowPile.cell).rounded(.up)), 1))
    }

    public var width: Float { Float(heights.count) * SnowPile.cell }

    /// Total snow held, as an area in square points.
    public var volume: Float {
        heights.reduce(0, +) * SnowPile.cell
    }

    public var isEmpty: Bool {
        !heights.contains { $0 > 0.05 }
    }

    /// The tallest this column may grow. Low-frequency noise gives each pile its
    /// own lumpy silhouette instead of a flat ruled top.
    @inline(__always)
    public func limit(at index: Int) -> Float {
        let x = Float(index)
        let lumps = 0.58 + 0.30 * Noise.value(x * 0.022, seed: seed) + 0.12 * Noise.value(x * 0.075, seed: seed &+ 5)
        var limit = maxHeight * lumps
        if tapered {
            let fromEnd = Float(min(index, heights.count - 1 - index))
            limit *= smoothstep(1, 9, fromEnd)
        }
        return limit
    }

    /// Height at a horizontal position, linearly interpolated.
    @inline(__always)
    public func height(atX x: Float) -> Float {
        let f = (x - originX) / SnowPile.cell - 0.5
        let i = Int(f.rounded(.down))
        guard i >= -1, i < heights.count else { return 0 }
        let t = f - Float(i)
        let a = i >= 0 ? heights[i] : heights[0]
        let b = i + 1 < heights.count ? heights[i + 1] : heights[heights.count - 1]
        return a + (b - a) * t
    }

    /// Adds snow at `x`. `amount` is an area in square points.
    /// - Returns: false when the pile is already full there and the snow slides off.
    @discardableResult
    public func deposit(x: Float, amount: Float, force: Bool = false) -> Bool {
        let i = Int(((x - originX) / SnowPile.cell).rounded(.down))
        guard i >= 0, i < heights.count else { return false }
        let cap = limit(at: i)
        if !force {
            guard cap > 0.3 else { return false }
            // Fill more reluctantly near the top so piles round off naturally.
            let fullness = heights[i] / cap
            if fullness >= 1 { return false }
        }
        // Spread over five columns: a flake is wider than one cell, and the
        // overlap is what keeps the surface from looking like a bar chart.
        let rise = amount / SnowPile.cell
        let last = heights.count - 1
        heights[i] += rise * 0.30
        heights[max(i - 1, 0)] += rise * 0.25
        heights[min(i + 1, last)] += rise * 0.25
        heights[max(i - 2, 0)] += rise * 0.10
        heights[min(i + 2, last)] += rise * 0.10
        settled = false
        return true
    }

    /// Lets over-steep columns slump onto their neighbours.
    public func relax() {
        guard !settled, heights.count > 1 else { return }
        let maxStep: Float = 0.85 * SnowPile.cell
        var moved = false
        for i in 0..<(heights.count - 1) {
            let difference = heights[i] - heights[i + 1]
            if difference > maxStep {
                let flow = (difference - maxStep) * 0.25
                heights[i] -= flow
                heights[i + 1] += flow
                moved = true
            } else if difference < -maxStep {
                let flow = (-difference - maxStep) * 0.25
                heights[i] += flow
                heights[i + 1] -= flow
                moved = true
            }
        }
        settled = !moved
    }

    /// Lowers every column by `amount` points.
    public func melt(_ amount: Float) {
        for i in heights.indices where heights[i] > 0 {
            heights[i] = max(heights[i] - amount, 0)
        }
    }

    /// Lowers columns that stand above their current limit (after the user picks a shallower depth).
    public func settleToLimit(rate: Float) {
        for i in heights.indices {
            let cap = limit(at: i)
            if heights[i] > cap { heights[i] = max(cap, heights[i] - rate) }
        }
    }

    /// Re-anchors the pile after its window changed width, keeping snow that is
    /// still over the edge exactly where it was.
    public func reshape(originX newOrigin: Float, width: Float) {
        let count = max(Int((width / SnowPile.cell).rounded(.up)), 1)
        let shift = Int(((newOrigin - originX) / SnowPile.cell).rounded())
        if shift == 0, count == heights.count {
            originX = newOrigin
            return
        }
        var next = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let source = i + shift
            if source >= 0, source < heights.count { next[i] = heights[source] }
        }
        heights = next
        originX = newOrigin
        settled = false
    }

    public struct Chunk {
        public var x: Float
        public var y: Float
        public var amount: Float
    }

    /// Empties the pile, handing back its snow as chunks that can fall.
    public func shed(maxChunks: Int = 140) -> [Chunk] {
        var chunks: [Chunk] = []
        let stride = max(heights.count / maxChunks, 2)
        var i = 0
        while i < heights.count {
            let end = min(i + stride, heights.count)
            var area: Float = 0
            var peak: Float = 0
            for j in i..<end {
                area += heights[j] * SnowPile.cell
                peak = max(peak, heights[j])
            }
            if area > 1.5 {
                let x = originX + (Float(i) + Float(end - i) * 0.5) * SnowPile.cell
                chunks.append(Chunk(x: x, y: y - peak * 0.5, amount: area))
            }
            i = end
        }
        for j in heights.indices { heights[j] = 0 }
        settled = true
        return chunks
    }

    /// Skims a little snow off the top (wind), returning where it came from.
    public func skim(_ rng: inout FastRNG, probability: Float, amount: Float) -> [SIMD2<Float>] {
        var points: [SIMD2<Float>] = []
        var i = 0
        while i < heights.count {
            if heights[i] > 1.2, rng.chance(probability) {
                heights[i] -= amount
                points.append(SIMD2(originX + (Float(i) + 0.5) * SnowPile.cell, y - heights[i]))
            }
            i += 2
        }
        return points
    }

    /// Emits the pile's triangles between `lo` and `hi` (clipped to visible parts).
    public func draw(into batch: RenderBatch, from lo: Float, to hi: Float, opacity: Float = 1) {
        let n = heights.count
        guard n > 1 else { return }
        let first = max(Int(((lo - originX) / SnowPile.cell).rounded(.down)), 0)
        let last = min(Int(((hi - originX) / SnowPile.cell).rounded(.up)), n - 1)
        guard last > first else { return }

        let base = y + 0.75
        let feather: Float = 1.3
        var previous: (x: Float, h: Float)?
        for i in first...last {
            let h = (heights[max(i - 2, 0)] + heights[min(i + 2, n - 1)]
                + 4 * (heights[max(i - 1, 0)] + heights[min(i + 1, n - 1)])
                + 6 * heights[i]) * (1.0 / 16.0)
            let x = min(max(originX + (Float(i) + 0.5) * SnowPile.cell, lo), hi)
            if let p = previous, p.h > 0.12 || h > 0.12 {
                let alphaA = smoothstep(0.1, 1.6, p.h) * opacity
                let alphaB = smoothstep(0.1, 1.6, h) * opacity
                let topA = SIMD2<Float>(p.x, base - p.h)
                let topB = SIMD2<Float>(x, base - h)
                // Bluish in the shade at the bottom, clean white on top.
                let shadeA = SIMD4<Float>(0.80, 0.87, 0.96, alphaA)
                let shadeB = SIMD4<Float>(0.80, 0.87, 0.96, alphaB)
                let whiteA = SIMD4<Float>(1, 1, 1, alphaA)
                let whiteB = SIMD4<Float>(1, 1, 1, alphaB)
                batch.quad(
                    MeshVertex(SIMD2(p.x, base), shadeA), MeshVertex(SIMD2(x, base), shadeB),
                    MeshVertex(topA, whiteA), MeshVertex(topB, whiteB)
                )
                batch.quad(
                    MeshVertex(topA, whiteA), MeshVertex(topB, whiteB),
                    MeshVertex(SIMD2(p.x, topA.y - feather), SIMD4(1, 1, 1, 0)),
                    MeshVertex(SIMD2(x, topB.y - feather), SIMD4(1, 1, 1, 0))
                )
            }
            previous = (x, h)
        }
    }
}
