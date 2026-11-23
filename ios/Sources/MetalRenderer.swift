import Foundation
import Metal
import MetalKit
import UIKit
import simd


struct PerObjectUniforms {
  var u_skyColor: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_horizonColor: (Float, Float, Float) = (0, 0, 0)
  var u_horizonFalloff: Float = 0
  var u_skyBrightness: Float = 0
  var u_useEnvSun: Float = 0
  var u_sunAngles: (Float, Float) = (0, 0)
  var u_sunSize: Float = 0
  var u_sunInt: Float = 0
  var m8_pad: Float = 0
  var _g57: Float = 0
  var u_sunTint: (Float, Float, Float) = (0, 0, 0)
  var u_sunGlow: Float = 0
  var u_highCloudSpeed: (Float, Float) = (0, 0)
  var u_highCloudHeight: Float = 0
  var u_highCloudSize: Float = 0
  var u_highCloudDensity: Float = 0
  var u_highCloudOpacity: Float = 0
  var u_lowCloudSpeed: (Float, Float) = (0, 0)
  var u_lowCloudHeight: Float = 0
  var u_lowCloudSize: Float = 0
  var u_lowCloudDensity: Float = 0
  var u_lowCloudOpacity: Float = 0
  var u_cloudColor: (Float, Float, Float) = (0, 0, 0)
  var u_cloudAbsorption: Float = 0
  var u_cloudPatchiness: Float = 0
  var u_skyFadeOut: Float = 0
  var _t: (Float, Float) = (0, 0)
};

struct PerPassUniforms {
  var u_viewportSize: (Float, Float, Float, Float) = (0, 0, 0, 0)
};

struct PerFrameUniforms {
  var u_texSizeFull: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_texSizeHalf: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_postParams1: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_postParams2: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_lensDistortion: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_lensDistortion2: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_view: (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  var u_proj: (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  var u_viewProj: (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  var u_viewProjInv: (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  var u_viewProjOld: (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  var u_viewProjCull: (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  var u_camMat: (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  var u_camNearPlane: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_lightShadowConsts: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_aaCornerUvs0: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_aaCornerUvs1: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_eyePos: (Float, Float, Float) = (0, 0, 0)
  var u_unitHeightFrac: Float = 0
  var u_dt: Float = 0
  var u_time: Float = 0
  var u_levelTime: Float = 0
  var u_averagedt: Float = 0
  var u_averageLum: Float = 0
  var u_zNear: Float = 0
  var u_zFar: Float = 0
  var u_cameraCut: Float = 0
  var u_oceanOffsetHeight: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_grassSpecularTint: (Float, Float, Float) = (0, 0, 0)
  var u_underwater: Float = 0
  var u_windVec: (Float, Float, Float) = (0, 0, 0)
  var u_hudToSceneRatio: Float = 0
  var u_jitterFullHalf: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_jitterFullHalfOld: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_projPlaneU: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_projPlaneUOld: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_projPlaneV: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_projPlaneVOld: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_projPlaneOrigin: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_projPlaneOriginOld: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_cheapFog: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_cheapFog2: (Float, Float) = (0, 0)
  var u_sunAccess: (Float, Float) = (0, 0)
  var u_probeExposure: Float = 0
  var m44_pad: Float = 0
  var _g869: (Float, Float) = (0, 0)
  var u_sunDir: (Float, Float, Float) = (0, 0, 0)
  var u_oceanBlendPow: Float = 0
  var u_sunSizeIntMoonPhase: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_sunColor: (Float, Float, Float) = (0, 0, 0)
  var u_atmosphereDensity: Float = 0
  var u_fogDensityHeightDist: (Float, Float, Float) = (0, 0, 0)
  var u_averageSkyOcclusion: Float = 0
  var u_averageSkyColor: (Float, Float, Float) = (0, 0, 0)
  var u_atmosphereSample: Float = 0
  var u_averageSkyboxColor: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_atmosphereSunColor: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_averageProbeColor: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_earthPosRad: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_cinemaBrightness: Float = 0
  var u_galleryChromaTest: Float = 0
  var u_displayShoulderCutoff: Float = 0
  var _g1036: Float = 0
  var u_beaconPosEnable: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_beaconColor: (Float, Float, Float) = (0, 0, 0)
  var u_disableMeshMotion: Float = 0
  var u_portalConst: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_waterSimTerms: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_waterSimTerms2: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_waterSimTerms3: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_windScroll0: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_windScroll1: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_windScroll2: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_pointLight: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_probeShR0: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_probeShR1: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_probeShG0: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_probeShG1: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_probeShB0: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_probeShB1: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_probeShRGB2: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_probeCenter: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_cloudWindMoveNoise: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_cloudWindScrollSpace: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_cloudMat: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_cloudVoxelScales: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_localAvatarPos: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_localAvatarDir: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_localAvatarVel: (Float, Float, Float) = (0, 0, 0)
  var u_cloudPackedBinDimInv: Float = 0
  var u_randomOffset: (Float, Float, Float) = (0, 0, 0)
  var u_cloudUndulationScale: Float = 0
  var u_cloudBinMinWorld: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_cloudBinRangeWorld: (Float, Float, Float) = (0, 0, 0)
  var u_cloudGeoScrollSpeed: Float = 0
  var u_rainMovement: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_minLevelBounds: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_maxLevelBounds: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_levelBounds: (Float, Float, Float) = (0, 0, 0)
  var u_reflectionPlaneHeight2: Float = 0
  var u_debugTweaks: (Float, Float, Float, Float) = (0, 0, 0, 0)
  var u_debugToggles: (Float, Float, Float, Float) = (0, 0, 0, 0)
};


func t3(_ v: SIMD3<Float>) -> (Float, Float, Float) { (v.x, v.y, v.z) }
func t3(_ v: SIMD4<Float>) -> (Float, Float, Float) { (v.x, v.y, v.z) }
/// float3（16 字节，尾部含一列填充）
func t3p(_ v: SIMD3<Float>) -> (Float, Float, Float, Float) { (v.x, v.y, v.z, 0) }
func t3p(_ v: SIMD4<Float>) -> (Float, Float, Float, Float) { (v.x, v.y, v.z, 0) }

func mat4(_ m: simd_float4x4) -> (Float, Float, Float, Float, Float, Float, Float, Float,
                                 Float, Float, Float, Float, Float, Float, Float, Float) {
    (m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.0.w,
     m.columns.1.x, m.columns.1.y, m.columns.1.z, m.columns.1.w,
     m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.2.w,
     m.columns.3.x, m.columns.3.y, m.columns.3.z, m.columns.3.w)
}

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
    private var dome: DomePass?
    private var domeAuxTex: MTLTexture?   // 原版穹顶 fs 的第二路输出（o_fragColor1）
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
    private var terrain: TerrainPass?
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

    /// true = 站在关卡里平视（默认）；false = 旧的整体绕轨道俯瞰
    var firstPerson = true
    var az: Float = 2.10
    var el: Float = 0.28
    var zoom: Float = 1.0
    /// 观察用曝光增益（编辑器 UI 滑杆），乘在 tonemap 的 exposure 上；默认 1
    /// 双指平移：在关卡平面上的取景中心偏移
    var targetShift = SIMD2<Float>(0, 0)

    var exposureGain: Float = 1.0 {
        didSet {
            Boot.log("曝光增益 gain=\(exposureGain) 基准=\(exposureBase) 有效=\(exposureBase * exposureGain) 平均亮度=\(averageLum)")
        }
    }
    /// 关卡 env 里的 exposure（draw 时从 man.env 读，供滑杆日志用）
    private var exposureBase: Float = 1.0
    var center = SIMD3<Float>(0, 0, 0)
    var radius: Float = 10
    var waterY: Float = -5
    var averageLum: Float = 1

    /// 原版 u_averageSkyColor：由引擎对天空盒做均值得到，这里用「把穹顶渲进 32×32 再读回求均值」复现
    var averageSky = SIMD3<Float>(0.05, 0.09, 0.16)
    /// 云族（CloudSh）在 GEO0 里是带 alpha 的体积片，原版走混合；我们现在没有混合配置，硬画会变成大块黑斑。
    /// 默认隐藏，界面「云」按钮可以打开做对照。
    var hideCloud = true    // 云块需要引擎的 cloudPackedBin 才能正确着色，没算出来之前默认不开
    /// 给界面用的关卡统计
    private(set) var stats = ""

    private let debugSkipWater = true
    /// 穹顶开关：DomePass 用原版 SkyDomeFade metallib + 原版 UnitSphere.mesh（半径 1.0）；
    /// 管线或网格任一缺失时 DomePass 自身返回 nil，这里再兜一层，绝不发非法 draw（非法 draw 会让整个 command buffer 作废）
    var debugSkipSkyDome = false
    /// 诊断开关：真机雾管线输出恒为「1.0」(=亮度 0)，会把整帧乘黑；先让 tonemap 直读场景色，
    /// 用亮度图确认场景本身有没有内容，再回来修雾。仅诊断期打开，日志会写明。
    var debugSkipFogPost = false
    private var frameIdx = 0

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
        terrain = TerrainPass(device: device, level: level)
        terrain?.hideCloud = hideCloud
        stats = terrain?.summary ?? "" 

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
        // sceneTex 是 rgba16Float（HDR 场景缓冲）；管线声明 bgra8Unorm 会与附件格式不符，整条 pass 的 draw 都被校验拦掉
        rpd.colorAttachments[0].pixelFormat = .rgba16Float
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
        wrpd.colorAttachments[0].pixelFormat = .rgba16Float   // 水面写进 sceneTex2（rgba16Float），格式必须一致

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
        if let root = assetsURL() {
            dome = DomePass(device: dev, assets: root)
            Boot.log("穹顶通道 \(dome != nil ? "可用" : "不可用")")
        } else {
            Boot.log("穹顶: Assets 目录缺失")
        }
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

        // 纯地形关卡（ranges 为空）不需要 .verts/.idx，只有 GEO0 的 .terrain.bin
        if !m.ranges.isEmpty {
            guard let vb = try? Data(contentsOf: root.appendingPathComponent("\(level).verts")),
                  let ib = try? Data(contentsOf: root.appendingPathComponent("\(level).idx")), !vb.isEmpty, !ib.isEmpty else {
                lastError = "顶点/索引数据缺失 \(level)"; return
            }
            vbuf = vb.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress ?? UnsafeRawPointer(bitPattern: 1)!, length: $0.count, options: .storageModeShared) }
            ibuf = ib.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress ?? UnsafeRawPointer(bitPattern: 1)!, length: $0.count, options: .storageModeShared) }
            guard vbuf != nil, ibuf != nil else { lastError = "顶点/索引 buffer 创建失败"; return }
        }

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
        d.storageMode = .shared
        sceneTex = device.makeTexture(descriptor: d)
        sceneTex2 = device.makeTexture(descriptor: d)
        let fd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        fd.usage = [.renderTarget, .shaderRead]
        fd.storageMode = .shared
        fogTex = device.makeTexture(descriptor: fd)
        fogOut = device.makeTexture(descriptor: fd)
        let ld = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        ld.usage = [.renderTarget, .shaderRead]
        ld.storageMode = .shared
        ldrTex = device.makeTexture(descriptor: ld)
        let ad = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        ad.usage = .renderTarget
        domeAuxTex = device.makeTexture(descriptor: ad)
        let dd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: w, height: h, mipmapped: false)
        dd.usage = [.renderTarget, .shaderRead]
        depthTex = device.makeTexture(descriptor: dd)
    }

    /// 切关前调用：往同一个命令队列塞一个空命令缓冲并等它完成。
    /// Metal 命令是队列内按提交顺序执行的，这个空缓冲完成即代表之前所有帧都跑完了，
    /// 这时再释放 texture/buffer 才是安全的（否则驱动会直接把进程打死，还没有崩溃日志）。
    func retire() {
        let cb = queue.makeCommandBuffer()
        cb?.commit()
        cb?.waitUntilCompleted()
    }

    func draw(in view: MTKView) {
        var miss: [String] = []
        if man == nil { miss.append("man") }
        // GEO0 纯地形关卡没有 .verts/.idx（原版关卡只有 .terrain.bin），不算缺资源
        if !(man?.ranges.isEmpty ?? true), vbuf == nil { miss.append("vbuf") }
        if !(man?.ranges.isEmpty ?? true), ibuf == nil { miss.append("ibuf") }
        if view.currentDrawable == nil { miss.append("drawable") }
        if meshPipe == nil { miss.append("meshPipe") }
        if depthState == nil { miss.append("depthState") }
        if sampler == nil { miss.append("sampler") }
        if clampSampler == nil { miss.append("clampSampler") }
        if fallbackTex == nil { miss.append("fallbackTex") }
        if !miss.isEmpty {
            if frameIdx == 0 { Boot.log("draw 缺资源: \(miss.joined(separator: ","))  drawableSize=\(Int(view.drawableSize.width))×\(Int(view.drawableSize.height)) paused=\(view.isPaused)") }
            return
        }
        guard let man, let drawable = view.currentDrawable,
              let meshPipe, let depthState,
              let sampler, let clampSampler, let fallbackTex else { return }
        lastError = nil
        let w = view.drawableSize.width > 0 ? Int(view.drawableSize.width) : 1
        let h = view.drawableSize.height > 0 ? Int(view.drawableSize.height) : 1
        ensureTargets(w, h)
        guard let sceneTex, let sceneTex2, let depthTex else { return }

        // 摄像机：默认「第一人称 / 地面视角」——站在关卡的可玩区域里平视，
        // 和游戏里进去看到的一样；俯瞰模式保留旧的绕轨道相机（做成俯视沙盘）。
        // 之前默认就是绕轨道 + dist≈15 m：对烛窟这种洞窟，相机在洞顶外面往洞里看，
        // 结果就是「草地一片绿、洞顶背面一整块黑」——不是材质错，是机位在模型外面。
        let centerShifted = center + SIMD3<Float>(targetShift.x, 0, targetShift.y)
        let eye: SIMD3<Float>
        let lookAtPoint: SIMD3<Float>
        let camUp = SIMD3<Float>(0, 1, 0)
        let fovDeg: Float
        let nearD: Float, farD: Float
        if firstPerson {
            let b = man.bounds.count >= 6 ? man.bounds : [center.x, center.y, center.z, center.x, center.y, center.z]
            let minY = min(b.count >= 6 ? b[1] : center.y, center.y)
            let sea = man.seaLevel
            // 站高 1.7 m：优先用关卡海平面（烛窟 -5），没有就用包围盒底面
            let eyeY = (sea != nil ? sea! + 1.7 : minY + 1.7)
            eye = SIMD3<Float>(center.x + targetShift.x, max(eyeY, minY + 0.4), center.z + targetShift.y)
            let dir = SIMD3<Float>(cos(el) * cos(az), sin(el), cos(el) * sin(az))
            lookAtPoint = eye + dir
            nearD = 0.08
            farD = 1200
            fovDeg = min(100, max(25, 55 * zoom))
        } else {
            let dist = radius * 1.15 * zoom
            eye = centerShifted + SIMD3<Float>(cos(el)*cos(az), sin(el), cos(el)*sin(az)) * dist
            lookAtPoint = centerShifted
            nearD = max(dist * 0.01, 0.05)
            farD = dist * 20
            fovDeg = 50
        }
        let proj = perspective(fovDeg * Float.pi / 180, Float(w) / Float(h), nearD, farD)
        let viewM = lookAt(eye, lookAtPoint, camUp)
        let vp = proj * viewM
        updateClusters(vp, w, h)

        func envColor(_ k: String, _ def: SIMD3<Float>) -> SIMD4<Float> {
            guard let a = man.env?[k]?.array, a.count >= 3 else { return SIMD4<Float>(def, 1) }
            return SIMD4<Float>(a[0], a[1], a[2], 1)
        }
        func envNum(_ k: String, _ def: Float) -> Float { man.env?[k]?.first ?? def }

        exposureBase = envNum("exposure", 1)
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

        if frameIdx == 0 {
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 4, height: 4, mipmapped: false)
            td.usage = .renderTarget
            td.storageMode = .shared
            if let t = device.makeTexture(descriptor: td), let tcb = queue.makeCommandBuffer() {
                let p = MTLRenderPassDescriptor()
                p.colorAttachments[0].texture = t
                p.colorAttachments[0].loadAction = .clear
                p.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 0.25, blue: 0.5, alpha: 1)
                p.colorAttachments[0].storeAction = .store
                if let e = tcb.makeRenderCommandEncoder(descriptor: p) { e.endEncoding() }
                tcb.commit()
                tcb.waitUntilCompleted()
                Boot.log("自检 清屏读回=\(probeHalf(t, 0.25, 0.25)) cb=\(tcb.status.rawValue) err=\(String(describing: tcb.error))")
            }
        }

        guard let cb = queue.makeCommandBuffer() else { return }

        if frameIdx == 0 { Boot.log("路径 terrain=\(terrain != nil) dome=\(dome != nil) skipDome=\(debugSkipSkyDome) ranges=\(man.ranges.count)") }
        // Pass 1：场景
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = sceneTex
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0.03, green: 0.05, blue: 0.09, alpha: 1)
        rp.colorAttachments[0].storeAction = .store
        // 原版 SkyDomeFade fs 输出 o_fragColor0/o_fragColor1 两路，管线必须有第 2 个颜色附件
        rp.colorAttachments[1].texture = domeAuxTex
        rp.colorAttachments[1].loadAction = .dontCare
        rp.colorAttachments[1].storeAction = .dontCare
        rp.depthAttachment.texture = depthTex
        rp.depthAttachment.loadAction = .clear
        rp.depthAttachment.storeAction = .store
        rp.depthAttachment.clearDepth = 1

        guard let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        enc.setRenderPipelineState(meshPipe)
        enc.setDepthStencilState(depthState)
        if let vbuf { enc.setVertexBuffer(vbuf, offset: 0, index: 0) }
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
        // 原版 PerFrame：地形/穹顶/簇光共用同一块 1584 B
        averageSky = SIMD3<Float>(avgSkyC.x, avgSkyC.y, avgSkyC.z)   // EnvNode 原版 tintMidMid（原版均值由引擎天空盒积分给出）
        var skyF = PerFrameUniforms()
        skyF.u_eyePos = t3(eye)
        skyF.u_time = Float(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 10000))
        skyF.u_sunDir = t3(sunDir)
        // 原版 server.cjs Ambience 的 uniforms 映射（照抄，不自拟）：
        //   u_sunSizeIntMoonPhase = [sunSize, sunInt, sunToMoon, moonPhase]
        //   u_fogDensityHeightDist = [fogDensity, fogHeight, drawDistance]
        skyF.u_sunSizeIntMoonPhase = (envNum("sunSize", 0), envNum("sunInt", 1),
                                      envNum("sunToMoon", 0), envNum("moonPhase", 0.5))
        skyF.u_fogDensityHeightDist = (envNum("fogDensity", 1), envNum("fogHeight", 0.1), envNum("drawDistance", 15000))
        skyF.u_atmosphereDensity = envNum("atmosphereDensity", 1)
        skyF.u_probeExposure = envNum("exposure", 1)
        skyF.u_sunColor = t3(envColor("sunColor", SIMD3<Float>(0.0433, 0.0335, 0.0293)))
        skyF.u_atmosphereSunColor = (skyF.u_sunColor.0, skyF.u_sunColor.1, skyF.u_sunColor.2, 1)
        skyF.u_averageSkyColor = (averageSky.x, averageSky.y, averageSky.z)
        skyF.u_averageSkyOcclusion = 1
        skyF.u_averageSkyboxColor = (averageSky.x, averageSky.y, averageSky.z, 1)
        skyF.u_averageProbeColor = (averageSky.x, averageSky.y, averageSky.z, 1)

        // 原版 SkyDomeFade 穹顶（vsmain/fsmain 直接来自游戏包 metallib，几何用原版 UnitSphere.mesh）
        var sky = PerObjectUniforms()
        var skyP = PerPassUniforms()
        skyP.u_viewportSize = (Float(w), Float(h), 1 / Float(w), 1 / Float(h))
        skyF.u_view = mat4(viewM)
        skyF.u_proj = mat4(proj)
        skyF.u_viewProj = mat4(vp)
        skyF.u_viewProjInv = mat4(simd_inverse(vp))
        // EnvNode 的 26 个字段（TGCL 原值），缺字段时保留引擎构造默认
        let tintTopV = envColor("tintTop", SIMD3<Float>(0, 0.0009, 0.017))
        sky.u_skyColor = (tintTopV.x, tintTopV.y, tintTopV.z, 1)
        let tintBotV = envColor("tintBot", SIMD3<Float>(0.1726, 0.0005, 0))
        sky.u_horizonColor = (tintBotV.x, tintBotV.y, tintBotV.z)
        sky.u_horizonFalloff = envNum("horizonFalloff", 0)
        sky.u_skyBrightness = envNum("skyBrightness", 1)
        sky.u_useEnvSun = 1
        sky.u_sunAngles = (envNum("sunAngleXZ", 180), envNum("sunAngleY", 40))
        sky.u_sunSize = envNum("sunSize", 0)
        sky.u_sunInt = envNum("sunInt", 1)
        let sunTintV = envColor("sunColor", SIMD3<Float>(0.0433, 0.0335, 0.0293))
        sky.u_sunTint = (sunTintV.x, sunTintV.y, sunTintV.z)
        sky.u_sunGlow = envNum("sunGlow", 0)
        sky.u_highCloudSpeed = (envNum("highCloudSpeedX", 0), envNum("highCloudSpeedY", 0))
        sky.u_highCloudHeight = envNum("highCloudHeight", 0)
        sky.u_highCloudSize = envNum("highCloudSize", 0)
        sky.u_highCloudDensity = envNum("highCloudDensity", 0)
        sky.u_highCloudOpacity = envNum("highCloudOpacity", 0)
        sky.u_lowCloudSpeed = (envNum("lowCloudSpeedX", 0), envNum("lowCloudSpeedY", 0))
        sky.u_lowCloudHeight = envNum("lowCloudHeight", 0)
        sky.u_lowCloudSize = envNum("lowCloudSize", 0)
        sky.u_lowCloudDensity = envNum("lowCloudDensity", 0)
        sky.u_lowCloudOpacity = envNum("lowCloudOpacity", 0)
        let cloudColV = envColor("cloudColor", SIMD3<Float>(0.14, 0.15, 0.17))
        sky.u_cloudColor = (cloudColV.x, cloudColV.y, cloudColV.z)
        sky.u_cloudAbsorption = envNum("cloudAbsorption", 0)
        sky.u_cloudPatchiness = envNum("cloudPatchiness", 0)
        // fs 末段 alpha = 1 - u_skyFadeOut，且颜色按同一权重与雾色混合：1 会把整块穹顶压成全黑（上一轮真机整屏黑即此）
        // 洞穴关（烛窟/罐洞）原版会把天空淡出成雾色，EnvNode 里有 skyFadeOut 就直接用
        sky.u_skyFadeOut = envNum("skyFadeOut", 0)
        if let dome, !debugSkipSkyDome {
            dome.setProbeColor(SIMD3<Float>(averageSky.x, averageSky.y, averageSky.z))
            dome.encode(enc, eye: eye, radiusScale: farD * 0.9,
                        perObject: &sky, perFrame: &skyF, perPass: &skyP)
            enc.setRenderPipelineState(meshPipe)     // 恢复主 mesh 管线给地形用
            enc.setDepthStencilState(depthState)     // 穹顶用的是 always/no-write，这里恢复主 pass 的 depth 状态
        }

        // 原版地形片元读取的 PerFrame 字段：u_camMat@480 / u_lightShadowConsts@560 / u_eyePos@608 / u_sunDir@880 / u_sunColor@912 / u_pointLight@1184
        if frameIdx == 0 {
            Boot.log("结构体尺寸 PerFrame=\(MemoryLayout<PerFrameUniforms>.stride) PerObject=\(MemoryLayout<PerObjectUniforms>.stride) DomeObj=\(MemoryLayout<DomeObjectUniforms>.stride) PerPass=\(MemoryLayout<PerPassUniforms>.stride)")
            Boot.log("PerFrame 偏移 camMat=\(MemoryLayout<PerFrameUniforms>.offset(of: \.u_camMat) ?? -1) eyePos=\(MemoryLayout<PerFrameUniforms>.offset(of: \.u_eyePos) ?? -1) sunDir=\(MemoryLayout<PerFrameUniforms>.offset(of: \.u_sunDir) ?? -1) sunColor=\(MemoryLayout<PerFrameUniforms>.offset(of: \.u_sunColor) ?? -1) pointLight=\(MemoryLayout<PerFrameUniforms>.offset(of: \.u_pointLight) ?? -1) size=\(MemoryLayout<PerFrameUniforms>.stride)")
        }
        if let terrain {
            var pf = skyF
            // 地形 vs 用的 PerFrame 字段（按 GrassShMesh/SandShMeshDecal/RockFaceSh/RockFaceRainSh/CloudSh 的 vs IR 核对）：
            // i32 8 = 第 3 个矩阵 @224 = u_viewProj；i32 97 @1492 = 单个 float。之前只填了 u_camMat，u_viewProj 是 0 → 顶点全被剪掉
            pf.u_view = mat4(viewM)
            pf.u_proj = mat4(proj)
            pf.u_viewProj = mat4(vp)
            pf.u_camMat = mat4(viewM)
            pf.u_lightShadowConsts = (0.01, 0.01, 0.01, 0.01) // 引擎构造函数里直接存 0x3c23d70a=0.01 到 4 个分量
            pf.u_pointLight = (plC.x * plK, plC.y * plK, plC.z * plK, 0)
            // 原版 bc()：SH 是 9 系数 × RGB（coef0 为常数项），常数天空 Radiance L 只有 coef0 非零：
            // u_probeShR0 = [t0,t3,0→t9...]，t0 = L.r * 0.2820948（Y00），u_averageProbeColor = t0 * 3.5449078
            let shK: Float = 0.2820947766
            pf.u_probeShR0 = (averageSky.x * shK, 0, 0, 0)
            pf.u_probeShR1 = (0, 0, 0, 0)
            pf.u_probeShG0 = (averageSky.y * shK, 0, 0, 0)
            pf.u_probeShG1 = (0, 0, 0, 0)
            pf.u_probeShB0 = (averageSky.z * shK, 0, 0, 0)
            pf.u_probeShB1 = (0, 0, 0, 0)
            pf.u_probeShRGB2 = (0, 0, 0, 0)
            pf.u_averageProbeColor = (averageSky.x, averageSky.y, averageSky.z, 1)
            pf.u_probeCenter = (eye.x, eye.y, eye.z, 1)
            terrain.hideCloud = hideCloud
            terrain.encode(enc, perFrame: &pf, perPass: SIMD4<Float>(skyP.u_viewportSize.0, skyP.u_viewportSize.1, 1 / Float(w), 1 / Float(h)))
            enc.setRenderPipelineState(meshPipe)
        } else if let vbuf, let ibuf {
        enc.setVertexBuffer(vbuf, offset: 0, index: 0)
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
        }
        enc.endEncoding()

        frameIdx += 1

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
        if debugSkipWater && frameIdx == 0 { Boot.log("调试：跳过水面 pass（水面仍为占位 MSL，未接原版 Ocean*）") }
        if !debugSkipWater, let waterVB, let waterIB, let waterPipe, let waterDepthState,
           let wenc = cb.makeRenderCommandEncoder(descriptor: wrp) {
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

        /// 雾合成（原版单帧跑两遍：第一遍用上一帧亮度，第二遍用本帧新算出的亮度）
        func runFogUpsample(_ cbX: MTLCommandBuffer, _ avgLum: Float) {
            guard let fogUpsamplePipe, let fogTex, let fogOut else { return }
            let up = MTLRenderPassDescriptor()
            up.colorAttachments[0].texture = fogOut
            up.colorAttachments[0].loadAction = .dontCare
            up.colorAttachments[0].storeAction = .store
            if let uenc = cbX.makeRenderCommandEncoder(descriptor: up) {
                // Scene.metal 的 fogUpsampleFS 把常量声明成 `constant FU &u [[constant buffer(1)]]`，
                // FU 是 12 个 float4 的自建结构。之前把 PerFrame(1584B) 绑到 index 2，shader 却从 buffer(1)
                // 读 16B 的 viewport → 所有雾参数为 0 → 输出恒 1/(1+0)=1.0 → tonemap 反解成 0（整屏黑）。
                // 现在按 FU 字段顺序逐项映射原版 PerFrame 的值，绑到 shader 真正读取的 buffer(1)。
                struct FUF {
                    var eyePos: SIMD4<Float>; var sunDir: SIMD4<Float>
                    var sunColor: SIMD4<Float>; var sunSize: SIMD4<Float>
                    var fogDensityHeightDist: SIMD4<Float>; var atmosphereDensity: SIMD4<Float>
                    var atmosphereSample: SIMD4<Float>; var avgSkyboxColor: SIMD4<Float>
                    var atmSunColor: SIMD4<Float>; var earthPosRad: SIMD4<Float>
                    var viewportSize: SIMD4<Float>; var averageLum: SIMD4<Float>
                }
                var fogObj = SIMD4<Float>(0, 0, 0, 0)
                let tintTopV = envColor4("tintTop", SIMD4<Float>(0.0216, 0.0928, 0.3301, 1))
                let sunV = envColor4("sunColor", SIMD4<Float>(0.0825, 0.1882, 0.7490, 1))
                let ssz = skyF.u_sunSizeIntMoonPhase
                var fogF = FUF(eyePos: u.eyePos,
                               sunDir: u.sunDir,
                               sunColor: u.sunColor,
                               sunSize: SIMD4<Float>(ssz.0, ssz.1, ssz.2, ssz.3),
                               fogDensityHeightDist: SIMD4<Float>(envNum("fogDensity", 1), envNum("fogHeight", 0.1), envNum("drawDistance", 15000), 1),
                               atmosphereDensity: SIMD4<Float>(envNum("atmosphereDensity", 1), 0, 0, 0),
                               atmosphereSample: SIMD4<Float>(0, 0, 0, 0),
                               avgSkyboxColor: tintTopV,
                               atmSunColor: sunV,
                               earthPosRad: SIMD4<Float>(0, 0, 0, 0),
                               viewportSize: SIMD4<Float>(Float(w), Float(h), 1 / Float(w), 1 / Float(h)),
                               averageLum: SIMD4<Float>(avgLum, 0, 0, 0))
                uenc.setRenderPipelineState(fogUpsamplePipe)
                uenc.setFragmentBytes(&fogObj, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                uenc.setFragmentBytes(&fogF, length: MemoryLayout<FUF>.stride, index: 1)
                // Scene.metal 里的 fogUpsampleFS 是按原版 FogUpsample0.frag 译写的（texture 0=scene、
                // 2=fogTex、3=atmoTex，sampler 0；常量走 buffer(1) 的 FU）。这里按 MSL 声明的槽位绑。
                uenc.setFragmentTexture(sceneTex2, index: 0)
                uenc.setFragmentTexture(fogTex, index: 2)
                uenc.setFragmentTexture(blackTex ?? fallbackTex, index: 3)
                for i in 0...3 { uenc.setFragmentSamplerState(clampSampler, index: i) }
                uenc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                uenc.endEncoding()
            }
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
            // 原版第一遍雾固定用 u_averageLum = 1（server.cjs: u_averageLum:1），
            // 这样 1/x-1 反解出来的就是场景本身，几何平均不会和上一帧互相拉扯。
            runFogUpsample(cb, 1.0)
        }

        /// 后处理：Tonemap → Fxaa → drawable（在读画面第二遍雾之后跑）
        func runPost(_ cbX: MTLCommandBuffer) {
        // Pass 5：Tonemap（原版 Tonemap0.frag：HDR 反解 + bloom + 曝光 + 暗角 + 输出曲线）
        if let tonemapPipe, let ldrTex {
            let tp = MTLRenderPassDescriptor()
            tp.colorAttachments[0].texture = ldrTex
            tp.colorAttachments[0].loadAction = .dontCare
            tp.colorAttachments[0].storeAction = .store
            if let tenc = cbX.makeRenderCommandEncoder(descriptor: tp) {
                struct TUni { var bloomTint: SIMD4<Float>; var bloomParams: SIMD4<Float>
                              var viewportSize: SIMD4<Float>; var exposure: SIMD4<Float> }
                // 自动曝光在雾/穹顶开关变化时会把亮度在 0.6×–40× 之间来回甩，看着比固定还乱；
                // 改回固定倍率（默认 7.6×，就是上次你自己拖到的那个位置），只在滑杆上手动调。
                _ = averageLum
                var tu = TUni(bloomTint: envColor("bloomTint", SIMD3<Float>(1, 1, 1)),
                              bloomParams: SIMD4<Float>(envNum("bloomIntensity", 0), 0, 0, 0),
                              viewportSize: SIMD4<Float>(Float(w), Float(h), 1, 0),
                              exposure: SIMD4<Float>(envNum("exposure", 1) * exposureGain, 0, 0, 0))
                tenc.setRenderPipelineState(tonemapPipe)
                tenc.setFragmentBytes(&tu, length: MemoryLayout<TUni>.stride, index: 1)
                if frameIdx == 0 { Boot.log("调试：雾后处理旁路 debugSkipFogPost=\(debugSkipFogPost)（tonemap 直读 sceneTex2）") }
                tenc.setFragmentTexture((fogOut != nil && !debugSkipFogPost) ? fogOut! : sceneTex2, index: 0)
                tenc.setFragmentTexture(blackTex ?? fallbackTex, index: 1)
                tenc.setFragmentSamplerState(clampSampler, index: 0)
                tenc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                tenc.endEncoding()
            }
            // Pass 6：Fxaa0.frag
            if let fxaaPipe {
                let xp = MTLRenderPassDescriptor()
                xp.colorAttachments[0].texture = drawable.texture
                xp.colorAttachments[0].loadAction = .dontCare
                xp.colorAttachments[0].storeAction = .store
                if let xenc = cbX.makeRenderCommandEncoder(descriptor: xp) {
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
        }

        cb.commit()
        cb.waitUntilCompleted()
        // 原版（server.cjs 同样）：单帧内先出一遍雾、读回算几何平均亮度，再用新亮度重出一遍雾，才进 tonemap。
        // 之前只跑一遍且用上一帧亮度，亮度会在两档之间来回跳，截图一会儿黑一会儿白。
        if let fogOut {
            let l = averageLuminance(of: fogOut)
            if l > 0, l.isFinite {
                // 逐帧抖动会让自动曝光来回跳，做一点时间平滑（0.6 旧 + 0.4 新）
                averageLum = frameIdx == 0 ? l : (averageLum * 0.6 + l * 0.4)
            }
            if frameIdx <= 6 { Boot.log("平均亮度 f\(frameIdx)=\(l)（第二遍雾用这个）") }
        }
        if let cb2 = queue.makeCommandBuffer() {
            runFogUpsample(cb2, averageLum)
            runPost(cb2)
            cb2.present(drawable)
            cb2.commit()
        }
        // 探针（亮度已在上面的两遍雾里算过）
        if let fogOut {
            if frameIdx <= 6 {
                Boot.log("探针 f\(frameIdx) 地面75%: 地形=\(probeHalf(sceneTex, 0.5, 0.75)) 雾后=\(probeHalf(fogOut, 0.5, 0.75)) | 天空10%: 地形=\(probeHalf(sceneTex, 0.5, 0.1))")
                Boot.log("帧体检 f\(frameIdx) cb=\(cb.status.rawValue) err=\(String(describing: cb.error)) 存储=\(sceneTex.storageMode.rawValue)/\(fogOut.storageMode.rawValue) 尺寸=\(sceneTex.width)×\(sceneTex.height)")
                Boot.log("scene 亮度图 f\(frameIdx):\n\(probeGrid(sceneTex, 24, 10))")
                Boot.log("雾后 亮度图 f\(frameIdx):\n\(probeGrid(fogOut, 24, 10))")
                Boot.log("显示(bgra8) 中心60%,50%=\(probeBGRA(ldrTex, 0.6, 0.5)) 顶部10%=\(probeBGRA(ldrTex, 0.5, 0.1))")
            }
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

    /// 32×32 天空目标求算术平均（等价于引擎对天空盒最粗 mip 取平均）

    /// 把整张纹理按 cols×rows 采样成字符亮度图（. 全黑  · 极暗  1-9 递增  # 亮）
    private func probeGrid(_ tex: MTLTexture?, _ cols: Int, _ rows: Int) -> String {
        guard let tex else { return "nil" }
        let w = tex.width, h = tex.height
        var out = ""
        var buf = [UInt8](repeating: 0, count: 8)
        for r in 0..<rows {
            var line = ""
            for c in 0..<cols {
                let x = min(w - 1, Int(Float(w) * (Float(c) + 0.5) / Float(cols)))
                let y = min(h - 1, Int(Float(h) * (Float(r) + 0.5) / Float(rows)))
                buf.withUnsafeMutableBytes { raw in
                    tex.getBytes(raw.baseAddress!, bytesPerRow: 8,
                                 from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
                }
                func half(_ i: Int) -> Float {
                    Float(Float16(bitPattern: UInt16(buf[i]) | (UInt16(buf[i + 1]) << 8)))
                }
                let l = max(0, min(1, 0.2126 * half(0) + 0.7152 * half(2) + 0.0722 * half(4)))
                if l < 0.0005 { line += "." }
                else if l < 0.01 { line += "·" }
                else if l < 0.05 { line += "1" }
                else if l < 0.1 { line += "2" }
                else if l < 0.2 { line += "3" }
                else if l < 0.35 { line += "4" }
                else if l < 0.5 { line += "5" }
                else if l < 0.7 { line += "6" }
                else if l < 0.9 { line += "7" }
                else if l < 1.2 { line += "8" }
                else { line += "#" }
            }
            out += line + "\n"
        }
        return out
    }

    private func probeBGRA(_ tex: MTLTexture?, _ fx: Float, _ fy: Float) -> String {
        guard let tex else { return "nil" }
        let w = tex.width, h = tex.height
        let x = min(w - 1, Int(Float(w) * fx)), y = min(h - 1, Int(Float(h) * fy))
        var buf = [UInt8](repeating: 0, count: 4)
        buf.withUnsafeMutableBytes { raw in
            tex.getBytes(raw.baseAddress!, bytesPerRow: 4,
                         from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
        }
        return String(format: "(b=%d g=%d r=%d a=%d)", buf[0], buf[1], buf[2], buf[3])
    }

    private func probeHalf(_ tex: MTLTexture?, _ fx: Float, _ fy: Float) -> String {
        guard let tex else { return "nil" }
        let w = tex.width, h = tex.height
        let x = min(w - 1, Int(Float(w) * fx)), y = min(h - 1, Int(Float(h) * fy))
        var buf = [UInt8](repeating: 0, count: 8)
        buf.withUnsafeMutableBytes { raw in
            tex.getBytes(raw.baseAddress!, bytesPerRow: 8,
                         from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
        }
        func half(_ i: Int) -> Float {
            Float(Float16(bitPattern: UInt16(buf[i]) | (UInt16(buf[i + 1]) << 8)))
        }
        return String(format: "(%.3f, %.3f, %.3f, %.3f)", half(0), half(2), half(4), half(6))
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
