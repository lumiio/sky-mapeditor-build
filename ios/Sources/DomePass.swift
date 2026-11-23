import Foundation
import Metal
import MetalKit

// 穹顶通道：完全使用游戏包原版 SkyDomeFade 的 vs/fs metallib（vsmain / fsmain），不做任何自写着色器。
// 绑定布局取自 docs/ir/SkyDomeFade-22h.ios.{vs,fs}.ll 的 air.* 元数据：
//   vs  : buffer0 PerObject 80 B(u_model float4x4 + u_reflected float) / buffer2 PerFrame 1584 B / texture3 u_probeCube(cube)
//   fs  : buffer0 PerObject 160 B(天空参数) / buffer1 PerPass 16 B(u_viewportSize) / buffer2 PerFrame / texture3 u_probeCube
// 顶点输入：a_position float3 / a_color float4 / a_normal float3 / a_uv0 float4 / a_uv1 float4（loc0..4）
// 顶点属性缓冲走 descriptor 的 3/4/5 号槽，避免与原版参数缓冲 0/1/2 冲突。

struct DomeObjectUniforms {
    var u_model: (Float, Float, Float, Float, Float, Float, Float, Float,
                  Float, Float, Float, Float, Float, Float, Float, Float) =
        (1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1)
    var u_reflected: Float = 0
    var _pad0: Float = 0
    var _pad1: Float = 0
    var _pad2: Float = 0
}

final class DomePass {
    private let device: MTLDevice
    let pipeline: MTLRenderPipelineState?
    private let depth: MTLDepthStencilState?
    private var vpos: MTLBuffer?
    private var vnrm: MTLBuffer?
    private var vcuv: MTLBuffer?     // color uchar4 @0 + uv0 half4 @4 + uv1 half4 @12（stride 20）
    private var ibuf: MTLBuffer?
    private var vc = 0
    private var ic = 0
    private var probeCube: MTLTexture?
    private var sampler: MTLSamplerState?
    /// 网格外接球半径（原版 UnitSphere.mesh 解出来是 1.0）
    private(set) var meshRadius: Float = 1.0
    let available: Bool

    init?(device: MTLDevice, assets: URL) {
        self.device = device
        // 原版 metallib 与网格
        let sh = assets.appendingPathComponent("Data/Shaders/Bin")
        guard let vsData = try? Data(contentsOf: sh.appendingPathComponent("SkyDomeFade-22h.ios.vs.metallib")),
              let fsData = try? Data(contentsOf: sh.appendingPathComponent("SkyDomeFade-22h.ios.fs.metallib")) else {
            Boot.log("穹顶: 原版 metallib 缺失")
            return nil
        }
        func dispatch(_ d: Data) -> DispatchData { d.withUnsafeBytes { DispatchData(bytes: $0) } }
        guard let vsLib = try? device.makeLibrary(data: dispatch(vsData)),
              let fsLib = try? device.makeLibrary(data: dispatch(fsData)),
              let vsFn = vsLib.makeFunction(name: "vsmain"),
              let fsFn = fsLib.makeFunction(name: "fsmain") else {
            Boot.log("穹顶: metallib 载入/函数解析失败")
            return nil
        }

        guard let bin = try? Data(contentsOf: assets.appendingPathComponent("UnitSphere.dome.bin")),
              bin.count > 8 else {
            Boot.log("穹顶: UnitSphere.dome.bin 缺失")
            return nil
        }
        vc = Int(bin.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) })
        ic = Int(bin.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) })
        let posBytes = vc * 12, nrmBytes = vc * 12, colBytes = vc * 4, uvBytes = vc * 32, idxBytes = ic * 4
        guard vc > 0, ic > 0, bin.count == 8 + posBytes + nrmBytes + colBytes + uvBytes + idxBytes else {
            Boot.log("穹顶: 网格尺寸不符 vc=\(vc) ic=\(ic) bytes=\(bin.count)")
            return nil
        }
        // 把 color/uv 合到一条 stride=36 的缓冲：color uchar4 @0 / uv0 float4 @4 / uv1 float4 @20
        var interleaved = [UInt8](repeating: 0, count: vc * 36)
        bin.withUnsafeBytes { raw in
            let p = raw.baseAddress!
            memcpy(&interleaved[0], p.advanced(by: 8 + posBytes + nrmBytes), vc * 4)
            memcpy(&interleaved[4], p.advanced(by: 8 + posBytes + nrmBytes + colBytes), vc * 32)
            _ = p
        }
        let dev = device
        func buf(_ base: UnsafeRawPointer, _ n: Int) -> MTLBuffer? {
            dev.makeBuffer(bytes: base, length: max(n, 1), options: .storageModeShared)
        }
        vpos = bin.withUnsafeBytes { buf($0.baseAddress!.advanced(by: 8), posBytes) }
        vnrm = bin.withUnsafeBytes { buf($0.baseAddress!.advanced(by: 8 + posBytes), nrmBytes) }
        vcuv = interleaved.withUnsafeBytes { buf($0.baseAddress!, vc * 36) }
        ibuf = bin.withUnsafeBytes { buf($0.baseAddress!.advanced(by: 8 + posBytes + nrmBytes + colBytes + uvBytes), idxBytes) }

        let vd = MTLVertexDescriptor()
        // 0 a_position
        vd.attributes[0].format = .float3; vd.attributes[0].offset = 0; vd.attributes[0].bufferIndex = 3
        vd.layouts[3].stride = 12; vd.layouts[3].stepFunction = .perVertex
        // 2 a_normal
        vd.attributes[2].format = .float3; vd.attributes[2].offset = 0; vd.attributes[2].bufferIndex = 4
        vd.layouts[4].stride = 12; vd.layouts[4].stepFunction = .perVertex
        // 1 a_color / 3 a_uv0 / 4 a_uv1
        vd.attributes[1].format = .uchar4Normalized; vd.attributes[1].offset = 0; vd.attributes[1].bufferIndex = 5
        vd.attributes[3].format = .float4; vd.attributes[3].offset = 4; vd.attributes[3].bufferIndex = 5
        vd.attributes[4].format = .float4; vd.attributes[4].offset = 20; vd.attributes[4].bufferIndex = 5
        vd.layouts[5].stride = 36; vd.layouts[5].stepFunction = .perVertex

        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = vsFn
        pd.fragmentFunction = fsFn
        pd.vertexDescriptor = vd
        pd.colorAttachments[0].pixelFormat = .rgba16Float
        pd.colorAttachments[1].pixelFormat = .rgba16Float
        pd.depthAttachmentPixelFormat = .depth32Float
        do { pipeline = try device.makeRenderPipelineState(descriptor: pd) }
        catch {
            Boot.log("穹顶: 原版管线创建失败 \(error)")
            pipeline = nil
            return nil
        }

        let dd = MTLDepthStencilDescriptor()
        dd.depthCompareFunction = .always
        dd.isDepthWriteEnabled = false
        depth = device.makeDepthStencilState(descriptor: dd)

        let sd = MTLSamplerDescriptor()
        sd.sAddressMode = .clampToEdge; sd.tAddressMode = .clampToEdge
        sd.minFilter = .linear; sd.magFilter = .linear
        sampler = device.makeSamplerState(descriptor: sd)

        // u_probeCube：1×1 cube，颜色按关卡环境均值；原版采样器的替代，不做二次创作
        let td = MTLTextureDescriptor()
        td.textureType = .typeCube
        td.pixelFormat = .rgba16Float
        td.width = 1; td.height = 1
        td.mipmapLevelCount = 1
        td.usage = .shaderRead
        probeCube = device.makeTexture(descriptor: td)

        available = true
        Boot.log("穹顶: 原版 SkyDomeFade 管线就绪 vc=\(vc) tris=\(ic/3)")
    }

    func setProbeColor(_ c: SIMD3<Float>) {
        guard let probeCube else { return }
        var px: [Float16] = [Float16(c.x), Float16(c.y), Float16(c.z), 1]
        for f in 0..<6 {
            probeCube.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, slice: f,
                              withBytes: &px, bytesPerRow: 8, bytesPerImage: 8)
        }
    }

    /// u_model = 平移(eye) × 缩放(R)；R 取相机远平面内 90%，保证穹顶始终包住视点且不被远裁剪
    func encode(_ enc: MTLRenderCommandEncoder,
                eye: SIMD3<Float>, radiusScale: Float,
                perObject: inout PerObjectUniforms,
                perFrame: inout PerFrameUniforms,
                perPass: inout PerPassUniforms) {
        guard let pipeline, let vpos, let vnrm, let vcuv, let ibuf else { return }
        var obj = DomeObjectUniforms()
        let m = simd_float4x4(
            SIMD4<Float>(radiusScale, 0, 0, 0),
            SIMD4<Float>(0, radiusScale, 0, 0),
            SIMD4<Float>(0, 0, radiusScale, 0),
            SIMD4<Float>(eye.x, eye.y, eye.z, 1))
        obj.u_model = (m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.0.w,
                       m.columns.1.x, m.columns.1.y, m.columns.1.z, m.columns.1.w,
                       m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.2.w,
                       m.columns.3.x, m.columns.3.y, m.columns.3.z, m.columns.3.w)
        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(depth)
        enc.setCullMode(.none)
        enc.setVertexBuffer(vpos, offset: 0, index: 3)
        enc.setVertexBuffer(vnrm, offset: 0, index: 4)
        enc.setVertexBuffer(vcuv, offset: 0, index: 5)
        enc.setVertexBytes(&obj, length: MemoryLayout<DomeObjectUniforms>.stride, index: 0)
        enc.setVertexBytes(&perFrame, length: MemoryLayout<PerFrameUniforms>.stride, index: 2)
        if let probeCube { enc.setVertexTexture(probeCube, index: 3) }
        enc.setFragmentBytes(&perObject, length: MemoryLayout<PerObjectUniforms>.stride, index: 0)
        enc.setFragmentBytes(&perPass, length: MemoryLayout<PerPassUniforms>.stride, index: 1)
        enc.setFragmentBytes(&perFrame, length: MemoryLayout<PerFrameUniforms>.stride, index: 2)
        if let probeCube { enc.setFragmentTexture(probeCube, index: 3) }
        if let sampler { enc.setFragmentSamplerState(sampler, index: 0) }
        enc.drawIndexedPrimitives(type: .triangle, indexCount: ic, indexType: .uint32,
                                  indexBuffer: ibuf, indexBufferOffset: 0)
    }
}
