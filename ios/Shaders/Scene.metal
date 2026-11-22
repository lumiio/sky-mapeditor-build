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
  float3 probeSpecR = probe.sample(lodsmp, R, level(5.0 * sqrt(rough))).rgb / max(in.probeSpec, float3(1e-4));
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

  // 原版把 HDR 存成 c/(c+1)，Tonemap0.frag 里再 1/ldr-1 反解回来
  return float4(finalColor / (finalColor + 1.0), 1.0);
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
    return float4(col / (col + 1.0), 1.0);
}

// ---- Tonemap0.frag 原样搬（HDR 反解 + bloom 混合 + 曝光 + 暗角 + 输出曲线）----
struct TIn { float4 pos [[position]]; float2 uv; };
struct TUni { float4 bloomTint; float4 bloomParams; float4 viewportSize; float4 exposure; };

vertex TIn tonemapVS(uint vid [[vertex_id]]) {
  TIn o;
  float2 p[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
  o.pos = float4(p[vid], 0.0, 1.0);
  o.uv = float2((p[vid].x + 1.0) * 0.5, (1.0 - p[vid].y) * 0.5);
  return o;
}

fragment float4 tonemapFS(TIn in [[stage_in]], constant TUni &u [[constant buffer(1)]],
                          texture2d<float> texFull [[texture(0)]],
                          texture2d<float> bloomTex [[texture(1)]],
                          sampler smp [[sampler(0)]]) {
  float4 full = texFull.sample(smp, in.uv, level(0.0));
  float3 c = (float3(1.0) / max(float3(0.0001), full.xyz)) - float3(1.0);
  float3 bloom = bloomTex.sample(smp, in.uv).xyz * u.bloomTint.xyz;
  float3 comp = ((0.25 - (u.bloomParams.x * 0.25)) * c + bloom * (u.bloomParams.x + u.bloomParams.y)) * u.exposure.x;
  float2 deathOffset = in.uv - float2(0.5);
  deathOffset.x = deathOffset.x * u.viewportSize.z;
  float t12 = clamp(((dot(deathOffset, deathOffset) * 0.25) - 0.625) / -0.625, 0.0, 1.0);
  float t13 = max((((t12 * (t12 * (3.0 - (2.0 * t12)))) * 0.97) + 0.03) - 0.0625, 0.0);
  comp = comp * t13;
  float3 scalar = comp + 0.25;
  float3 outv = comp / scalar;
  return float4(outv * outv, 0.0);
}

// ---- FogVolume0.frag 原样：用 Beamo 的遮挡体画体积，正面写 +、背面写 - ----
struct FVIn { float3 pos [[attribute(0)]]; };
struct FVOut { float4 pos [[position]]; float dist; };
struct FVUni { float4 params; };   // x = u_intensity
vertex FVOut fogVolumeVS(FVIn in [[stage_in]], constant U &u [[buffer(1)]]) {
  FVOut o;
  o.pos = u.viewProj * float4(in.pos, 1.0);
  o.dist = length(in.pos - u.eyePos.xyz);
  return o;
}
fragment float4 fogVolumeFS(FVOut in [[stage_in]], constant FVUni &u [[constant buffer(1)]],
                            bool front [[front_facing]]) {
  float Do = min(256000.0, in.dist);
  float sign_ = front ? 0.001 : -0.001;
  return float4((Do * u.params.x) * sign_, 0, 0, 0);
}

// ---- FogUpsample0.frag 的雾合成核心（clouds/alpha/beacon 分支按原条件关闭）----
struct FU {
  float4 eyePos; float4 sunDir; float4 sunColor; float4 sunSize;
  float4 fogDensityHeightDist; float4 atmosphereDensity; float4 atmosphereSample;
  float4 avgSkyboxColor; float4 atmSunColor; float4 earthPosRad; float4 viewportSize;
};
fragment float4 fogUpsampleFS(TIn in [[stage_in]], constant FU &u [[constant buffer(1)]],
                              texture2d<float> scene [[texture(0)]],
                              texture2d<float> fogTex [[texture(2)]],
                              texture2d<float> atmoTex [[texture(3)]],
                              sampler smp [[sampler(0)]]) {
  float2 uv = in.uv;
  float4 sc = scene.sample(smp, uv);
  float tmpvar_15 = fogTex.sample(smp, uv).x * 1000.0;   // 原版: fogTex.x * 1000

  // 视线方向（view space）
  float2 ndc = uv * 2.0 - 1.0;
  float tanHalf = tan(25.0 * 3.14159265 / 180.0);
  float aspect = u.viewportSize.x / max(u.viewportSize.y, 1.0);
  float3 pointer = normalize(float3(ndc.x * tanHalf * aspect, -ndc.y * tanHalf, -1.0));

  float EdotL = dot(normalize(pointer), -u.sunDir.xyz);
  float3 pos = u.eyePos.xyz + pointer * tmpvar_15;
  if (tmpvar_15 >= 256000.0) {
    float3 dir = normalize(pos - u.eyePos.xyz);
    float3 toC = u.earthPosRad.xyz - u.eyePos.xyz;
    float len = length(toC);
    float3 w;
    w.xz = (u.eyePos.xz + 25000.0 * dir.xz);
    float3 x38 = (u.eyePos.xyz + max(15000.0, sqrt(max(0.0, len * len - u.earthPosRad.w * u.earthPosRad.w))) * dir) - u.earthPosRad.xyz;
    w.y = sqrt(dot(x38, x38)) - u.earthPosRad.w;
    pos = w;
  } else {
    float3 c = pos - u.earthPosRad.xyz;
    pos.y = max(0.0, sqrt(dot(c, c)) - u.earthPosRad.w);
  }

  float3 diff = pos - u.eyePos.xyz;
  diff.y = sign(diff.y) * max(0.1, abs(diff.y));
  float2 r2 = float2(1.0, u.fogDensityHeightDist.y);
  float2 d2 = 0.000901684 / r2;
  float2 a2 = float2(u.atmosphereDensity.x, u.fogDensityHeightDist.x);
  float2 k2 = (0.000832548 * a2) / d2;
  float4 v4 = float4(d2 * u.eyePos.y, d2 * (diff.y + u.eyePos.y));
  float4 e4 = exp2(-v4);
  float2 q2 = float2(e4.x - e4.z, e4.y - e4.w);
  float2 sc2 = min(float2(64000.0), ((length(diff) / diff.y) * k2) * q2);

  float EdotL2 = EdotL * EdotL;
  float depthContribution = tmpvar_15 / 256000.0;
  float phase = (EdotL2 * 0.2) + (EdotL * 0.4) + 0.4;
  float t62 = 1.0 - exp2(-5.0 * sc2.x);
  float t66 = 1.0 - exp2(-20.0 * sc2.y);
  float3 atm = atmoTex.sample(smp, uv).xyz;
  float sunGlow = max((EdotL2 * EdotL) - u.sunSize.z, 0.0);
  float halo = 1.0 / (200.0 + (2000.0 * u.sunSize.z));
  float3 cA = ((u.atmSunColor.xyz * atm) * (sc2.x * (1.0 + EdotL2))) * (phase * t62);
  float3 cB = (u.avgSkyboxColor.xyz + u.sunColor.xyz * sunGlow)
            * mix(((3333.3 * sc2.y) * (halo / (halo - (EdotL - 1.0)))) * depthContribution, phase, t66);
  float3 fogCol = mix(cA, cB, t66) * 0.5;
  float fogW = (t62 * (1.0 - t66)) + t66;

  float lum = dot(float3(0.2126, 0.7152, 0.0722), sc.xyz) * 0.8;
  float w = max(fogW - lum * lum, 0.0);
  return float4(sc.xyz * (1.0 - w) + fogCol, 1.0);
}

// ---- Fxaa0.frag 原样（4 邻域亮度 + 方向搜索 + 边缘判定）----
struct FXU { float4 params; };  // xy = viewport size
fragment float4 fxaaFS(TIn in [[stage_in]], constant FXU &u [[constant buffer(1)]],
                       texture2d<float> tex [[texture(0)]], sampler smp [[sampler(0)]]) {
  float2 invTex = 1.0 / u.params.xy;
  float4 c = tex.sample(smp, in.uv);
  float3 w = float3(0.25, 0.6, 0.15);
  float lA = dot(tex.sample(smp, in.uv, level(0), int2(-1, -1)).xyz, w);
  float lB = dot(tex.sample(smp, in.uv, level(0), int2(1, -1)).xyz, w);
  float lC = dot(tex.sample(smp, in.uv, level(0), int2(-1, 1)).xyz, w);
  float lD = dot(tex.sample(smp, in.uv, level(0), int2(1, 1)).xyz, w);
  float lM = dot(c.xyz, w);
  float mn = min(min(lM, lA), min(min(lB, lC), lD));
  float mx = max(max(lM, lA), max(max(lB, lC), lD));
  float2 dir;
  dir.x = (lC + lD) - (lA + lB);
  dir.y = (lA + lC) - (lB + lD);
  dir = (min(float2(8.0), max(float2(-8.0), dir * (1.0 / ((min(abs(dir.x), abs(dir.y))
        + max(((lA + lB) + (lC + lD)) * 0.02083333, 0.0078125)))))) * invTex;
  float3 s13 = 0.5 * (tex.sample(smp, in.uv + dir * -0.1666667).xyz + tex.sample(smp, in.uv + dir * 0.1666667).xyz);
  float3 s16 = (s13 * 0.5) + (0.25 * (tex.sample(smp, in.uv + dir * -0.5).xyz + tex.sample(smp, in.uv + dir * 0.5).xyz));
  float l16 = dot(s16, w);
  float3 col = (l16 < mn || l16 > mx) ? s13 : s16;
  return float4(col, 0.5);
}
