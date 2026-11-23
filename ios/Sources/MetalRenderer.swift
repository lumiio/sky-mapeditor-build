import Foundation
import Metal
import MetalKit
import UIKit
import simd

struct Uniforms {
    var viewProj: simd_float4x4
    var eyePos: simd_float4
    var sunDir: simd_float4
    var sunColor: simd_float4
    var avgSky: simd_float4
    var pointLight: simd_float4
    var viewport: simd_float4
    var exposure: simd_float4
    var lightShadowConsts: simd_float4
}

struct WaterUniforms {
    var viewProj: simd_float4x4
    var camPos: simd_float4
    var sunDir: simd_float4
    var sunColor: simd_float4
    var skyColor: simd_float4
    var simTerms: simd_float4
    var viewport: simd_float4
    var uvOffA: simd_float4
    var uvOffB: simd_float4
    var uvOffC: simd_float4
}

struct RangeDesc: Decodable {
    let start: Int; let count: Int; let name: String
    let material: Int?; let color: [Float]; let texture: String?; let texture2: String?
    let uvScale: Float?; let min: [Float]; let max: [Float]; let selfLit: [Float]?
    let normTex: String?; let lightTex: String?; let normScale: Float?
}
enum EnvValue: Decodable {
    case num(Float)
    case arr([Float])
    init(from d: Decoder) throws {
        if let v = try? d.singleValueContainer().decode(Float.self) { self = .num(v); return }
        if let a = try? d.singleValueContainer().decode([Float].self) { self = .arr(a); return }
        self = .num(0)
    }
    var first: Float? { switch self { case .num(let v): return v; case .arr(let a): return a.first } }
    var array: [Float] { switch self { case .num(let v): return [v]; case .arr(let a): return a } }
}

struct LightDesc: Decodable {
    let pos: [Float]; let radius: Float; let color: [Float]; let sharp: Float
}

struct BeamoDesc: Decodable { let start: Int; let count: Int; let mesh: String; let skirt: Float; let density: Float; let blurLighting: Int }

struct Manifest: Decodable {
    let level: String; let seaLevel: Float?
    let lights: [LightDesc]?
    let beamos: [BeamoDesc]?
    let env: [String: EnvValue]?
    let vertices: Int; let indices: Int; let stride: Int
    let bounds: [Float]; let focus: [Float]; let ranges: [RangeDesc]
}

final class MetalRenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private var meshPipe: MTLRenderPipelineState?
    private var tonemapPipe: MTLRenderPipelineState?
    private var fxaaPipe: MTLRenderPipelineState?
    private var ldrTex: MTLTexture?
    private var bloomTex: MTLTexture?
    private var blackTex: MTLTexture?
    private var fogPipe: MTLRenderPipelineState?
    private var fogUpsamplePipe: MTLRenderPipelineState?
    private var fogTex: MTLTexture?
    private var fogOut: MTLTexture?
    private var waterPipe: MTLRenderPipelineState?
    private var skyPipe: MTLRenderPipelineState?
    private var domePipe: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    private var waterDepthState: MTLDepthStencilState?
    private var sampler: MTLSamplerState?
    private var clampSampler: MTLSamplerState?
    private var lodSampler: MTLSamplerState?
    private var flatNormal: MTLTexture?
    private var whiteTex: MTLTexture?
    private var probeCube: MTLTexture?
    private var fallbackTex: MTLTexture?
    private var texCache: [String: MTLTexture] = [:]
    // 32×16 屏幕光簇（原版 Mesh2243.frag 的 u_light* 通道）
    private var countsTex: MTLTexture?
    private var offsetsTex: MTLTexture?
    private var posTex: MTLTexture?
    private var colTex: MTLTexture?
    private var countsData = [UInt32](repeating: 0, count: 32 * 16)
    private var offsetsData = [UInt32](repeating: 0, count: 32 * 16)
    private var posData = [Float](repeating: 0, count: 2048 * 4)
    private var colData = [Float](repeating: 0, count: 2048 * 4)

    private(set) var levelName: String = ""
    private var man: Manifest?
    private var vbuf: MTLBuffer?
    private var beamoVB: MTLBuffer?
    private var beamoIB: MTLBuffer?
    private var ibuf: MTLBuffer?
    private var waterVB: MTLBuffer?
    private var waterIB: MTLBuffer?

    var az: Float = 2.10
    var el: Float = 0.28
    var zoom: Float = 1.0
    var center = SIMD3<Float>(0, 0, 0)
    var radius: Float = 10
    var waterY: Float = -5
    var averageLum: Float = 1

    private var sceneTex: MTLTexture?
    private var sceneTex2: MTLTexture?
    private var depthTex: MTLTexture?
    private var width = 0, height = 0
    private(set) var lastError: String?

    init?(level: String) {
        Boot.log("renderer init start level=\(level)")
        guard let dev = MTLCreateSystemDefaultDevice(), let q = dev.makeCommandQueue() else {
            Boot.log("Metal device 不可用"); return nil
        }
        Boot.log("device \(dev.name)")
        device = dev
        queue = q
        // 用构建期编好的 default.metallib，避免运行时编译源码（iOS 上这一步容易直接挂）
        // 注意：被当作 folder 资源打进包时它位于 Shaders/ 子目录，makeDefaultLibrary() 找不到，必须按 URL 加载
        var lib: MTLLibrary?
        do { lib = try dev.makeDefaultLibrary(bundle: .main) } catch { Boot.log("默认库(源码)不可用: \(error.localizedDescription)") }
        if lib == nil {
            for sub in ["Shaders", nil] as [String?] {
                if let u = Bundle.main.url(forResource: "default", withExtension: "metallib", subdirectory: sub),
                   let l = try? dev.makeLibrary(URL: u) { lib = l; Boot.log("metallib 已加载(\(sub ?? "根目录"))"); break }
            }
        }
        guard let library = lib else {
            Boot.log("default.metallib 缺失或加载失败"); return nil
        }
        guard let vfn = library.makeFunction(name: "vs"), let ffn = library.makeFunction(name: "fs"),
              let wvs = library.makeFunction(name: "waterVS"), let wfs = library.makeFunction(name: "waterFS")
        else { Boot.log("shader 函数缺失"); return nil }
        Boot.log("shader 函数就绪")

        let vd = MTLVertexDescriptor()
        // 原版顶点：pos | nrm | a_color | a_uv0(vec4) | a_uv1(vec4) | light0 | light1 | light2 = 72 B
        vd.attributes[0].format = .float3; vd.attributes[0].offset = 0;  vd.attributes[0].bufferIndex = 0
        vd.attributes[1].format = .float3; vd.attributes[1].offset = 12; vd.attributes[1].bufferIndex = 0
        vd.attributes[2].format = .uchar4Normalized; vd.attributes[2].offset = 24; vd.attributes[2].bufferIndex = 0
        vd.attributes[3].format = .float4; vd.attributes[3].offset = 28; vd.attributes[3].bufferIndex = 0
        vd.attributes[4].format = .float4; vd.attributes[4].offset = 44; vd.attributes[4].bufferIndex = 0
        vd.attributes[5].format = .uchar4Normalized; vd.attributes[5].offset = 60; vd.attributes[5].bufferIndex = 0
        vd.attributes[6].format = .uchar4Normalized; vd.attributes[6].offset = 64; vd.attributes[6].bufferIndex = 0
        vd.attributes[7].format = .uchar4Normalized; vd.attributes[7].offset = 68; vd.attributes[7].bufferIndex = 0
        vd.layouts[0].stride = 72          // 顶点结构 72 B（pos/nrm/color/uv01/uv23/light0-2），stride 为 0 会让管线编译直接 abort
        vd.layouts[0].stepFunction = .perVertex
        vd.layouts[0].stepRate = 1

        let rpd = MTLRenderPipelineDescriptor()
        rpd.vertexFunction = vfn; rpd.fragmentFunction = ffn; rpd.vertexDescriptor = vd
        rpd.colorAttachments[0].pixelFormat = .bgra8Unorm
        rpd.depthAttachmentPixelFormat = .depth32Float
        let dsDesc = MTLDepthStencilDescriptor()
        dsDesc.depthCompareFunction = .less
        dsDesc.isDepthWriteEnabled = true

        let wvd = MTLVertexDescriptor()
        wvd.attributes[0].format = .float3; wvd.attributes[0].offset = 0;  wvd.attributes[0].bufferIndex = 0
        wvd.attributes[1].format = .float2; wvd.attributes[1].offset = 12; wvd.attributes[1].bufferIndex = 0
        wvd.layouts[0].stride = 20; wvd.layouts[0].stepFunction = .perVertex; wvd.layouts[0].stepRate = 1
        let bvd = MTLVertexDescriptor()
        bvd.attributes[0].format = .float3; bvd.attributes[0].offset = 0; bvd.attributes[0].bufferIndex = 0
        bvd.layouts[0].stride = 12; bvd.layouts[0].stepFunction = .perVertex; bvd.layouts[0].stepRate = 1
        let frpd2 = MTLRenderPipelineDescriptor()
        frpd2.vertexFunction = library.makeFunction(name: "fogVolumeVS")
        frpd2.fragmentFunction = library.makeFunction(name: "fogVolumeFS")
        frpd2.vertexDescriptor = bvd
        frpd2.colorAttachments[0].pixelFormat = .rgba16Float
        fogPipe = try? dev.makeRenderPipelineState(descriptor: frpd2)

        let wrpd = MTLRenderPipelineDescriptor()
        wrpd.vertexFunction = wvs; wrpd.fragmentFunction = wfs; wrpd.vertexDescriptor = wvd
        wrpd.colorAttachments[0].pixelFormat = .bgra8Unorm

        let wdsDesc = MTLDepthStencilDescriptor()
        wdsDesc.depthCompareFunction = .lessEqual
        wdsDesc.isDepthWriteEnabled = false

        let trpd = MTLRenderPipelineDescriptor()
        trpd.vertexFunction = library.makeFunction(name: "tonemapVS")
        trpd.fragmentFunction = library.makeFunction(name: "tonemapFS")
        trpd.colorAttachments[0].pixelFormat = .bgra8Unorm
        Boot.log("开始建 tonemap 管线")
        tonemapPipe = try? dev.makeRenderPipelineState(descriptor: trpd)

        let urpd = MTLRenderPipelineDescriptor()
        urpd.vertexFunction = library.makeFunction(name: "tonemapVS")
        urpd.fragmentFunction = library.makeFunction(name: "fogUpsampleFS")
        urpd.colorAttachments[0].pixelFormat = .rgba16Float
        fogUpsamplePipe = try? dev.makeRenderPipelineState(descriptor: urpd)
        Boot.log("雾管线 \(fogPipe != nil && fogUpsamplePipe != nil ? "ok" : "失败")")

        let xrpd = MTLRenderPipelineDescriptor()
        xrpd.vertexFunction = library.makeFunction(name: "tonemapVS")
        xrpd.fragmentFunction = library.makeFunction(name: "fxaaFS")
        xrpd.colorAttachments[0].pixelFormat = .bgra8Unorm
        fxaaPipe = try? dev.makeRenderPipelineState(descriptor: xrpd)
        Boot.log("fxaa 管线 \(fxaaPipe != nil ? "ok" : "失败")")

        Boot.log("开始建 mesh 管线 (stride=\(vd.layouts[0].stride))")
        do {
            meshPipe = try dev.makeRenderPipelineState(descriptor: rpd)
            Boot.log("mesh 管线 ok")
        let skp = MTLRenderPipelineDescriptor()
        skp.vertexFunction = library.makeFunction(name: "skyVS")
        skp.fragmentFunction = library.makeFunction(name: "skyFS")
        skp.colorAttachments[0].pixelFormat = .rgba16Float
        skyPipe = try? dev.makeRenderPipelineState(descriptor: skp)
        let dpd = MTLRenderPipelineDescriptor()
        dpd.vertexFunction = library.makeFunction(name: "domeVS")
        dpd.fragmentFunction = library.makeFunction(name: "domeFS")
        dpd.vertexDescriptor = vd
        dpd.colorAttachments[0].pixelFormat = .rgba16Float
        domePipe = try? dev.makeRenderPipelineState(descriptor: dpd)
            waterPipe = try dev.makeRenderPipelineState(descriptor: wrpd)
            Boot.log("water 管线 ok")
        } catch { Boot.log("pipeline 失败: \(error)"); return nil }
        Boot.log("pipeline 构建完成")
        guard let ds = dev.makeDepthStencilState(descriptor: dsDesc),
              let wds = dev.makeDepthStencilState(descriptor: wdsDesc) else {
            Boot.log("depth state 创建失败"); return nil
        }
        depthState = ds; waterDepthState = wds

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear; sd.magFilter = .linear
        sd.sAddressMode = .repeat; sd.tAddressMode = .repeat
        let cd = MTLSamplerDescriptor()
        cd.minFilter = .linear; cd.magFilter = .linear
        cd.sAddressMode = .clampToEdge; cd.tAddressMode = .clampToEdge
        let ld = MTLSamplerDescriptor()          // 原版 textureLod(...,5.0) 用的 mip 采样器
        ld.minFilter = .linear; ld.magFilter = .linear; ld.mipFilter = .linear
        ld.sAddressMode = .clampToEdge; ld.tAddressMode = .clampToEdge
        guard let smp = dev.makeSamplerState(descriptor: sd),
              let csmp = dev.makeSamplerState(descriptor: cd),
              let lsmp = dev.makeSamplerState(descriptor: ld) else {
            Boot.log("sampler 创建失败"); return nil
        }
        sampler = smp; clampSampler = csmp; lodSampler = lsmp

        func u32Tex(_ w: Int, _ h: Int) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Uint, width: w, height: h, mipmapped: false)
            d.usage = [.shaderRead]; d.storageMode = .shared
            return dev.makeTexture(descriptor: d)
        }
        func f32Tex(_ w: Int, _ h: Int) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: w, height: h, mipmapped: false)
            d.usage = [.shaderRead]; d.storageMode = .shared
            return dev.makeTexture(descriptor: d)
        }
        countsTex = u32Tex(32, 16); offsetsTex = u32Tex(32, 16)
        posTex = f32Tex(2048, 1); colTex = f32Tex(2048, 1)
        Boot.log("光簇纹理 \(countsTex != nil && posTex != nil ? "ok" : "失败")")

        let fbDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        Boot.log("采样器就绪")
        guard let fb = dev.makeTexture(descriptor: fbDesc) else {
            Boot.log("fallback texture 创建失败"); return nil
        }
        fallbackTex = fb
        var white: [UInt8] = [255, 255, 255, 255]
        fb.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &white, bytesPerRow: 4)
        // u_normTex 缺失时的平法线（原版等价于 (0.5,0.5,1)）
        let fnDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        if let fn = dev.makeTexture(descriptor: fnDesc) {
            var flat: [UInt8] = [128, 128, 255, 255]
            fn.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &flat, bytesPerRow: 4)
            flatNormal = fn
        }
        whiteTex = fb
        // bloom 缺省用一张黑图（原版 bloom 是多级 downsample，这里不造假数据）
        if let blk = dev.makeTexture(descriptor: fbDesc) {
            var zero: [UInt8] = [0, 0, 0, 255]
            blk.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &zero, bytesPerRow: 4)
            blackTex = blk
        }

        load(level: level)
        Boot.log("renderer init done \(level) err=\(lastError ?? "-")")
    }

    func assetsURL() -> URL? {
        Bundle.main.url(forResource: "Assets", withExtension: nil)
    }

    func load(level: String) {
        Boot.log("load: 开始 \(level)")
        guard let root = assetsURL() else { Boot.log("Assets 目录缺失"); lastError = "Assets 资源目录缺失"; return }
        Boot.log("Assets \(root.path)")
        let jsonURL = root.appendingPathComponent("\(level).json")
        guard let data = try? Data(contentsOf: jsonURL) else { lastError = "manifest 读不到 \(level)"; return }
        let m: Manifest
        do { m = try JSONDecoder().decode(Manifest.self, from: data) }
        catch { lastError = "manifest 解析失败 \(level): \(error)"; Boot.log("manifest 错误 \(error)"); return }
        man = m; levelName = level
        waterY = m.seaLevel ?? -5

        guard let vb = try? Data(contentsOf: root.appendingPathComponent("\(level).verts")),
              let ib = try? Data(contentsOf: root.appendingPathComponent("\(level).idx")), !vb.isEmpty, !ib.isEmpty else {
            lastError = "顶点/索引数据缺失 \(level)"; return
        }
        vbuf = vb.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress ?? UnsafeRawPointer(bitPattern: 1)!, length: $0.count, options: .storageModeShared) }
        ibuf = ib.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress ?? UnsafeRawPointer(bitPattern: 1)!, length: $0.count, options: .storageModeShared) }
        guard vbuf != nil, ibuf != nil else { lastError = "顶点/索引 buffer 创建失败"; return }

        // 取景：三角形数加权落在最密的一簇
        let mm = m
        var wsum: Float = 0, acc = SIMD3<Float>(0, 0, 0)
        for r in mm.ranges where !(r.name.range(of: "^Cube|^DCube|^Plane|Sky|Cloud|StarField", options: .regularExpression) != nil) {
            let w = Float(r.count)
            acc += SIMD3<Float>((r.min[0]+r.max[0])/2, (r.min[1]+r.max[1])/2, (r.min[2]+r.max[2])/2) * w
            wsum += w
        }
        // 取景用关卡 focus（前景密集区），不然 150 m 背景壳会把相机拉得很远
        let fb = mm.focus
        center = SIMD3<Float>((fb[0]+fb[3])/2, (fb[1]+fb[4])/2, (fb[2]+fb[5])/2)
        radius = max(1, simd_length(SIMD3<Float>(fb[3]-fb[0], fb[4]-fb[1], fb[5]-fb[2])) / 2)

        // Beamo 体积网格（FogVolume 用的遮挡体）
        if let bvURL = root.appendingPathComponent(level + ".beamo.verts") as URL?,
           FileManager.default.fileExists(atPath: bvURL.path),
           let bdata = try? Data(contentsOf: bvURL),
           let bidx = try? Data(contentsOf: root.appendingPathComponent(level + ".beamo.idx")),
           !bdata.isEmpty {
            beamoVB = device.makeBuffer(bytes: (bdata as NSData).bytes, length: bdata.count, options: .storageModeShared)
            beamoIB = device.makeBuffer(bytes: (bidx as NSData).bytes, length: bidx.count, options: .storageModeShared)
            Boot.log("beamo 缓冲 \(bdata.count) B / \(bidx.count) B")
        }

        // 水面：覆盖整关的大平面
        let ext: Float = 600
        var wv: [Float] = []
        let pts: [Float] = [-ext, -ext, ext, -ext, ext, ext, -ext, ext]
        for i in 0..<4 {
            wv.append(center.x + pts[i*2]); wv.append(waterY); wv.append(center.z + pts[i*2+1])
            wv.append(0); wv.append(0)
        }
        var widx: [UInt32] = [0, 1, 2, 0, 2, 3]
        waterVB = wv.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress ?? UnsafeRawPointer(bitPattern: 1)!, length: $0.count, options: .storageModeShared) }
        waterIB = widx.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress ?? UnsafeRawPointer(bitPattern: 1)!, length: $0.count, options: .storageModeShared) }
        _ = widx.count
    }

    /// 照 web/js/viewer.js 的 updateLightClusters 移植：把 Level 的 PointLight 分进 32×16 屏幕格
    private func updateClusters(_ m: simd_float4x4, _ w: Int, _ h: Int) {
        guard let man, let countsTex, let offsetsTex, let posTex, let colTex else { return }
        let lights = man.lights ?? []
        countsData.withUnsafeMutableBufferPointer { $0.initialize(repeating: 0) }
        offsetsData.withUnsafeMutableBufferPointer { $0.initialize(repeating: 0) }
        var cells = [[Int]](repeating: [], count: 512)
        let fpx = Float(h) * 0.5 * abs(m.columns.1.y)
        for (li, L) in lights.enumerated() {
            let p = SIMD3<Float>(L.pos[0], L.pos[1], L.pos[2])
            let c = m * SIMD4<Float>(p, 1)
            if c.w <= 0.05 { continue }
            let nx = c.x / c.w, ny = c.y / c.w, depth = c.z / c.w
            let rpx = (L.radius * fpx) / max(depth, 0.1)
            let gx = (nx * 0.5 + 0.5) * 32
            let gy = (ny * 0.5 + 0.5) * 16
            let rx = (rpx * 32) / Float(max(w, 1)) + 0.5
            let ry = (rpx * 16) / Float(max(h, 1)) + 0.5
            let x0 = max(0, Int(floor(gx - rx))), x1 = min(31, Int(ceil(gx + rx)))
            let y0 = max(0, Int(floor(gy - ry))), y1 = min(15, Int(ceil(gy + ry)))
            if gx < -rx || gx > 32 + rx || gy < -ry || gy > 16 + ry { continue }
            if x0 > 31 || y0 > 15 { continue }
            for y in y0...y1 { for x in x0...x1 {
                if cells[y * 32 + x].count < 4 { cells[y * 32 + x].append(li) }
            } }
        }
        var cursor = 0
        for i in 0..<512 {
            let list = cells[i]
            offsetsData[i] = UInt32(cursor)
            countsData[i] = UInt32(list.count)
            for li in list {
                let L = lights[li]
                posData[cursor * 4] = L.pos[0]; posData[cursor * 4 + 1] = L.pos[1]
                posData[cursor * 4 + 2] = L.pos[2]
                posData[cursor * 4 + 3] = 1 / (L.radius * L.radius)   // 原版存的是逆平方半径
                colData[cursor * 4] = L.color[0]; colData[cursor * 4 + 1] = L.color[1]
                colData[cursor * 4 + 2] = L.color[2]; colData[cursor * 4 + 3] = L.sharp
                cursor += 1
            }
        }
        let r32 = MTLRegionMake2D(0, 0, 32, 16)
        countsTex.replace(region: r32, mipmapLevel: 0, withBytes: countsData, bytesPerRow: 32 * 4)
        offsetsTex.replace(region: r32, mipmapLevel: 0, withBytes: offsetsData, bytesPerRow: 32 * 4)
        posData.withUnsafeBytes { raw in
            posTex.replace(region: MTLRegionMake2D(0, 0, 2048, 1), mipmapLevel: 0,
                           withBytes: raw.baseAddress!, bytesPerRow: 2048 * 16)
        }
        colData.withUnsafeBytes { raw in
            colTex.replace(region: MTLRegionMake2D(0, 0, 2048, 1), mipmapLevel: 0,
                           withBytes: raw.baseAddress!, bytesPerRow: 2048 * 16)
        }
    }

    /// 原版 u_probeCube：由关卡 Ambience 的五段天色烘 32×32×6 立方体（含 mip，供 textureLod 5.0）
    private func buildProbeCubeIfNeeded() {
        guard probeCube == nil, let man else { return }
        func col(_ k: String, _ d: SIMD3<Float>) -> SIMD3<Float> {
            guard let a = man.env?[k]?.array, a.count >= 3 else { return d }
            return SIMD3<Float>(a[0], a[1], a[2])
        }
        let cB = col("tintBot", SIMD3<Float>(0.18, 0.14, 0.1))
        let cMB = col("tintMidBot", SIMD3<Float>(0.16, 0.14, 0.12))
        let cMM = col("tintMidMid", SIMD3<Float>(0.14, 0.14, 0.18))
        let cMT = col("tintMidTop", SIMD3<Float>(0.1, 0.18, 0.3))
        let cT = col("tintTop", SIMD3<Float>(0.02, 0.05, 0.1))
        let sunC = col("sunColor", SIMD3<Float>(1, 0.95, 0.85))
        let sunEl = (man.env?["sunAngleY"]?.first ?? 55) * Float.pi / 180
        let sunAz = (man.env?["sunAngleXZ"]?.first ?? 30) * Float.pi / 180
        let sunDir = simd_normalize(SIMD3<Float>(cos(sunEl) * cos(sunAz), sin(sunEl), cos(sunEl) * sin(sunAz)))
        let sunSize = man.env?["sunSize"]?.first ?? 0.02

        let n = 32
        let d = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba16Float, size: n, mipmapped: true)
        d.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: d) else { return }
        for face in 0..<6 {
            var px = [Float16](repeating: 0, count: n * n * 4)
            for y in 0..<n {
                for x in 0..<n {
                    let u = (Float(x) + 0.5) / Float(n) * 2 - 1
                    let v = (Float(y) + 0.5) / Float(n) * 2 - 1
                    var dir: SIMD3<Float>
                    switch face {
                    case 0: dir = SIMD3<Float>(1, -v, -u)
                    case 1: dir = SIMD3<Float>(-1, -v, u)
                    case 2: dir = SIMD3<Float>(u, 1, v)
                    case 3: dir = SIMD3<Float>(u, -1, -v)
                    case 4: dir = SIMD3<Float>(u, -v, 1)
                    default: dir = SIMD3<Float>(-u, -v, -1)
                    }
                    dir = simd_normalize(dir)
                    let yy = dir.y
                    var c: SIMD3<Float>
                    if yy < -0.35 { c = cB }
                    else if yy < 0 { c = simd_mix(cB, cMB, SIMD3(repeating: (yy + 0.35) / 0.35)) }
                    else if yy < 0.30 { c = simd_mix(cMB, cMT, SIMD3(repeating: yy / 0.30)) }
                    else { c = simd_mix(cMT, cT, SIMD3(repeating: min(1, (yy - 0.30) / 0.70))) }
                    let dSun = simd_dot(dir, sunDir)
                    if dSun > cos(sunSize) { c += sunC * pow((dSun - cos(sunSize)) / (1 - cos(sunSize) + 1e-6), 8) }
                    let i = (y * n + x) * 4
                    px[i] = Float16(c.x); px[i + 1] = Float16(c.y); px[i + 2] = Float16(c.z); px[i + 3] = 1
                }
            }
            tex.replace(region: MTLRegionMake2D(0, 0, n, n), mipmapLevel: 0, slice: face,
                        withBytes: px, bytesPerRow: n * 8, bytesPerImage: n * n * 8)
        }
        if let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: tex)
            blit.endEncoding(); cb.commit()
        }
        probeCube = tex
    }

    private func tex(_ name: String) -> MTLTexture? {
        if let t = texCache[name] { return t }
        guard let root = assetsURL() else { return nil }
        let url = root.appendingPathComponent("Data/Images/Bin/\(name).png")
        let loader = MTKTextureLoader(device: device)
        guard let t = try? loader.newTexture(URL: url, options: [.SRGB: false]) else { return nil }
        texCache[name] = t
        return t
    }

    private func ensureTargets(_ w: Int, _ h: Int) {
        guard w > 0, h > 0, (w != width || h != height || sceneTex == nil) else { return }
        width = w; height = h
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        sceneTex = device.makeTexture(descriptor: d)
        sceneTex2 = device.makeTexture(descriptor: d)
        let fd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        fd.usage = [.renderTarget, .shaderRead]
        fogTex = device.makeTexture(descriptor: fd)
        fogOut = device.makeTexture(descriptor: fd)
        let ld = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        ld.usage = [.renderTarget, .shaderRead]
        ldrTex = device.makeTexture(descriptor: ld)
        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: w, height: h, mipmapped: false)
        dd.usage = [.renderTarget, .shaderRead]
        depthTex = device.makeTexture(descriptor: dd)
    }

    func draw(in view: MTKView) {
        guard let man, let vbuf, let ibuf, let waterVB, let waterIB, let drawable = view.currentDrawable,
              let meshPipe, let waterPipe, let depthState, let waterDepthState,
              let sampler, let clampSampler, let fallbackTex else { return }
        lastError = nil
        let w = view.drawableSize.width > 0 ? Int(view.drawableSize.width) : 1
        let h = view.drawableSize.height > 0 ? Int(view.drawableSize.height) : 1
        ensureTargets(w, h)
        guard let sceneTex, let sceneTex2, let depthTex else { return }

        let dist = radius * 1.15 * zoom
        let eye = center + SIMD3<Float>(cos(el)*cos(az), sin(el), cos(el)*sin(az)) * dist
        let fwd = simd_normalize(center - eye)
        let up = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(fwd, up))
        let camUp = simd_cross(right, fwd)
        let nearD = max(dist * 0.01, 0.05), farD = dist * 20
        let proj = perspective(50.0 * Float.pi / 180, Float(w) / Float(h), nearD, farD)
        let viewM = lookAt(eye, center, camUp)
        let vp = proj * viewM
        updateClusters(vp, w, h)

        func envColor(_ k: String, _ def: SIMD3<Float>) -> SIMD4<Float> {
            guard let a = man.env?[k]?.array, a.count >= 3 else { return SIMD4<Float>(def, 1) }
            return SIMD4<Float>(a[0], a[1], a[2], 1)
        }
        func envNum(_ k: String, _ def: Float) -> Float { man.env?[k]?.first ?? def }

        let sunEl = envNum("sunAngleY", 55) * Float.pi / 180
        let sunAz = envNum("sunAngleXZ", 30) * Float.pi / 180
        let sunDir = simd_normalize(SIMD3<Float>(cos(sunEl)*cos(sunAz), sin(sunEl), cos(sunEl)*sin(sunAz)))

        let avgSkyC = envColor("tintMidMid", SIMD3<Float>(0.14, 0.14, 0.18))
        let plC = envColor("pointColor", SIMD3<Float>(1, 0.85, 0.6))
        let plK = envNum("pointIntensity", 1)
        var u = Uniforms(viewProj: vp, eyePos: SIMD4<Float>(eye, 1),
                         sunDir: SIMD4<Float>(sunDir, 0),
                         sunColor: envColor("sunColor", SIMD3<Float>(1, 0.95, 0.85)),
                         avgSky: SIMD4<Float>(avgSkyC.x, avgSkyC.y, avgSkyC.z, 0),
                         pointLight: SIMD4<Float>(plC.x * plK, plC.y * plK, plC.z * plK, 0),
                         viewport: SIMD4<Float>(Float(w), Float(h), 0, 0),
                         exposure: SIMD4<Float>(envNum("exposure", 1), 0, 0, 0),
                         lightShadowConsts: SIMD4<Float>(0, 0, 1, 0))

        guard let cb = queue.makeCommandBuffer() else { return }

        // Pass 1：场景
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = sceneTex
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1)
        rp.colorAttachments[0].storeAction = .store
        rp.depthAttachment.texture = depthTex
        rp.depthAttachment.loadAction = .clear
        rp.depthAttachment.storeAction = .store
        rp.depthAttachment.clearDepth = 1

        guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        enc.setRenderPipelineState(meshPipe)
        enc.setDepthStencilState(depthState)
        enc.setVertexBuffer(vbuf, offset: 0, index: 0)
        enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setFragmentSamplerState(clampSampler, index: 1)
        if let lodSampler {
            enc.setFragmentSamplerState(lodSampler, index: 2)
            enc.setVertexSamplerState(lodSampler, index: 0)
        }
        buildProbeCubeIfNeeded()
        if let probeCube {
            enc.setVertexTexture(probeCube, index: 0)
            enc.setFragmentTexture(probeCube, index: 8)
        }
        if let offsetsTex, let countsTex, let posTex, let colTex {
            enc.setFragmentTexture(offsetsTex, index: 4)
            enc.setFragmentTexture(countsTex, index: 5)
            enc.setFragmentTexture(posTex, index: 6)
            enc.setFragmentTexture(colTex, index: 7)
        }
        // SkyDomeFade 穹顶：原版那一关的 Plane 段（6 索引）走穹顶管线，采 u_probeCube
        if let domePipe, let probeCube {
            for r in man.ranges where r.name.lowercased() == "plane" {
                enc.setRenderPipelineState(domePipe)
                enc.setFragmentTexture(probeCube, index: 0)
                enc.setFragmentSamplerState(clampSampler, index: 0)
                enc.drawIndexedPrimitives(type: .triangle, indexCount: r.count, indexType: .uint32,
                                          indexBuffer: ibuf, indexBufferOffset: r.start * 4)
            }
            enc.setRenderPipelineState(meshPipe)
        }
        for r in man.ranges where r.name.lowercased() != "plane" {
            let c = SIMD4<Float>(r.color.count >= 3 ? r.color[0] : 1, r.color.count >= 3 ? r.color[1] : 1, r.color.count >= 3 ? r.color[2] : 1, 1)
            if let n = r.texture, let t = tex(n) { enc.setFragmentTexture(t, index: 0) } else { enc.setFragmentTexture(fallbackTex, index: 0) }
            if let n = r.texture2, let t = tex(n) { enc.setFragmentTexture(t, index: 1) } else { enc.setFragmentTexture(fallbackTex, index: 1) }
            var cc = c
            enc.setFragmentBytes(&cc, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
            // u_normTex / u_lightTex / u_selfLit / 两个 uv 缩放
            if let n = r.normTex, let t = tex(n) { enc.setFragmentTexture(t, index: 2) } else { enc.setFragmentTexture(flatNormal ?? fallbackTex, index: 2) }
            if let n = r.lightTex, let t = tex(n) { enc.setFragmentTexture(t, index: 3) } else { enc.setFragmentTexture(whiteTex ?? fallbackTex, index: 3) }
            var sl = SIMD4<Float>(r.selfLit?.count ?? 0 >= 4 ? r.selfLit![0] : 0,
                                  r.selfLit?.count ?? 0 >= 4 ? r.selfLit![1] : 0,
                                  r.selfLit?.count ?? 0 >= 4 ? r.selfLit![2] : 0,
                                  r.selfLit?.count ?? 0 >= 4 ? r.selfLit![3] : 0)
            enc.setFragmentBytes(&sl, length: MemoryLayout<SIMD4<Float>>.stride, index: 3)
            var prm = SIMD4<Float>(r.uvScale ?? 1, r.normScale ?? 1, 0, 0)
            enc.setFragmentBytes(&prm, length: MemoryLayout<SIMD4<Float>>.stride, index: 4)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: r.count, indexType: .uint32,
                                      indexBuffer: ibuf, indexBufferOffset: r.start * 4)
        }
        enc.endEncoding()

        // 场景色拷到第二张目标
        if let blit = cb.makeBlitCommandEncoder() {
            blit.copy(from: sceneTex, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: w, height: h, depth: 1),
                      to: sceneTex2, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
        }

        // Pass 2：水面
        var wu = WaterUniforms(viewProj: vp, camPos: SIMD4<Float>(eye, 1),
                               sunDir: SIMD4<Float>(sunDir, 0),
                               sunColor: envColor("sunColor", SIMD3<Float>(1, 0.95, 0.85)),
                               skyColor: envColor("tintMidTop", SIMD3<Float>(0.1, 0.18, 0.3)),
                               simTerms: SIMD4<Float>(0, 0, 0, 0),
                               viewport: SIMD4<Float>(Float(w), Float(h), waterY, 0),
                               uvOffA: SIMD4<Float>(-floor(eye.x * 77 / 2048), -floor(eye.z * 77 / 2048), 0, 0),
                               uvOffB: SIMD4<Float>(-floor(eye.x * 296 / 512), -floor(eye.z * 296 / 512), 0, 0),
                               uvOffC: SIMD4<Float>(-floor(eye.x * 104 / 1024), -floor(eye.z * 104 / 1024), 0, 0))
        let wrp = MTLRenderPassDescriptor()
        wrp.colorAttachments[0].texture = sceneTex2
        wrp.colorAttachments[0].loadAction = .load
        wrp.colorAttachments[0].storeAction = .store
        wrp.depthAttachment.texture = depthTex
        wrp.depthAttachment.loadAction = .load
        wrp.depthAttachment.storeAction = .dontCare
        if let wenc = cb.makeRenderCommandEncoder(descriptor: wrp) {
            wenc.setRenderPipelineState(waterPipe)
            wenc.setDepthStencilState(waterDepthState)
            wenc.setVertexBuffer(waterVB, offset: 0, index: 0)
            wenc.setVertexBytes(&wu, length: MemoryLayout<WaterUniforms>.stride, index: 1)
            wenc.setFragmentBytes(&wu, length: MemoryLayout<WaterUniforms>.stride, index: 1)
            wenc.setFragmentTexture(sceneTex, index: 0)
            wenc.setFragmentTexture(tex("Ocean1_N") ?? fallbackTex, index: 1)
            wenc.setFragmentTexture(tex("Caustics") ?? fallbackTex, index: 2)
            wenc.setFragmentSamplerState(sampler, index: 0)
            wenc.setFragmentSamplerState(clampSampler, index: 1)
            wenc.drawIndexedPrimitives(type: .triangle, indexCount: 6, indexType: .uint32, indexBuffer: waterIB, indexBufferOffset: 0)
            wenc.endEncoding()
        }

        // Pass 3：FogVolume → Pass 4：FogUpsample
        if let fogPipe, let fogUpsamplePipe, let fogTex, let fogOut {
            let fp = MTLRenderPassDescriptor()
            fp.colorAttachments[0].texture = fogTex
            fp.colorAttachments[0].loadAction = .clear
            fp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            fp.colorAttachments[0].storeAction = .store
            fp.depthAttachment.texture = depthTex
            fp.depthAttachment.loadAction = .load
            fp.depthAttachment.storeAction = .dontCare
            if let fenc = cb.makeRenderCommandEncoder(descriptor: fp), let beamoVB, let beamoIB, let bm = man.beamos {
                struct FV { var params: SIMD4<Float> }
                var fv = FV(params: SIMD4<Float>(envNum("fogVolumeIntensity", 0), nearD, farD, 0))
                fenc.setRenderPipelineState(fogPipe)
                fenc.setDepthStencilState(depthState)
                fenc.setCullMode(.none)
                fenc.setVertexBuffer(beamoVB, offset: 0, index: 0)
                fenc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
                fenc.setFragmentBytes(&fv, length: MemoryLayout<FV>.stride, index: 1)
                for b in bm where b.start < b.count + b.start {
                    fenc.drawIndexedPrimitives(type: .triangle, indexCount: b.count, indexType: .uint32,
                                               indexBuffer: beamoIB, indexBufferOffset: b.start * 4)
                }
                fenc.endEncoding()
            }
            let up = MTLRenderPassDescriptor()
            up.colorAttachments[0].texture = fogOut
            up.colorAttachments[0].loadAction = .dontCare
            up.colorAttachments[0].storeAction = .store
            if let uenc = cb.makeRenderCommandEncoder(descriptor: up) {
                struct FU { var eyePos: SIMD4<Float>; var sunDir: SIMD4<Float>; var sunColor: SIMD4<Float>; var sunSize: SIMD4<Float>
                            var fogDH: SIMD4<Float>; var atmDen: SIMD4<Float>; var atmSample: SIMD4<Float>
                            var avgSkybox: SIMD4<Float>; var atmSun: SIMD4<Float>; var earth: SIMD4<Float>; var vp: SIMD4<Float>; var avgLum: SIMD4<Float> }
                var fu = FU(eyePos: SIMD4<Float>(eye, 1), sunDir: SIMD4<Float>(sunDir, 0),
                            sunColor: envColor("sunColor", SIMD3<Float>(1, 0.95, 0.85)),
                            sunSize: SIMD4<Float>(envNum("sunSize", 0), 0, envNum("sunSize", 0), 0),
                            fogDH: SIMD4<Float>(envNum("fogDensity", 1), envNum("fogHeight", 0.3), 0, 0),
                            atmDen: SIMD4<Float>(26.0, 0, 0, 0),
                            atmSample: SIMD4<Float>(1, 0, 0, 0),
                            avgSkybox: envColor("tintTop", SIMD3<Float>(0.02, 0.05, 0.1)),
                            atmSun: envColor("sunColor", SIMD3<Float>(1, 0.95, 0.85)),
                            earth: SIMD4<Float>(0, -50000, 0, 50000),
                            vp: SIMD4<Float>(Float(w), Float(h), 1, 0), avgLum: SIMD4<Float>(averageLum, 0, 0, 0))
                uenc.setRenderPipelineState(fogUpsamplePipe)
                uenc.setFragmentBytes(&fu, length: MemoryLayout<FU>.stride, index: 1)
                uenc.setFragmentTexture(sceneTex2, index: 0)
                uenc.setFragmentTexture(fogTex, index: 2)
                uenc.setFragmentTexture(fallbackTex, index: 3)
                uenc.setFragmentSamplerState(clampSampler, index: 0)
                uenc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                uenc.endEncoding()
            }
        }

        // Pass 5：Tonemap（原版 Tonemap0.frag：HDR 反解 + bloom + 曝光 + 暗角 + 输出曲线）
        if let tonemapPipe {
            let tp = MTLRenderPassDescriptor()
            tp.colorAttachments[0].texture = ldrTex
            tp.colorAttachments[0].loadAction = .dontCare
            tp.colorAttachments[0].storeAction = .store
            if let tenc = cb.makeRenderCommandEncoder(descriptor: tp) {
                struct TUni { var bloomTint: SIMD4<Float>; var bloomParams: SIMD4<Float>
                              var viewportSize: SIMD4<Float>; var exposure: SIMD4<Float> }
                var tu = TUni(bloomTint: envColor("bloomTint", SIMD3<Float>(1, 1, 1)),
                              bloomParams: SIMD4<Float>(envNum("bloomIntensity", 0), 0, 0, 0),
                              viewportSize: SIMD4<Float>(Float(w), Float(h), 1, 0),
                              exposure: SIMD4<Float>(envNum("exposure", 1), 0, 0, 0))
                tenc.setRenderPipelineState(tonemapPipe)
                tenc.setFragmentBytes(&tu, length: MemoryLayout<TUni>.stride, index: 1)
                tenc.setFragmentTexture((fogPipe != nil && fogOut != nil) ? fogOut! : sceneTex2, index: 0)
                tenc.setFragmentTexture(blackTex ?? fallbackTex, index: 1)
                tenc.setFragmentSamplerState(clampSampler, index: 0)
                tenc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                tenc.endEncoding()
            }
            // Pass 6：Fxaa0.frag
            if let fxaaPipe, let ldrTex {
                let xp = MTLRenderPassDescriptor()
                xp.colorAttachments[0].texture = drawable.texture
                xp.colorAttachments[0].loadAction = .dontCare
                xp.colorAttachments[0].storeAction = .store
                if let xenc = cb.makeRenderCommandEncoder(descriptor: xp) {
                    struct FX { var params: SIMD4<Float> }
                    var fx = FX(params: SIMD4<Float>(Float(w), Float(h), 0, 0))
                    xenc.setRenderPipelineState(fxaaPipe)
                    xenc.setFragmentBytes(&fx, length: MemoryLayout<FX>.stride, index: 1)
                    xenc.setFragmentTexture(ldrTex, index: 0)
                    xenc.setFragmentSamplerState(clampSampler, index: 0)
                    xenc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                    xenc.endEncoding()
                }
            }
        }
        cb.present(drawable)
        cb.commit()
        // 原版视线自适应：用上一帧 FogUpsample 输出的几何平均亮度做 u_averageLum
        if let fogOut {
            cb.waitUntilCompleted()
            let l = averageLuminance(of: fogOut)
            if l > 0, l.isFinite { averageLum = l }
        }
    }

    /// server.cjs: Te = 1/max(1e-4,px)-1；log(max(1e-4, 0.2126R+0.7152G+0.0722B))，取几何平均
    private func envColor4(_ key: String, _ def: SIMD4<Float>) -> SIMD4<Float> {
        guard let v = man?.env?[key], case let .arr(a) = v, a.count >= 3 else { return def }
        return SIMD4<Float>(a[0], a[1], a[2], a.count > 3 ? a[3] : 1)
    }

    private func averageLuminance(of tex: MTLTexture) -> Float {
        let rows = 8, cols = 128
        var sumLog: Float = 0; var n: Float = 0
        let bpr = cols * 8   // rgba16Float 每像素 8B
        var buf = [UInt8](repeating: 0, count: bpr)
        for r in 0..<rows {
            let y = min(tex.height - 1, r * max(1, tex.height / rows))
            buf.withUnsafeMutableBytes { raw in
                tex.getBytes(raw.baseAddress!, bytesPerRow: bpr,
                             from: MTLRegionMake2D(0, y, cols, 1), mipmapLevel: 0)
            }
            for c in 0..<cols {
                let p = c * 8
                let r0 = Float(Float16(bitPattern: UInt16(buf[p]) | (UInt16(buf[p+1]) << 8)))
                let g0 = Float(Float16(bitPattern: UInt16(buf[p+2]) | (UInt16(buf[p+3]) << 8)))
                let b0 = Float(Float16(bitPattern: UInt16(buf[p+4]) | (UInt16(buf[p+5]) << 8)))
                let rr = max(1e-4, 1.0 / max(1e-4, r0) - 1.0)
                let gg = max(1e-4, 1.0 / max(1e-4, g0) - 1.0)
                let bb = max(1e-4, 1.0 / max(1e-4, b0) - 1.0)
                sumLog += log(max(1e-4, 0.2126 * rr + 0.7152 * gg + 0.0722 * bb))
                n += 1
            }
        }
        return n > 0 ? exp(sumLog / n) : 1
    }

    private func perspective(_ fovy: Float, _ aspect: Float, _ near: Float, _ far: Float) -> simd_float4x4 {
        let y = 1 / tan(fovy / 2), x = y / aspect
        return simd_float4x4(columns: (SIMD4<Float>(x,0,0,0), SIMD4<Float>(0,y,0,0),
                                       SIMD4<Float>(0,0,far/(near-far),-1), SIMD4<Float>(0,0,(far*near)/(near-far),0)))
    }
    private func lookAt(_ e: SIMD3<Float>, _ c: SIMD3<Float>, _ u: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(e - c), x = simd_normalize(simd_cross(u, z)), y = simd_cross(z, x)
        return simd_float4x4(columns: (SIMD4<Float>(x.x, y.x, z.x, 0), SIMD4<Float>(x.y, y.y, z.y, 0),
                                       SIMD4<Float>(x.z, y.z, z.z, 0), SIMD4<Float>(-dot(x,e), -dot(y,e), -dot(z,e), 1)))
    }
}
