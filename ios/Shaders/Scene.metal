#include <metal_stdlib>
using namespace metal;

struct U {
  float4x4 viewProj;
  float4 eyePos;
  float4 sunDir;
  float4 sunColor;
  float4 avgSky;
  float4 pointLight;
  float4 viewport;
  float4 exposure;
  float4 lightShadowConsts;   // xyz=光轴方向, w=半径, y=遮挡开关
};

struct VIn {
  float3 pos   [[attribute(0)]];
  float3 nrm   [[attribute(1)]];
  uchar4 color [[attribute(2)]];
  float4 uv0   [[attribute(3)]];
  float4 uv1   [[attribute(4)]];
  uchar4 l0    [[attribute(5)]];
  uchar4 l1    [[attribute(6)]];
  uchar4 l2    [[attribute(7)]];
};

struct VOut {
  float4 pos [[position]];
  float3 world;
  float3 nrm;
  float4 color;
  float4 l0;
  float4 l1;
  float4 l2;
  float3 eye;
  float4 uv01;
  float4 uv23;
  float3 probeAmb;
  float3 probeSpec;
};

// Mesh2243.vert 原样：world / normal / eye / probe 环境与反射
vertex VOut vs(VIn in [[stage_in]], constant U &u [[buffer(1)]],
               texturecube<float> probe [[texture(0)]], sampler lodsmp [[sampler(0)]]) {
  VOut o;
  o.world = in.pos;
  o.pos = u.viewProj * float4(in.pos, 1.0);
  o.nrm = in.nrm;
  o.color = float4(in.color) / 255.0;
  o.eye = u.eyePos.xyz - in.pos;
  float3 E = normalize(o.eye);
  float3 I = -E;
  o.probeAmb = probe.sample(lodsmp, o.nrm, level(5.0)).rgb;
  o.probeSpec = probe.sample(lodsmp, I - 2.0 * dot(o.nrm, I) * o.nrm, level(5.0)).rgb;
  o.uv01 = in.uv0;
  o.uv23 = in.uv1;
  o.l0 = float4(in.l0) / 255.0;
  o.l1 = float4(in.l1) / 255.0;
  o.l2 = float4(in.l2) / 255.0;
  return o;
}

// 原版 GGX 高光项（Mesh2243.frag 里那段 spec_118 / spec_135 的展开）
static float3 specGGX(float3 N, float3 V, float3 L, float rough, float3 specColor) {
  float3 H = normalize(V + L);
  float a = rough * rough;
  float NoV = max(dot(N, V), 0.0);
  float NoL = max(dot(N, L), 0.0);
  float NoH = max(dot(N, H), 0.0);
  float d = (NoH * NoH * (a - 1.0)) + 1.0;
  float3 F = mix(specColor, float3(1.0), pow(clamp(1.0 - dot(V, H), 0.0, 0.999), 5.0));
  float num = a / (d * d);
  float den = (NoV + sqrt(((NoV - (NoV * a)) * NoV) + a))
            * (NoL + sqrt(((NoL - (NoL * a)) * NoL) + a));
  return F * (NoL * (num / den));
}

fragment float4 fs(VOut in [[stage_in]], constant U &u [[buffer(1)]],
                   constant float4 &diffuseColor [[buffer(2)]],
                   constant float4 &selfLit [[buffer(3)]],
                   constant float4 &params [[buffer(4)]],      // x=diffuse1TexScale, y=normTexScale
                   texture2d<float> diffuse1 [[texture(0)]],
                   texture2d<float> diffuse2 [[texture(1)]],
                   texture2d<float> normTex  [[texture(2)]],
                   texture2d<float> lightTex [[texture(3)]],
                   texture2d<uint> lOffsets [[texture(4)]],
                   texture2d<uint> lCounts  [[texture(5)]],
                   texture2d<float> lPos    [[texture(6)]],
                   texture2d<float> lCol    [[texture(7)]],
                   texturecube<float> probe [[texture(8)]],
                   sampler smp [[sampler(0)]], sampler clampSmp [[sampler(1)]],
                   sampler lodsmp [[sampler(2)]]) {

  float4 L0 = in.l0, L1 = in.l1, L2 = in.l2;
  float tmpvar_27 = L2.w;
  float tmpvar_28 = L1.g * L1.g;
  float3 tmpvar_26 = (L2.xyz * 2.007874) - 1.007874;

  // 烘焙漫反射
  float3 amb = (L0.rgb * L0.rgb) / max(L0.w, 0.0001);
  amb = amb * mix(u.avgSky.rgb, u.sunColor.rgb, L1.r);
  amb = amb + ((L1.w * exp2((255.0 * L1.b) - 128.0)) * u.pointLight.rgb);

  // ---- 法线：u_normTex + dFdx/dFdy 建 TBN ----
  float2 nUv = in.uv01.xy * params.y;
  float4 nSample = normTex.sample(smp, nUv);
  float3 p = -in.eye;
  float3 dx = dfdx(p), dy = dfdy(p);
  float2 du = dfdx(nUv), dv = dfdy(nUv);
  float3 s1 = (dy.yzx * in.nrm.zxy) - (dy.zxy * in.nrm.yzx);
  float3 s2 = (in.nrm.yzx * dx.zxy) - (in.nrm.zxy * dx.yzx);
  float3 t1 = (s1 * du.x) + (s2 * dv.x);
  float3 t2 = (s1 * du.y) + (s2 * dv.y);
  float invLen = min(1e7, 1.0 / sqrt(max(dot(t1, t1), dot(t2, t2))));
  float3x3 tbn;
  tbn[0] = t1 * invLen;
  tbn[1] = t2 * invLen;
  tbn[2] = in.nrm;
  float2 nxy = (nSample.xy * 2.007874) - 1.007874;
  float nz = sqrt(max(1.0 - dot(nxy, nxy), 0.0001));
  float3 N = normalize(tbn * float3(nxy.x, nxy.y, nz));

  float tmpvar_35 = nSample.z;
  float tmpvar_34 = nSample.w;
  float tmpvar_51 = tmpvar_28 * tmpvar_35;
  float3 tmpvar_20 = tmpvar_26 * tmpvar_35;

  // ---- 顶点色四通道（原版 v_color）----
  float4 vc = in.color;
  float emission = 2.0 * max(0.0, vc.z - 0.51);
  float4 clr = float4(vc.xy, emission, min(1.0, vc.z * 2.0));

  // ---- 两张 diffuse 各用各的 uv ----
  float4 baseTex = diffuse1.sample(smp, in.uv01.xy * params.x) * diffuse2.sample(smp, in.uv23.zw);
  float3 baseColor = baseTex.rgb * diffuseColor.rgb;
  float3 color15 = baseColor * clr.w;

  float4 lm = lightTex.sample(clampSmp, in.uv01.zw);
  float3 Ldir = -u.sunDir.xyz;
  float3 V = normalize(in.eye);
  float3 R = -V - 2.0 * dot(N, -V) * N;
  float rough = max(max(0.03, vc.x * tmpvar_34),
                    pow(clamp(max(dot(dfdx(in.nrm), dfdx(in.nrm)), dot(dfdy(in.nrm), dfdy(in.nrm))), 0.0, 1.0), 0.333));
  float3 specColor = mix((baseColor * 0.015) + float3(0.035), baseColor, vc.y);

  // ---- 光簇：点光 + 球体遮挡（原版 lightCounts 那一段）----
  float3 clusCol = float3(0.0);
  float occMul = 1.0;
  int2 tile = int2(floor(in.pos.xy / max(u.viewport.xy, float2(1.0)) * float2(32.0, 16.0)));
  tile.y = 15 - tile.y;                       // GL 的 FragCoord 原点在左下，Metal 在左上
  tile = clamp(tile, int2(0), int2(31, 15));
  uint4 cnt = lCounts.read(uint2(tile));
  if ((cnt.x + cnt.y) != 0u) {
    uint off = lOffsets.read(uint2(tile)).x;
    for (uint i = 0u; i < cnt.x; i++) {
      float4 lp = lPos.read(uint2(off + i, 0));
      float4 lc = lCol.read(uint2(off + i, 0));
      float3 dv = lp.xyz - in.world;
      float d2 = dot(dv, dv);
      float atten = min(1.0, d2 * lp.w);
      atten = 1.0 - pow(atten, lc.w + 0.1);
      float nd = max(0.0, dot(dv / sqrt(d2), N));
      atten = atten * ((nd * 0.9) + 0.1);
      clusCol = clusCol + lc.rgb * atten;
    }
    uint shadowCount = (tmpvar_51 > 0.01) ? cnt.y : 0u;
    float occ = 0.0;
    float Rs = u.lightShadowConsts.w;
    float3 shadowPos = in.world + ((in.nrm - N) * 0.2);
    off = off + cnt.x;
    for (uint i = 0u; i < shadowCount; i++) {
      float4 sp = lPos.read(uint2(off + i, 0));
      off = off + 1u;
      float3 sv = shadowPos - sp.xyz;
      float sl = max(sqrt(dot(sv, sv)), 0.0001);
      float3 x = sv - (u.lightShadowConsts.xyz * dot(u.lightShadowConsts.xyz, sv));
      float d = sqrt(dot(x, x)) / sl;
      float Ro = sp.w / sl;
      float ed0 = Rs - Ro;
      float k = clamp((d - ed0) / ((Rs + Ro) - ed0), 0.0, 1.0);
      occ = max(occ, (Ro / Rs) * (1.0 - k * (k * (3.0 - 2.0 * k))));
    }
    occMul = 1.0 - (min(occ, 1.0) * max(-u.lightShadowConsts.y, 0.0));
  }

  float3 tmpvar_19 = amb + clusCol;
  float tmpvar_21 = tmpvar_51 * occMul;

  float NdotL = max(0.0, dot(N, Ldir));
  float3 ambDir = normalize(tmpvar_20 + (0.1 * N));
  float3 diffTerm = color15 * (1.0 - vc.y) * NdotL;
  float3 specSun = min(float3(100.0), specGGX(N, V, Ldir, rough, specColor));

  float3 finalColor = ((u.sunColor.rgb * tmpvar_21) * lm.y) * (diffTerm + specSun);

  // 环境/反射项：原版用 probe 立方体在 LOD5 上采样
  float ambDirLen = pow(clamp((sqrt(dot(tmpvar_20, tmpvar_20)) * 2.5) - 1.5, 0.0, 1.0), 4.0);
  float3 Namb = N;
  float4 t148 = float4(1.041667, 0.475, 0.01822917, 0.25) * (1.0 - rough);
  t148.zw = t148.zw + float2(-0.015625, 0.75);
  float fit = (t148.x * min(t148.y, exp2(-9.28 * max(0.0, dot(Namb, V)))) + t148.z);
  float3 subsurf = ((5.0 * color15) * pow(max(0.0, dot(-V, Ldir)), 8.0)) * max(0.0, dot(-N, Ldir));
  float3 probeAmbR = probe.sample(lodsmp, N, level(5.0)).rgb / max(in.probeAmb, float3(1e-4));
  float3 probeSpecR = probe.sample(lodsmp, R, level(5.0) * sqrt(rough)).rgb / max(in.probeSpec, float3(1e-4));
  float3 refl = probeSpecR * clamp((fit + (specColor * (t148.w - fit))), 0.0, 1.0);
  float3 ambSpec = mix(refl, min(float3(100.0), specGGX(N, V, ambDir, min(1.0, rough + 0.2 * (1.0 - ambDirLen)), specColor)), ambDirLen);
  float3 ambTerm = ((probeAmbR * color15) * (1.0 - vc.y)) + mix(ambSpec, subsurf, tmpvar_27);
  finalColor = finalColor + (((tmpvar_19 * ambTerm) * lm.x) + ((5.0 * emission) * color15));

  // 自发光材质（u_selfLit）——星星那类
  float3 selfLitColor = float3(0.0);
  float lum = dot(color15, float3(0.299, 0.587, 0.114));
  if (((selfLit.x > 0.0) && (lum > (1.0 - selfLit.x))) || (emission > 0.0)) {
    selfLitColor = ((color15 * selfLit.y) * max((10.0 * emission), (lum - (1.0 - selfLit.x)) / max(selfLit.x, 0.0001)));
  }
  selfLitColor = selfLitColor * (1.0 + selfLit.z);
  finalColor = finalColor + selfLitColor;

  return float4(finalColor, 1.0);
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
