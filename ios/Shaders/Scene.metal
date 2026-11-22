#include <metal_stdlib>
using namespace metal;

struct VIn { float3 pos [[attribute(0)]]; float3 nrm [[attribute(1)]]; float2 uv [[attribute(2)]];
            uchar4 l0 [[attribute(3)]]; uchar4 l1 [[attribute(4)]]; uchar4 l2 [[attribute(5)]]; };
struct VOut { float4 pos [[position]]; float3 nrm; float2 uv; float4 l0; float4 l1; float4 l2; float3 world; };
struct U {
  float4x4 viewProj; float4 camPos; float4 sunDir; float4 sunColor; float4 skyColor; float4 groundColor;
  float4 tintTop; float4 tintMidTop; float4 tintMidMid; float4 tintMidBot; float4 tintBot; float4 exposure;
  float4 avgSky; float4 pointLight; float4 viewport;
};
// 原版 Ambience 的天空渐变：按视线仰角在 tintBot→tintMidBot→tintMidTop→tintTop 之间插值
static float3 skyGradient(float4 cB, float4 cMB, float4 cMT, float4 cT, float y) {
  if (y < -0.35) return cB.rgb;
  if (y < 0.0) { float t = (y + 0.35) / 0.35; return mix(cB.rgb, cMB.rgb, t); }
  if (y < 0.30) { float t = y / 0.30; return mix(cMB.rgb, cMT.rgb, t); }
  float t = clamp((y - 0.30) / 0.70, 0.0, 1.0);
  return mix(cMT.rgb, cT.rgb, t);
}
vertex VOut vs(VIn in [[stage_in]], constant U &u [[buffer(1)]]) {
    VOut o;
    o.pos = u.viewProj * float4(in.pos, 1);
    o.nrm = in.nrm; o.uv = in.uv; o.world = in.pos;
    o.l0 = float4(in.l0) / 255.0; o.l1 = float4(in.l1) / 255.0; o.l2 = float4(in.l2) / 255.0;
    return o;
}
fragment float4 fs(VOut in [[stage_in]], constant U &u [[buffer(1)]],
                   texture2d<float> tex [[texture(0)]], texture2d<float> tex2 [[texture(1)]],
                   sampler smp [[sampler(0)]],
                   constant float4 &matColor [[buffer(2)]],
                   texture2d<uint> lOffsets [[texture(3)]], texture2d<uint> lCounts [[texture(4)]],
                   texture2d<float> lPos [[texture(5)]], texture2d<float> lCol [[texture(6)]]) {
    // ---- 照搬 Mesh2243.frag 的烘焙光路 ----
    float4 L0 = in.l0, L1 = in.l1, L2 = in.l2;
    // tmpvar_25 = (light0.rgb^2 / light0.w) * mix(u_averageSkyColor, u_sunColor, light1.r)
    float3 amb = (L0.rgb * L0.rgb) / max(L0.w, 0.0001);
    amb = amb * mix(u.avgSky.rgb, u.sunColor.rgb, L1.r);
    // + light1.w * exp2(255*light1.b - 128) * u_pointLight
    amb = amb + L1.w * exp2(255.0 * L1.b - 128.0) * u.pointLight.rgb;
    // light2.xyz 是环境方向（原版 tmpvar_26 = light2*2.007874 - 1.007874）
    float3 ambDir = normalize((L2.xyz * 2.007874) - 1.007874 + float3(0.0, 0.0, 1e-6));

    // 32×16 屏幕光簇：烛台的点光都在这里
    float3 cluster = float3(0.0);
    int2 tile = int2(floor(in.pos.xy / max(u.viewport.xy, float2(1.0)) * float2(32.0, 16.0)));
    // 原版 GL 的 gl_FragCoord 原点在左下，Metal 在左上，y 翻一下
    tile.y = 15 - tile.y;
    tile = clamp(tile, int2(0), int2(31, 15));
    uint4 cnt = lCounts.read(uint2(tile));
    if (cnt.x + cnt.y > 0u) {
        uint off = lOffsets.read(uint2(tile)).x;
        for (uint i = 0u; i < cnt.x; i++) {
            float4 p = lPos.read(uint2(off + i, 0));
            float4 c = lCol.read(uint2(off + i, 0));
            float3 d = p.xyz - in.world;
            float d2 = dot(d, d);
            float atten = min(1.0, d2 * p.w);
            atten = 1.0 - pow(atten, c.w + 0.1);
            float ndl = max(0.0, dot(d / sqrt(max(d2, 1e-4)), normalize(in.nrm + ambDir * 0.05)));
            atten = atten * (ndl * 0.9 + 0.1);
            cluster = cluster + c.rgb * atten;
        }
    }

    float3 base = tex.sample(smp, in.uv).rgb * tex2.sample(smp, in.uv).rgb * matColor.rgb;
    // 阳光遮蔽 = L1.g^2（原版 tmpvar_51 = light1.y^2 * normTex.z）
    float shade = L1.g * L1.g;
    float3 sunLit = u.sunColor.rgb * 0.55 * shade * max(dot(normalize(in.nrm), normalize(u.sunDir.xyz)), 0.0);

    float3 col = base * (amb + cluster + sunLit + 0.02);
    col = col * max(u.exposure.x, 0.01);
    col = col / (col + 0.55);
    col = pow(max(col, 0.0), float3(0.4545));
    return float4(col, 1);
}

struct WU {
  float4x4 viewProj; float4 camPos; float4 sunDir; float4 sunColor; float4 skyColor;
  float4 simTerms; float4 viewport; float4 uvOffA; float4 uvOffB; float4 uvOffC;
};
struct WVIn { float3 pos [[attribute(0)]]; float2 uv [[attribute(1)]]; };
struct WVOut { float4 pos [[position]]; float3 world; float3 eye; float4 uv01; float4 uv23; float3 nrm; };
vertex WVOut waterVS(WVIn in [[stage_in]], constant WU &u [[buffer(1)]]) {
    WVOut o;
    float3 w = in.pos;
    float3 toEye = w - u.camPos.xyz;
    float atten = clamp(sqrt(dot(toEye, toEye)) * -0.06666667 + 1.666667, 0.0, 1.0);
    float wave = (sin(w.x) * sin(w.z * 0.3 + u.viewport.w) + sin(-w.x * 0.4 + u.viewport.w * 1.25)) * 0.05;
    w.y += wave * atten;
    o.world = w;
    o.eye = u.camPos.xyz - w;
    o.pos = u.viewProj * float4(w, 1);
    o.uv01.xy = (w.xz * 77.0 / 2048.0 + u.uvOffA.xy);
    o.uv01.zw = (w.xz * 296.0 / 512.0 + u.uvOffB.xy);
    o.uv23.xy = (w.xz * 104.0 / 1024.0 + u.uvOffC.xy);
    o.uv23.zw = float2(0.0);
    o.nrm = float3(0, 1, 0);
    return o;
}
fragment float4 waterFS(WVOut in [[stage_in]], constant WU &u [[buffer(1)]],
    texture2d<float> scene [[texture(0)]], texture2d<float> normalTex [[texture(1)]],
    texture2d<float> causticTex [[texture(2)]],
    sampler smp [[sampler(0)]], sampler cl [[sampler(1)]]) {
    float2 fragUv = float2(in.pos.x / u.viewport.x, in.pos.y / u.viewport.y);
    float3 E = normalize(in.eye);
    float3 N = normalize(in.nrm);
    float3 nrmTap = (normalTex.sample(smp, in.uv01.xy).xyz
                   + normalTex.sample(smp, in.uv01.zw).xyz
                   + normalTex.sample(smp, in.uv23.xy).xyz) / 3.0 - 0.5;
    N.xz = N.xz + nrmTap.xz;
    N = normalize(N);
    float3 I = -E;
    float3 reflDir = I - 2.0 * dot(N, I) * N;
    reflDir.y = abs(reflDir.y);
    float3 refl = u.skyColor.rgb * (0.7 + 0.3 * clamp(reflDir.y, 0.0, 1.0));
    float fres = mix(0.04, 0.8, pow(clamp(1.0 - dot(E, N), 0.0, 1.0), 7.0));
    float3 H = normalize(E - u.sunDir.xyz);
    float3 spec = u.sunColor.rgb * 2.0 * pow(max(dot(N, H), 0.0), 180.0);
    float2 refrUv = fragUv + N.xz * 0.035;
    float3 bg = scene.sample(cl, refrUv).rgb;
    float3 deep = float3(0.01, 0.03, 0.06) * (u.sunColor.rgb * 0.7 + u.skyColor.rgb * 0.5);
    float3 body = mix(bg, deep * 5.0 + bg * 0.12, 0.82);
    float ca = causticTex.sample(smp, in.uv23.xy).z;
    body = body * clamp(((ca * ca * 2.0 - 0.1) * 0.5) + 1.0, 0.55, 1.45) * 0.55;
    float3 col = mix(body, refl + spec, fres);
    col = col / (col + 0.55);
    col = pow(max(col, 0.0), float3(0.4545));
    return float4(col, 1);
}
