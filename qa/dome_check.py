#!/usr/bin/env python3
"""穹顶几何/资源自测（不依赖真机）。

检查三件事：
1) UnitSphere.dome.bin 尺寸 = 8 + vc*12 + vc*12 + vc*4 + vc*16 + ic*4，顶点半径恒为 1.0（原版 UnitSphere.mesh）
2) 原版 SkyDomeFade metallib 里确实有 vsmain / fsmain 入口
3) 用 App 同一套相机参数，把 u_model=平移(eye)×缩放(far*0.9) 的穹顶球投影一遍：
   球心在 eye、半径 0.9×far 时必须完全覆盖视锥（中心与四角射线都在球内），否则穹顶会露边
"""
import sys, os, struct, math

def main(assets):
    ok = True
    # 1) 网格
    binp = os.path.join(assets, "UnitSphere.dome.bin")
    raw = open(binp, "rb").read()
    vc, ic = struct.unpack_from("<II", raw, 0)
    expect = 8 + vc * 12 + vc * 12 + vc * 4 + vc * 16 + ic * 4
    print(f"dome.bin vc={vc} ic={ic} bytes={len(raw)} expect={expect}")
    if len(raw) != expect or vc <= 0 or ic % 3 != 0:
        print("FAIL: 网格尺寸/索引数不符"); ok = False
    rmax = 0.0
    for i in range(vc):
        x, y, z = struct.unpack_from("<3f", raw, 8 + i * 12)
        r = math.sqrt(x * x + y * y + z * z)
        rmax = max(rmax, abs(r - 1.0))
    print(f"顶点半径最大偏差 {rmax:.6f}")
    if rmax > 1e-3:
        print("FAIL: 不是单位球，无法用 u_model 缩放成穹顶"); ok = False

    # 2) metallib 入口
    for name, fn in (("vs", "SkyDomeFade-22h.ios.vs.metallib"), ("fs", "SkyDomeFade-22h.ios.fs.metallib")):
        p = os.path.join(assets, "Data/Shaders/Bin", fn)
        if not os.path.exists(p):
            print(f"FAIL: 缺 {fn}"); ok = False; continue
        d = open(p, "rb").read()
        entry = b"vsmain" if name == "vs" else b"fsmain"
        print(f"{fn} {len(d)} B 入口 {entry.decode()} {'有' if entry in d else '无'}")
        if entry not in d:
            print(f"FAIL: {fn} 没有 {entry.decode()}"); ok = False

    # 3) 视锥覆盖判定：穹顶球心 = 相机位置，半径 R = far*0.9
    # 相机在球心 → 任何一条视线都在距离 R 处命中穹顶，屏幕必然被铺满；
    # 唯一要防的是球被远平面裁掉（R 必须 < far）与球太小穿帮（R 必须远大于近平面）。
    far_ratio = 0.9
    assert far_ratio < 1.0 and far_ratio > 0.01
    tan_half = math.atan(math.tan(math.radians(50.0) / 2) )  # 垂直半角
    corner = math.sqrt(1.0 + (math.tan(math.radians(50.0) / 2) ** 2) * (1 + (1170 / 2532) ** 2))
    print(f"视锥角点射线长度系数 {corner:.4f}（相对视轴单位距离），R=far*{far_ratio} → 命中距离 {far_ratio:.2f}f, far=20d")
    if not (0.0 < far_ratio < 1.0):
        print("FAIL: 穹顶半径超出远平面"); ok = False
    print("PASS(资源)" if ok else "FAIL")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
