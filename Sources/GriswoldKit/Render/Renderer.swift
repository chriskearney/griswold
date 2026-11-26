import CoreGraphics
import Foundation
import Metal
import simd

struct FrameUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var time: Float
}

/// Pipelines and the art atlas, shared by every screen.
public final class Renderer {
    public let device: MTLDevice
    public let queue: MTLCommandQueue
    public static let pixelFormat: MTLPixelFormat = .bgra8Unorm

    private let spritePipeline: MTLRenderPipelineState
    private let meshPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    public let atlas: Atlas
    /// Bound when no frost has been wiped: a single zero texel.
    private let blankMask: MTLTexture

    public init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: ShaderSource.metal, options: nil)
        } catch {
            NSLog("Griswold: shader compile failed: \(error)")
            return nil
        }

        func pipeline(_ vertex: String, _ fragment: String) -> MTLRenderPipelineState? {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = Renderer.pixelFormat
            // Premultiplied "over". A fragment with colour but little alpha adds
            // light instead of covering, which is how glows are drawn.
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }

        guard
            let sprite = pipeline("sprite_vertex", "sprite_fragment"),
            let mesh = pipeline("mesh_vertex", "mesh_fragment")
        else {
            NSLog("Griswold: pipeline creation failed")
            return nil
        }
        spritePipeline = sprite
        meshPipeline = mesh

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor),
              let atlas = Atlas(device: device, queue: queue),
              let blank = Renderer.makeMask(device: device, width: 1, height: 1)
        else { return nil }
        var zero: UInt8 = 0
        blank.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &zero, bytesPerRow: 1)
        self.sampler = sampler
        self.atlas = atlas
        blankMask = blank
    }

    /// A one-channel texture recording where frost has been wiped away.
    static func makeMask(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: max(width, 1), height: max(height, 1), mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        return device.makeTexture(descriptor: descriptor)
    }

    /// Encodes one batch into an already configured render pass.
    func encode(_ batch: RenderBatch, buffers: FrameBuffers, encoder: MTLRenderCommandEncoder,
                viewport: SIMD2<Float>, scale: Float, time: Float, texture: MTLTexture? = nil,
                mask: MTLTexture? = nil) {
        guard !batch.isEmpty else { return }
        var uniforms = FrameUniforms(viewport: viewport, scale: scale, time: time)
        let (spriteBuffer, meshBuffer) = buffers.upload(batch, device: device)

        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentTexture(texture ?? atlas.texture, index: 0)
        encoder.setFragmentTexture(mask ?? blankMask, index: 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)

        var bound = 0
        for command in batch.commands {
            switch command {
            case .sprites(let range):
                guard let spriteBuffer else { continue }
                if bound != 1 {
                    encoder.setRenderPipelineState(spritePipeline)
                    bound = 1
                }
                encoder.setVertexBuffer(
                    spriteBuffer,
                    offset: range.lowerBound * MemoryLayout<SpriteInstance>.stride,
                    index: 0
                )
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: range.count)
            case .mesh(let range):
                guard let meshBuffer else { continue }
                if bound != 2 {
                    encoder.setRenderPipelineState(meshPipeline)
                    bound = 2
                }
                encoder.setVertexBuffer(meshBuffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: range.lowerBound, vertexCount: range.count)
            }
        }
    }
}

/// Keeps a GPU copy of one screen's wiped-frost map up to date.
final class FrostMaskTexture {
    private var texture: MTLTexture?
    private var version = -1

    func texture(for scene: ScreenScene, device: MTLDevice) -> MTLTexture? {
        guard let mask = scene.frostMask else {
            version = -1
            return nil
        }
        if texture == nil || texture!.width != mask.width || texture!.height != mask.height {
            texture = Renderer.makeMask(device: device, width: mask.width, height: mask.height)
            version = -1
        }
        guard let texture else { return nil }
        if version != mask.version {
            version = mask.version
            mask.bytes.withUnsafeBytes { raw in
                texture.replace(region: MTLRegionMake2D(0, 0, mask.width, mask.height), mipmapLevel: 0,
                                withBytes: raw.baseAddress!, bytesPerRow: mask.width)
            }
        }
        return texture
    }
}

/// Per-view vertex storage. A small ring keeps the CPU from rewriting a buffer
/// the GPU may still be reading for the previous frame.
final class FrameBuffers {
    private static let ringSize = 3
    private var spriteBuffers: [MTLBuffer?] = Array(repeating: nil, count: ringSize)
    private var meshBuffers: [MTLBuffer?] = Array(repeating: nil, count: ringSize)
    private var index = 0

    func upload(_ batch: RenderBatch, device: MTLDevice) -> (MTLBuffer?, MTLBuffer?) {
        index = (index + 1) % FrameBuffers.ringSize
        let sprite = fill(&spriteBuffers[index], from: batch.sprites, device: device)
        let mesh = fill(&meshBuffers[index], from: batch.mesh, device: device)
        return (sprite, mesh)
    }

    private func fill<T>(_ buffer: inout MTLBuffer?, from items: [T], device: MTLDevice) -> MTLBuffer? {
        guard !items.isEmpty else { return nil }
        let needed = items.count * MemoryLayout<T>.stride
        if buffer == nil || buffer!.length < needed {
            // Grow in generous steps so a burst of particles does not reallocate every frame.
            let capacity = max(needed * 3 / 2, 64 * 1024)
            buffer = device.makeBuffer(length: capacity, options: .storageModeShared)
        }
        guard let target = buffer else { return nil }
        items.withUnsafeBytes { raw in
            target.contents().copyMemory(from: raw.baseAddress!, byteCount: needed)
        }
        return target
    }
}
