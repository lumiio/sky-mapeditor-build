#!/usr/bin/env python3
"""Uniform 绑定自测：逐条核对 PerFrame / Dome PerObject 的字段来源是否照原版（server.cjs Ambience 映射 / bc() SH 映射）。
任何一条不满足就 FAIL，拦住出货。"""
import os
import re
import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else "ios/Sources"
RENDER = os.path.join(SRC, "MetalRenderer.swift")

ok = True


def need(cond, msg):
    global ok
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        ok = False


def main():
    if not os.path.exists(RENDER):
        print(f"FAIL 找不到 {RENDER}")
        return 1
    s = open(RENDER, encoding="utf8").read()

    # 1) 穹顶淡出权重：fs 末段 alpha/颜色都吃它，必须是 0
    # 取关卡 EnvNode 的 skyFadeOut（洞穴关原版就靠它把天空淡出），缺省必须回落到 0，绝不允许写死 1
    need(re.search(r'sky\.u_skyFadeOut\s*=\s*envNum\("skyFadeOut",\s*0\)', s) is not None,
         "Dome u_skyFadeOut = envNum(skyFadeOut, 0)（1 会把整块穹顶压黑）")
    need("sky.u_skyFadeOut = 1" not in s, "没有残留 u_skyFadeOut = 1")

    # 2) 原版 Ambience uniforms 映射
    need(re.search(r"u_fogDensityHeightDist\s*=\s*\(envNum\(\"fogDensity\".*envNum\(\"fogHeight\".*envNum\(\"drawDistance\"", s) is not None,
         "u_fogDensityHeightDist = [fogDensity, fogHeight, drawDistance]")
    need(re.search(r"u_sunSizeIntMoonPhase\s*=\s*\(envNum\(\"sunSize\".*envNum\(\"sunInt\".*envNum\(\"sunToMoon\".*envNum\(\"moonPhase\"", s, re.S) is not None,
         "u_sunSizeIntMoonPhase = [sunSize, sunInt, sunToMoon, moonPhase]")
    need(re.search(r"u_atmosphereDensity\s*=\s*envNum\(\"atmosphereDensity\"", s) is not None,
         "u_atmosphereDensity = env.atmosphereDensity")

    # 3) 常数天空的 SH 常数项：Y00 = 0.2820948，averageProbeColor = t0 * 3.5449078
    need("0.2820947766" in s, "SH 常数项系数 0.2820947766（bc() 的 t0）")
    need(re.search(r"u_probeShR0\s*=\s*\(averageSky\.x\s*\*\s*shK", s) is not None, "u_probeShR0 = averageSky.r * Y00")
    need(re.search(r"u_averageProbeColor\s*=\s*\(averageSky\.x", s) is not None, "u_averageProbeColor = averageSky")

    # 3.5) FogUpsample 必须按 IR 的 location_index 绑纹理（3..10），绑错会让原版 fs 读空 → 输出恒 1.0 → 整屏黑
    for idx, name in ((0, "scene"), (2, "fogTex"), (3, "atmoTex")):
        m = re.search(r"uenc\.setFragmentTexture\([^\n]*index: %d\)" % idx, s)
        need(m is not None, f"fogUpsampleFS {name} 绑在 texture {idx}")
    need(re.search(r"for i in 0...3 \{ uenc\.setFragmentSamplerState", s) is not None,
         "fogUpsampleFS sampler 0..3 全绑")
    need("var fogF = FUF(" in s or "FUF(" in s, "雾常量按 FU 结构绑 buffer(1)，不是 PerFrame 1584B")

    # 3.6) 顶点阶段也要绑 u_probeCube：RockFace / SkyDomeFade 的 vs 里 texture3+sampler3 是 cubemap
    terr = os.path.join(SRC, "TerrainPass.swift")
    dome = os.path.join(SRC, "DomePass.swift")
    if os.path.exists(terr):
        t = open(terr, encoding="utf8").read()
        need("let vsCube: Bool" in t, "TerrainPass 有 vsCube 家族标记")
        need(re.search(r'RockFaceRainShMeshDecal.*vsCube: true', t, re.S) is not None,
             "RockFaceRainShMeshDecal vsCube = true")
        need(re.search(r'RockFaceShMeshDecal.*vsCube: true', t, re.S) is not None,
             "RockFaceShMeshDecal vsCube = true")
        need("enc.setVertexTexture(probeCube, index: 3)" in t, "地形 vs 绑 u_probeCube 到 texture 3")
        need("enc.setVertexSamplerState(sampler, index: 3)" in t, "地形 vs 绑 sampler 到 sampler 3")
    else:
        need(False, "找不到 TerrainPass.swift")
    if os.path.exists(dome):
        d = open(dome, encoding="utf8").read()
        need("setVertexSamplerState(sampler, index: 3)" in d or "for i in 0...3 { enc.setVertexSamplerState" in d,
             "穹顶 vs sampler 覆盖 index 3（原版声明在 sampler(3)）")
    else:
        need(False, "找不到 DomePass.swift")

    # 4) 日志不许每帧刷（真机 boot.log 已被刷爆，掩盖其它信息）
    need(re.search(r"if frameIdx == 0 \{\s*\n\s*Boot\.log\(\"结构体尺寸", s) is not None,
         "结构体尺寸/偏移日志只打一次")

    print("PASS(uniform)" if ok else "FAIL(uniform)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
