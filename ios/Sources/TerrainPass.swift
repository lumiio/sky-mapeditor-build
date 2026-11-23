import Foundation
import Metal
import MetalKit

// 地形通道：直载游戏包原版 iOS metallib（Grass / Sand / Cliff / CliffWet 四家族）。
// 顶点布局、PerObject 布局、贴图槽位全部取自各 metallib 的 IR 元数据（air.struct_type_info / air.location_index），不做自编。

struct TerrainRangeMeta: Codable {
    let start: Int
    let count: Int
    let material: Int
    let name: String
    let shader: String?   // 未支持材质在原版材质表里没有 shader 名，JSON 里是 null
}

struct TerrainMeta: Codable {
    let level: String?
    let stride: Int?
    let vertexCount: Int
    let indexCount: Int
    let ranges: [TerrainRangeMeta]
}

struct MaterialDef: Codable {
    let id: Int
    let shader: String
    let color: [Float]
    let metalness: Float
    let roughness: Float
    let uvScale: Float
    let minWeight: Int
    let stopWeight: Int
    let textures: [String: String]
}

/// 每个家族的 PerObjectUniforms 布局（来自各 vs metallib 的 air.struct_type_info）
private struct FamilySpec {
    let shader: String
    let vs: String
    let fs: String
    let objSize: Int
    let colorOffset: Int
    let uvScaleOffset: Int
    let metalnessOffset: Int   // -1 表示该结构没有 u_matMetalness
    let defaultRough: Float
    let hasFragRough: Bool
}

private let FAMILIES: [FamilySpec] = [
    FamilySpec(shader: "GrassShMesh", vs: "GrassShMesh-22h.ios.vs",
               fs: "GrassShMesh-22h.ios.fs", objSize: 112,
               colorOffset: 80, uvScaleOffset: 92, metalnessOffset: 96, defaultRough: 1.0, hasFragRough: true),
    FamilySpec(shader: "SandShMeshDecal", vs: "SandShMeshDecal-22h.ios.vs",
               fs: "SandShMeshDecal-22h.ios.fs", objSize: 160,
               colorOffset: 144, uvScaleOffset: 156, metalnessOffset: -1, defaultRough: 0.5, hasFragRough: true),
    FamilySpec(shader: "RockFaceShMeshDecal", vs: "RockFaceShMeshDecal-22h.ios.vs",
               fs: "RockFaceShMeshDecal-22h.ios.fs", objSize: 112,
               colorOffset: 80, uvScaleOffset: 92, metalnessOffset: 96, defaultRough: 1.0, hasFragRough: true),
    FamilySpec(shader: "RockFaceRainShMeshDecal", vs: "RockFaceRainShMeshDecal-22h.ios.vs",
               fs: "RockFaceRainShMeshDecal-22h.ios.fs", objSize: 112,
               colorOffset: 80, uvScaleOffset: 92, metalnessOffset: 96, defaultRough: 1.0, hasFragRough: true),
    // CloudSh：fs 只有 PerFrame(2)，没有 u_matRoughness
    FamilySpec(shader: "CloudSh", vs: "CloudShMesh-22h.ios.vs",
               fs: "CloudShMesh-22h.ios.fs", objSize: 112,
               colorOffset: 80, uvScaleOffset: 92, metalnessOffset: 96, defaultRough: 1.0, hasFragRough: false),
]

final class TerrainPass {
    private let device: MTLDevice
    private var vbuf: MTLBuffer?
    private var ibuf: MTLBuffer?
    private var meta: TerrainMeta?
    private var diagLogged = false
    private var groups: [String: [TerrainRangeMeta]] = [:]   // key = "<shader>/<material>"
    private var pipes: [String: MTLRenderPipelineState] = [:] // key = shader
    private var objBufs: [String: MTLBuffer] = [:]            // key = shader
    private var texSets: [String: [MTLTexture?]] = [:]        // key = "<shader>/<material>"
    private var roughs: [String: Float] = [:]                 // key 同上（fs 的 u_matRoughness）
    private var mats: [Int: MaterialDef] = [:]
    private var depth: MTLDepthStencilState?
    private var sampler: MTLSamplerState?

    private func famDefaultRough(_ shader: String) -> Float {
        FAMILIES.first { $0.shader == shader }?.defaultRough ?? 1
    }

    let level: String
    init?(device: MTLDevice, level: String) {
        self.device = device
        self.level = level
        guard let root = Bundle.main.url(forResource: "Assets", withExtension: nil) else { return nil }
        guard let data = try? Data(contentsOf: root.appendingPathComponent(level + ".terrain.bin")),
              data.count > 8 else { Boot.log("地形 bin 缺失"); return nil }
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
        if let md = try? Data(contentsOf: root.appendingPathComponent(level + ".terrain.meta.json")),
           let m = try? JSONDecoder().decode(TerrainMeta.self, from: md) {
            meta = m
            for r in m.ranges where r.shader != nil {
                groups["\(r.shader!)/\(r.material)", default: []].append(r)
            }
            Boot.log("terrain meta: \(m.vertexCount) 顶点 / \(m.ranges.count) 区间 / \(groups.count) 组")
        } else { Boot.log("terrain meta 解码失败"); return nil }
        if let md = try? Data(contentsOf: root.appendingPathComponent("CandleSpace.materials.json")),
           let list = try? JSONDecoder().decode([MaterialDef].self, from: md) {
            for m in list { mats[m.id] = m }
            Boot.log("原版材质表: \(list.count) 条")
        } else { Boot.log("材质表缺失") }

        let ds = MTLDepthStencilDescriptor()
        ds.depthCompareFunction = .lessEqual
        ds.isDepthWriteEnabled = true
        depth = device.makeDepthStencilState(descriptor: ds)

        let sd = MTLSamplerDescriptor()
        sd.sAddressMode = .repeat; sd.tAddressMode = .repeat
        sd.minFilter = .linear; sd.magFilter = .linear
        sd.mipFilter = .linear
        sampler = device.makeSamplerState(descriptor: sd)

        // 1×1 常量贴图 + 1×1 cube（u_probeCube 在原版声明为 texturecube<float>）
        func solid(_ v: UInt8) -> MTLTexture? {
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
            td.usage = .shaderRead
            guard let t = device.makeTexture(descriptor: td) else { return nil }
            var px: [UInt8] = [v, v, v, v]
            t.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &px, bytesPerRow: 4)
            return t
        }
        func solidCube(_ v: UInt8) -> MTLTexture? {
            let td = MTLTextureDescriptor()
            td.textureType = .typeCube
            td.pixelFormat = .rgba8Unorm
            td.width = 1; td.height = 1
            td.mipmapLevelCount = 1
            td.usage = .shaderRead
            guard let t = device.makeTexture(descriptor: td) else { return nil }
            var px: [UInt8] = [v, v, v, v]
            for f in 0..<6 {
                t.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, slice: f,
                          withBytes: &px, bytesPerRow: 4, bytesPerImage: 4)
            }
            return t
        }

        // 光簇图集（原版 fs 语义：uv=[[position]].xy*(32,16)，簇号=y*32+x；行0=表头，行1..count=光源条目）
        // 表头：(簇号, 512-簇号, count, 0)；PR 条目：(光世界位置 xyz, w=半径²)；CS 条目：(光颜色 xyz, w=0)
        // 片元第 1 段取 ratio = clamp(PR.w / d²) (CS.w=0 时该式成立)，第 2 段用 CS.x 作遮蔽系数
        func makeLightAtlas(_ lights: [(pos: SIMD3<Float>, radius: Float, color: SIMD3<Float>)]) -> (MTLTexture?, MTLTexture?)? {
            // 引擎 0x1009e8578 实参：宽 128、高 512、每像素 8 B（RGBA16F），5×128×512×8=0x80000
            // 行 0 = 表头，行 1..127 = 最多 127 条光源（shader 里 clamp 到 128 只是上界）
            let w = 128, h = 512
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
            td.usage = .shaderRead
            guard let pr = device.makeTexture(descriptor: td), let cs = device.makeTexture(descriptor: td) else { return nil }
            var prData = [Float16](repeating: 0, count: w * h * 4)
            var csData = [Float16](repeating: 0, count: w * h * 4)
            let n = min(lights.count, 127)
            func put(_ arr: inout [Float16], _ x: Int, _ y: Int, _ v: SIMD4<Float>) {
                let i = (y * 128 + x) * 4
                arr[i] = Float16(v.x); arr[i + 1] = Float16(v.y); arr[i + 2] = Float16(v.z); arr[i + 3] = Float16(v.w)
            }
            // 引擎写入值（0x1009e5754 段）：柔和度 soft 先 clamp 到 [0.07, 0.996]，再平方
            // 表头 (簇号, 512-簇号, 范围内条数, 该簇总条数)；PR.w = 半径²·soft²；CS = 颜色·强度，w = soft²
            let soft: Float = 0.996
            let soft2 = soft * soft
            for c in 0..<h {
                let hdr = SIMD4<Float>(Float(c), Float(512 - c), Float(n), Float(n))
                put(&prData, 0, c, hdr); put(&csData, 0, c, hdr)
                for i in 0..<n {
                    let l = lights[i]
                    put(&prData, i + 1, c, SIMD4<Float>(l.pos.x, l.pos.y, l.pos.z, l.radius * l.radius * soft2))
                    put(&csData, i + 1, c, SIMD4<Float>(l.color.x, l.color.y, l.color.z, soft2))
                }
            }
            prData.withUnsafeBytes { pr.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                                               withBytes: $0.baseAddress!, bytesPerRow: w * 8) }
            csData.withUnsafeBytes { cs.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                                               withBytes: $0.baseAddress!, bytesPerRow: w * 8) }
            return (pr, cs)
        }

        let loader = MTKTextureLoader(device: device)
        let imgRoot = root.appendingPathComponent("Data/Images/Bin")
        func loadTex(_ n: String) -> MTLTexture? {
            guard let t = try? loader.newTexture(URL: imgRoot.appendingPathComponent("\(n).png"), options: [.SRGB: false]) else {
                Boot.log("地形贴图缺失 \(n)"); return nil
            }
            return t
        }
        let white = solid(255), cube = solidCube(255)
        // 云体积：Data/Tex3D/CloudFluffy.vol = 64B 头（VOLU + 文件名）+ 64³ 单通道 8bit
        var cloudVol: MTLTexture?
        if let vd = try? Data(contentsOf: root.appendingPathComponent("Data/Tex3D/CloudFluffy.vol")),
           vd.count >= 64 + 64 * 64 * 64 {
            let td = MTLTextureDescriptor()
            td.textureType = .type3D
            td.pixelFormat = .r8Unorm
            td.width = 64; td.height = 64; td.depth = 64
            td.mipmapLevelCount = 1
            td.usage = .shaderRead
            if let t = device.makeTexture(descriptor: td) {
                vd.withUnsafeBytes { raw in
                    t.replace(region: MTLRegionMake3D(0, 0, 0, 64, 64, 64), mipmapLevel: 0, slice: 0,
                              withBytes: raw.baseAddress! + 64, bytesPerRow: 64, bytesPerImage: 4096)
                }
                cloudVol = t
                Boot.log("云体积 64³ 已载入")
            }
        } else { Boot.log("云体积缺失") }
        // 关卡里的 5 个 PointLight（TGCL 只序列化 transform，96 B 记录：id@0 / transform@16 / enabled@80）
        // 均匀缩放当作光照半径；颜色取 EnvNode AmbiencePointLight.color × intensity（u_pointLight 同源）
        // 引擎构造函数（0x1009e7f6c）把 256 条灯记录的颜色字段统一写成 __common 里的常量 vec4（无文件数据=0），
        // 关卡 TGCL 的 5 个 PointLight 又只有 transform 没有颜色/强度 → 官方默认这 5 盏灯不发光。
        let plColor = SIMD3<Float>(0, 0, 0)
        let levelLights: [(pos: SIMD3<Float>, radius: Float, color: SIMD3<Float>)] = [
            (SIMD3(-307.41, 43.14, 468.34), 20, plColor),
            (SIMD3(-386.05, 8.08, 431.77), 3, plColor),
            (SIMD3(2.4565, 6.2585, -2.8799), 1, plColor),
            (SIMD3(-314.18, 131.89, 587.20), 20, plColor),
            (SIMD3(10.7636, 4.6662, -37.465), 0.5, plColor),
        ]
        let lightAtlas = makeLightAtlas(levelLights)
        Boot.log("光簇图集 \(levelLights.count) 灯 / \(lightAtlas == nil ? "失败" : "已生成")")

        let grassMask = loadTex("GrassMask"), grassN0 = loadTex("GrassNorTex0"), grassN1 = loadTex("GrassNorTex1")
        let sandMask = loadTex("SandMask"), sandNoise = loadTex("SandNoiseGray04")
        let cliffSh = loadTex("CliffSh"), cliffWetSh = loadTex("CliffWetSh")
        let rockHeight = loadTex("RockHeightCliffSh"), soilSh = loadTex("SoilSh")

        // 顶点描述符：GEO0 36 B。属性语义由 vs IR 反推
        // loc0 a_position@0 / loc1 a_normal@12(SNORM) / loc2 a_light0@24 / loc3 a_light1@28 / loc4 a_light2@32 / loc5 a_color@20
        func vertexDescriptor() -> MTLVertexDescriptor {
            let vd = MTLVertexDescriptor()
            vd.attributes[0].format = .float3; vd.attributes[0].offset = 0; vd.attributes[0].bufferIndex = 1
            vd.attributes[1].format = .char4Normalized; vd.attributes[1].offset = 12; vd.attributes[1].bufferIndex = 1
            vd.attributes[2].format = .uchar4Normalized; vd.attributes[2].offset = 24; vd.attributes[2].bufferIndex = 1
            vd.attributes[3].format = .uchar4Normalized; vd.attributes[3].offset = 28; vd.attributes[3].bufferIndex = 1
            vd.attributes[4].format = .uchar4Normalized; vd.attributes[4].offset = 32; vd.attributes[4].bufferIndex = 1
            vd.attributes[5].format = .uchar4Normalized; vd.attributes[5].offset = 20; vd.attributes[5].bufferIndex = 1
            vd.layouts[1].stride = 36
            vd.layouts[1].stepFunction = .perVertex
            vd.layouts[1].stepRate = 1
            return vd
        }

        let sub = "Assets/Data/Shaders/Bin"
        for fam in FAMILIES {
            guard let vu = Bundle.main.url(forResource: fam.vs, withExtension: "metallib", subdirectory: sub),
                  let fu = Bundle.main.url(forResource: fam.fs, withExtension: "metallib", subdirectory: sub),
                  let vlib = try? device.makeLibrary(URL: vu), let flib = try? device.makeLibrary(URL: fu),
                  let vfn = vlib.makeFunction(name: "vsmain"), let ffn = flib.makeFunction(name: "fsmain") else {
                Boot.log("\(fam.shader) metallib 加载失败"); continue
            }
            let rpd = MTLRenderPipelineDescriptor()
            rpd.vertexFunction = vfn
            rpd.fragmentFunction = ffn
            rpd.vertexDescriptor = vertexDescriptor()
            rpd.colorAttachments[0].pixelFormat = .rgba16Float
            rpd.depthAttachmentPixelFormat = .depth32Float
            do {
                pipes[fam.shader] = try device.makeRenderPipelineState(descriptor: rpd)
                Boot.log("\(fam.shader) 管线就绪 (PerObject \(fam.objSize)B)")
            } catch { Boot.log("\(fam.shader) 管线失败: \(error.localizedDescription)"); continue }
        }

        // 槽位按各 fs 的 air.location_index（slotName → index）
        let slotMap: [String: [String: Int]] = [
            "GrassShMesh": ["u_lightPRTex": 3, "u_lightCSTex": 4, "u_grassMaskTex": 5,
                            "u_grassNorm1Tex": 6, "u_grassNorm2Tex": 7],
            "SandShMeshDecal": ["u_waterSim": 3, "u_lightPRTex": 4, "u_lightCSTex": 5,
                                "u_grassMaskTexture": 6, "u_normalTex": 7],
            "RockFaceShMeshDecal": ["u_probeCube": 3, "u_lightPRTex": 4, "u_lightCSTex": 5,
                                    "u_topGeoTexture": 6, "u_sideGeoTexture": 7],
            "RockFaceRainShMeshDecal": ["u_probeCube": 3, "u_lightPRTex": 4, "u_lightCSTex": 5,
                                        "u_topGeoTexture": 6, "u_sideGeoTexture": 7],
            "CloudSh": ["u_waterSim": 0, "u_cloudNoise3D": 3],
        ]
        var texCache: [String: MTLTexture?] = [:]
        func tex(_ name: String, _ isCube: Bool = false) -> MTLTexture? {
            if let c = texCache[name] { return c }
            let t = isCube ? nil : loadTex(name)
            texCache[name] = t
            return t
        }

        for (key, ranges) in groups {
            let shader = String(key.split(separator: "/").first ?? "")
            let matId = Int(key.split(separator: "/").last ?? "") ?? 0
            guard let fam = FAMILIES.first(where: { $0.shader == shader }) else { continue }
            let def = mats[matId]

            // PerObject：u_model 单位矩阵（关卡顶点本来就是世界坐标，原版整关是一个 draw 批次、model=identity）；
            // 颜色/uvScale/metalness 取原版材质表；缺失则白/1/0
            var obj = [UInt8](repeating: 0, count: fam.objSize)
            obj.withUnsafeMutableBytes { raw in
                let f = raw.bindMemory(to: Float.self)
                // 矩阵按列主序存：col0=(1,0,0,0) col1=(0,1,0,0) col2=(0,0,1,0) col3=(0,0,0,1)
                f[0] = 1; f[5] = 1; f[10] = 1; f[15] = 1
                let o = fam.colorOffset / 4
                let c = def?.color ?? [1, 1, 1]
                f[o] = c.count > 0 ? c[0] : 1
                f[o + 1] = c.count > 1 ? c[1] : 1
                f[o + 2] = c.count > 2 ? c[2] : 1
                f[fam.uvScaleOffset / 4] = def?.uvScale ?? 1
                if fam.metalnessOffset >= 0 { f[fam.metalnessOffset / 4] = def?.metalness ?? 0 }
            }
            objBufs[key] = obj.withUnsafeBytes {
                device.makeBuffer(bytes: $0.baseAddress!, length: fam.objSize, options: .storageModeShared)
            }
            roughs[key] = def?.roughness ?? fam.defaultRough

            // 贴图：默认 PR/CS/waterSim 用 1×1 白，probeCube 用 1×1 cube；其余按材质表的 texture 名取包内原图
            var slots: [MTLTexture?] = [nil, nil, nil, nil, nil, nil, nil, nil]
            let map = slotMap[shader] ?? [:]
            for (slotName, slotIdx) in map {
                if slotName == "u_cloudNoise3D" {
                    slots[slotIdx] = cloudVol
                } else if slotName == "u_lightPRTex" {
                    slots[slotIdx] = lightAtlas?.0 ?? white
                } else if slotName == "u_lightCSTex" {
                    slots[slotIdx] = lightAtlas?.1 ?? white
                } else if slotName == "u_waterSim" {
                    slots[slotIdx] = white
                } else if slotName == "u_probeCube" {
                    slots[slotIdx] = cube
                } else if let file = def?.textures[slotName] {
                    slots[slotIdx] = tex(file)
                } else {
                    slots[slotIdx] = white
                    Boot.log("材质 \(matId) 缺 \(slotName)")
                }
            }
            texSets[key] = slots
        }
        Boot.log("地形组资源就绪 \(texSets.count) 组 / 管线 \(pipes.count)")
    }

    func encode(_ enc: MTLRenderCommandEncoder, perFrame: inout PerFrameUniforms, perPass: SIMD4<Float>) {
        guard let vbuf, let ibuf, let depth, let sampler, !groups.isEmpty else { return }
        if !diagLogged, let meta {
            diagLogged = true
            // 真机自检：用本帧真正下发的 u_viewProj 把前 2000 个顶点投一遍，
            // 在屏率为 0 就说明矩阵/顶点布局错位（而不是"画了但被雾压黑"）。
            let cols = perFrame.u_viewProj
            let vpM = simd_float4x4(columns: (SIMD4<Float>(cols.0, cols.1, cols.2, cols.3),
                                             SIMD4<Float>(cols.4, cols.5, cols.6, cols.7),
                                             SIMD4<Float>(cols.8, cols.9, cols.10, cols.11),
                                             SIMD4<Float>(cols.12, cols.13, cols.14, cols.15)))
            let p = vbuf.contents().bindMemory(to: Float.self, capacity: meta.vertexCount * 9)
            var inView = 0, n = 0
            var zLo: Float = 9, zHi: Float = -9
            for i in 0..<min(meta.vertexCount, 2000) {
                let base = i * 9
                let c = vpM * SIMD4<Float>(p[base], p[base + 1], p[base + 2], 1)
                n += 1
                guard c.w > 0 else { continue }
                let x = c.x / c.w, y = c.y / c.w, z = c.z / c.w
                if abs(x) <= 1, abs(y) <= 1, z >= 0, z <= 1 { inView += 1 }
                zLo = min(zLo, z); zHi = max(zHi, z)
            }
            let draws = groups.values.reduce(0) { $0 + $1.count }
            let tris = groups.values.reduce(0) { $0 + $1.reduce(0) { $0 + $1.count } } / 3
            Boot.log("地形自检 顶点=\(meta.vertexCount) 索引=\(meta.indexCount) 组=\(groups.count) 管线=\(pipes.count) draw=\(draws) tri=\(tris) 采样=\(n) 在屏=\(inView) ndcz=[\(String(format: "%.3f", zLo)),\(String(format: "%.3f", zHi))]")
        }
        enc.setDepthStencilState(depth)
        enc.setVertexBuffer(vbuf, offset: 0, index: 1)
        enc.setVertexBytes(&perFrame, length: MemoryLayout<PerFrameUniforms>.stride, index: 2)
        var pp = perPass
        enc.setFragmentBytes(&pp, length: 16, index: 1)
        enc.setFragmentBytes(&perFrame, length: MemoryLayout<PerFrameUniforms>.stride, index: 2)
        for i in 0..<8 { enc.setFragmentSamplerState(sampler, index: i) }

        for (key, ranges) in groups {
            let shader = String(key.split(separator: "/").first ?? "")
            guard let pipe = pipes[shader], let objBuf = objBufs[key] else { continue }
            enc.setRenderPipelineState(pipe)
            enc.setVertexBuffer(objBuf, offset: 0, index: 0)
            if FAMILIES.first(where: { $0.shader == shader })?.hasFragRough ?? true {
                var roughVal = roughs[key] ?? famDefaultRough(shader)
                enc.setFragmentBytes(&roughVal, length: 4, index: 0)
            }
            if let set = texSets[key] {
                for (i, t) in set.enumerated() where t != nil { enc.setFragmentTexture(t, index: i) }
            }
            for range in ranges {
                enc.drawIndexedPrimitives(type: .triangle, indexCount: range.count, indexType: .uint32,
                                          indexBuffer: ibuf, indexBufferOffset: range.start * 4)
            }
        }
    }
}
