enum Shaders {
    static let source = """

#include <metal_stdlib>
using namespace metal;

struct VIn { float3 pos [[attribute(0)]]; float3 nrm [[attribute(1)]]; float2 uv [[attribute(2)]];
            uchar4 l0 [[attribute(3)]]; uchar4 l1 [[attribute(4)]]; uchar4 l2 [[attribute(5)]]; };
struct VOut { float4 pos [[position]]; float3 nrm; float2 uv; float4 l0; float4 l1; float4 l2; float3 world; };
struct U {
  float4x4 viewProj; float4 camPos; float4 sunDir; float4 sunColor; float4 skyColor; float4 groundColor;
  float4 tintTop; float4 tintMidTop; float4 tintMidMid; float4 tintMidBot; float4 tintBot; float4 exposure;
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
                   constant float4 &matColor [[buffer(2)]]) {
    float3 base = tex.sample(smp, in.uv).rgb * tex2.sample(smp, in.uv).rgb * matColor.rgb;
    // 原版 Mesh2243.frag 的烘焙光照：diffuse = (L0.rgb^2 / L0.w) * mix(平均天光, 日光, L1.r)
    float4 L0 = in.l0, L1 = in.l1, L2 = in.l2;
    float3 diffuse = (L0.rgb * L0.rgb) / max(L0.w, 0.0001);
    diffuse = diffuse * mix(u.skyColor.rgb * 1.6, u.sunColor.rgb, L1.r);
    diffuse = diffuse + L1.a * exp2(255.0 * L1.b - 128.0) * float3(0.0);   // 点光项：本关无点光
    // 阳光遮蔽 = L1.g^2（原版 tmpvar_51 = light1.y^2 * normTex.z）
    float shade = L1.g * L1.g;
    float3 sunLit = u.sunColor.rgb * 0.55 * shade * max(dot(normalize(in.nrm), normalize(u.sunDir.xyz)), 0.0);
    float3 col = base * (diffuse + sunLit + 0.03);
    float d = length(in.world - u.camPos.xyz);
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

"""
}
