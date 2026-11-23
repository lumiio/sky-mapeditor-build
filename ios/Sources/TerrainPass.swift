import Foundation
import Metal
import MetalKit
import simd

// 地形通道：顶点/索引/材质区间来自游戏本体 BstBaked.meshes#GEO0（30,838 顶点 / 408 区间），
// 着色器直接用游戏包里的原版 metallib（GrassShMesh-22h.ios.vs/fs），不翻译、不重写。
// 顶点 36 B：pos f32×3 | normal u8x4 | mat u8x4 | weight u8x4 | in2 u8x4 | in3 u8x4 | in4 u8x4
// 属性绑定（按 IR 的 6 个 air.vertex_input）：a_position@0 / a_normal@12 / a_color@24 / a_light0@28 / a_light1@32 / a_light2@20
struct TerrainVertex {
    var pos: (Float, Float, Float) = (0, 0, 0)
    var normal: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
    var mat: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
    var weight: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
    var in2: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
    var in3: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
    var in4: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
}

// 原版 PerObjectUniforms（GrassShMesh-22h.ios.vs.ll 的 air.struct_type_info：112 B / align 4）
struct TerrainPerObject {
    var model: (Float, Float, Float, Float, Float, Float, Float, Float,
                Float, Float, Float, Float, Float, Float, Float, Float) = (1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    var reflected: Float = 0          // +64
    var pad0: (Float, Float, Float) = (0, 0, 0)   // +68  (char[12])
    var matColor: (Float, Float, Float) = (1, 1, 1) // +80 packed_float3
    var matUvScale: Float = 1         // +92
    var matMetalness: Float = 0       // +96
    var pad1: (Float, Float, Float) = (0, 0, 0)   // +100 (char[12])
}

struct TerrainRangeMeta: Decodable {
    let start: Int, count: Int, material: Int, name: String, shader: String?
}

struct TerrainMeta: Decodable {
    let level: String, stride: Int, vertexCount: Int, indexCount: Int
    let ranges: [TerrainRangeMeta]
}

final class TerrainPass {
    private let device: MTLDevice
    private var vbuf: MTLBuffer?
    private var ibuf: MTLBuffer?
    private var pipe: MTLRenderPipelineState?
    private var depth: MTLDepthStencilState?
    private var meta: TerrainMeta?
    private var grassRanges: [TerrainRangeMeta] = []
    private var texSlots: [MTLTexture?] = [nil, nil, nil, nil, nil, nil, nil, nil]
    private var sampler: MTLSamplerState?
    private var rough: Float = 0.85

    init?(device: MTLDevice) {
        self.device = device
        guard let root = Bundle.main.url(forResource: "Assets", withExtension: nil) else { return nil }
        guard let data = try? Data(contentsOf: root.appendingPathComponent("CandleSpace.terrain.bin")),
              data.count > 8 else { return nil }
        let vc = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        let ic = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
        let vbytes = Int(vc) * 36, ibytes = Int(ic) * 4
        guard data.count >= 8 + vbytes + ibytes else { return nil }
        vbuf = data.subdata(in: 8..<(8 + vbytes)).withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: vbytes, options: .storageModeShared)
        }
        ibuf = data.subdata(in: (8 + vbytes)..<(8 + vbytes + ibytes)).withUnsafeBytes {
            device.makeBuffer(bytes: $0.baseAddress!, length: ibytes, options: .storageModeShared)
        }
        if let md = try? Data(contentsOf: root.appendingPathComponent("CandleSpace.terrain.meta.json")),
           let m = try? JSONDecoder().decode(TerrainMeta.self, from: md) {
            meta = m
            grassRanges = m.ranges.filter { $0.shader == "GrassShMesh" }
            Boot.log("terrain meta: \(m.vertexCount) 顶点 / \(m.ranges.count) 区间 / 草地面 \(grassRanges.count) 区间")
        } else { Boot.log("terrain meta 解码失败") }

        // 原版 metallib（游戏包 Data/Shaders/Bin）
        let sub = "Assets/Data/Shaders/Bin"
        guard let vu = Bundle.main.url(forResource: "GrassShMesh-22h.ios.vs", withExtension: "metallib", subdirectory: sub),
              let fu = Bundle.main.url(forResource: "GrassShMesh-22h.ios.fs", withExtension: "metallib", subdirectory: sub),
              let vlib = try? device.makeLibrary(URL: vu), let flib = try? device.makeLibrary(URL: fu),
              let vfn = vlib.makeFunction(name: "vsmain"), let ffn = flib.makeFunction(name: "fsmain") else {
            Boot.log("原版 GrassShMesh metallib 加载失败"); return nil
        }
        Boot.log("原版 GrassShMesh metallib 已加载")

        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float3; vd.attributes[0].offset = 0;  vd.attributes[0].bufferIndex = 1
        vd.attributes[1].format = .uchar4Normalized; vd.attributes[1].offset = 12; vd.attributes[1].bufferIndex = 1
        vd.attributes[2].format = .uchar4Normalized; vd.attributes[2].offset = 24; vd.attributes[2].bufferIndex = 1
        vd.attributes[3].format = .uchar4Normalized; vd.attributes[3].offset = 28; vd.attributes[3].bufferIndex = 1
        vd.attributes[4].format = .uchar4Normalized; vd.attributes[4].offset = 32; vd.attributes[4].bufferIndex = 1
        vd.attributes[5].format = .uchar4Normalized; vd.attributes[5].offset = 20; vd.attributes[5].bufferIndex = 1
        vd.layouts[1].stride = 36
        vd.layouts[1].stepFunction = .perVertex
        vd.layouts[1].stepRate = 1

        let rpd = MTLRenderPipelineDescriptor()
        rpd.vertexFunction = vfn
        rpd.fragmentFunction = ffn
        rpd.vertexDescriptor = vd
        rpd.colorAttachments[0].pixelFormat = .rgba16Float
        rpd.depthAttachmentPixelFormat = .depth32Float
        do { pipe = try device.makeRenderPipelineState(descriptor: rpd) }
        catch { Boot.log("地形管线编译失败: \(error.localizedDescription)"); return nil }

        let ds = MTLDepthStencilDescriptor()
        ds.depthCompareFunction = .lessEqual
        ds.isDepthWriteEnabled = true
        depth = device.makeDepthStencilState(descriptor: ds)

        let sd = MTLSamplerDescriptor()
        sd.sAddressMode = .repeat; sd.tAddressMode = .repeat
        sd.minFilter = .linear; sd.magFilter = .linear
        sd.mipFilter = .linear
        sampler = device.makeSamplerState(descriptor: sd)

        let loader = MTKTextureLoader(device: device)
        let imgRoot = root.appendingPathComponent("Data/Images/Bin")
        func loadTex(_ n: String) -> MTLTexture? {
            guard let t = try? loader.newTexture(URL: imgRoot.appendingPathComponent("\(n).png"), options: [.SRGB: false]) else {
                Boot.log("地形贴图缺失 \(n)"); return nil
            }
            return t
        }
        // 槽位严格取 IR 的 air.location_index：3=u_lightPRTex 4=u_lightCSTex 5=u_grassMaskTex 6=u_grassNorm1Tex 7=u_grassNorm2Tex
        var slots: [MTLTexture?] = [nil, nil, nil, nil, nil, nil, nil, nil]
        slots[3] = loadTex("White")          // u_lightPRTex（光簇图集，数据待解，暂用 1x1）
        slots[4] = loadTex("White")          // u_lightCSTex
        slots[5] = loadTex("GrassMask")
        slots[6] = loadTex("GrassNorTex0")
        slots[7] = loadTex("GrassNorTex1")
        texSlots = slots
    }

    func encode(_ enc: MTLRenderCommandEncoder, perFrame: inout PerFrameUniforms, perPass: SIMD4<Float>) {
        guard let pipe, let vbuf, let ibuf, let depth, let sampler, grassRanges.count > 0 else { return }
        enc.setRenderPipelineState(pipe)
        enc.setDepthStencilState(depth)
        enc.setVertexBuffer(vbuf, offset: 0, index: 1)
        var obj = TerrainPerObject()
        obj.reflected = 0
        obj.matColor = (1, 1, 1)
        obj.matUvScale = 1
        obj.matMetalness = 0
        enc.setVertexBytes(&obj, length: MemoryLayout<TerrainPerObject>.stride, index: 0)
        enc.setVertexBytes(&perFrame, length: MemoryLayout<PerFrameUniforms>.stride, index: 2)
        var ro: Float = rough
        enc.setFragmentBytes(&ro, length: 4, index: 0)
        var pp = perPass
        enc.setFragmentBytes(&pp, length: 16, index: 1)
        enc.setFragmentBytes(&perFrame, length: MemoryLayout<PerFrameUniforms>.stride, index: 2)
        for (i, t) in texSlots.enumerated() where t != nil { enc.setFragmentTexture(t, index: i) }
        for i in 3..<8 { enc.setFragmentSamplerState(sampler, index: i) }
        for r in grassRanges {
            enc.drawIndexedPrimitives(type: .triangle, indexCount: r.count, indexType: .uint32,
                                      indexBuffer: ibuf, indexBufferOffset: r.start * 4)
        }
    }
}
