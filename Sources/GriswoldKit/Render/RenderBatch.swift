import Foundation
import simd

/// Shape ids understood by the sprite fragment shader.
public enum Shape {
    public static let dot: Float = 0
    public static let crystal: Float = 1
    public static let halo: Float = 2
    public static let bulb: Float = 3
    public static let glint: Float = 4
    public static let atlas: Float = 5
    public static let clump: Float = 6
    public static let aurora: Float = 7
    public static let streak: Float = 8
    public static let frost: Float = 9
}

/// One instanced quad. Layout must match `Sprite` in the shader (64 bytes).
public struct SpriteInstance {
    public var pos: SIMD2<Float>
    public var size: SIMD2<Float>
    public var color: SIMD4<Float>
    public var uv: SIMD4<Float>
    public var rot: Float
    public var shape: Float
    public var p0: Float
    public var p1: Float

    @inline(__always)
    public init(pos: SIMD2<Float>, size: SIMD2<Float>, color: SIMD4<Float>,
                uv: SIMD4<Float> = SIMD4(0, 0, 1, 1), rot: Float = 0,
                shape: Float, p0: Float = 0, p1: Float = 0) {
        self.pos = pos
        self.size = size
        self.color = color
        self.uv = uv
        self.rot = rot
        self.shape = shape
        self.p0 = p0
        self.p1 = p1
    }
}

/// One mesh vertex. Layout must match `MeshIn` in the shader (32 bytes).
public struct MeshVertex {
    public var pos: SIMD2<Float>
    public var aux: SIMD2<Float>
    public var color: SIMD4<Float>

    @inline(__always)
    public init(_ pos: SIMD2<Float>, _ color: SIMD4<Float>) {
        self.pos = pos
        self.aux = .zero
        self.color = color
    }
}

/// Everything one screen draws in a frame, in paint order. Sprites and mesh
/// triangles can be interleaved; consecutive items of one kind share a draw call.
public final class RenderBatch {
    public enum Command {
        case sprites(Range<Int>)
        case mesh(Range<Int>)
    }

    public private(set) var sprites: [SpriteInstance] = []
    public private(set) var mesh: [MeshVertex] = []
    public private(set) var commands: [Command] = []

    public init() {
        sprites.reserveCapacity(4096)
        mesh.reserveCapacity(8192)
    }

    public func reset() {
        sprites.removeAll(keepingCapacity: true)
        mesh.removeAll(keepingCapacity: true)
        commands.removeAll(keepingCapacity: true)
    }

    public var isEmpty: Bool { commands.isEmpty }

    @inline(__always)
    public func add(_ sprite: SpriteInstance) {
        let index = sprites.count
        sprites.append(sprite)
        if case .sprites(let range)? = commands.last {
            commands[commands.count - 1] = .sprites(range.lowerBound..<(index + 1))
        } else {
            commands.append(.sprites(index..<(index + 1)))
        }
    }

    @inline(__always)
    private func noteMesh(added count: Int) {
        let end = mesh.count
        if case .mesh(let range)? = commands.last {
            commands[commands.count - 1] = .mesh(range.lowerBound..<end)
        } else {
            commands.append(.mesh((end - count)..<end))
        }
    }

    @inline(__always)
    public func triangle(_ a: MeshVertex, _ b: MeshVertex, _ c: MeshVertex) {
        mesh.append(a)
        mesh.append(b)
        mesh.append(c)
        noteMesh(added: 3)
    }

    /// Quad given as a strip: a-b on one side, c-d on the other.
    @inline(__always)
    public func quad(_ a: MeshVertex, _ b: MeshVertex, _ c: MeshVertex, _ d: MeshVertex) {
        mesh.append(a)
        mesh.append(b)
        mesh.append(c)
        mesh.append(b)
        mesh.append(d)
        mesh.append(c)
        noteMesh(added: 6)
    }

    /// Anti-aliased polyline: a solid core with a feathered edge on each side.
    public func polyline(_ points: [SIMD2<Float>], width: Float, color: SIMD4<Float>, feather: Float = 0.9) {
        guard points.count >= 2 else { return }
        let half = width * 0.5
        let clear = SIMD4<Float>(color.x, color.y, color.z, 0)
        var previous: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)?
        for i in 0..<points.count {
            let p = points[i]
            let before = points[max(i - 1, 0)]
            let after = points[min(i + 1, points.count - 1)]
            var tangent = after - before
            let len = simd_length(tangent)
            tangent = len > 0.0001 ? tangent / len : SIMD2(1, 0)
            let normal = SIMD2<Float>(-tangent.y, tangent.x)
            let current = (p - normal * (half + feather), p - normal * half,
                           p + normal * half, p + normal * (half + feather))
            if let prev = previous {
                quad(MeshVertex(prev.0, clear), MeshVertex(current.0, clear),
                     MeshVertex(prev.1, color), MeshVertex(current.1, color))
                quad(MeshVertex(prev.1, color), MeshVertex(current.1, color),
                     MeshVertex(prev.2, color), MeshVertex(current.2, color))
                quad(MeshVertex(prev.2, color), MeshVertex(current.2, color),
                     MeshVertex(prev.3, clear), MeshVertex(current.3, clear))
            }
            previous = current
        }
    }
}
