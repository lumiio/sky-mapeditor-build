#!/usr/bin/env python3
"""出包前的地形几何自测：用 App 里那套相机/矩阵参数，把 <level>.terrain.bin 真的投影一遍。

复刻 Swift 端 MetalRenderer 的相机：
  dist = radius*1.15*zoom, eye = center + (cos el cos az, sin el, cos el sin az)*dist
  proj = perspective(50°, w/h, near=max(dist*0.01,0.05), far=dist*20)
  vp = proj * lookAt(eye, center, up)
判据：进屏顶点占比 ≥ 5%，否则说明"相机对着空气"，直接把包拦下来。

用法：python3 qa/geo_preview.py <Assets 目录> <关卡名> [输出 png]
"""
import sys, os, json, struct
import numpy as np
from PIL import Image

W, H = 1170, 2532
FOVY = np.radians(50.0)
AZ, EL, ZOOM = 2.10, 0.28, 1.0


def look_at(e, c, up):
    z = e - c; z = z / np.linalg.norm(z)
    x = np.cross(up, z); x = x / np.linalg.norm(x)
    y = np.cross(z, x)
    m = np.eye(4)
    m[0, :3] = x; m[1, :3] = y; m[2, :3] = z
    m[0, 3] = -x @ e; m[1, 3] = -y @ e; m[2, 3] = -z @ e
    return m


def perspective(fovy, aspect, near, far):
    y = 1.0 / np.tan(fovy / 2.0); x = y / aspect
    m = np.zeros((4, 4))
    m[0, 0] = x; m[1, 1] = y
    m[2, 2] = far / (near - far); m[2, 3] = (far * near) / (near - far)
    m[3, 2] = -1.0
    return m


def load_level(assets, level):
    raw = open(os.path.join(assets, level + ".terrain.bin"), "rb").read()
    vc, ic = struct.unpack_from("<II", raw, 0)
    verts = np.frombuffer(raw, dtype="<f4", count=vc * 9, offset=8).reshape(vc, 9)[:, :3].astype(np.float64)
    idx = np.frombuffer(raw, dtype="<u4", count=ic, offset=8 + vc * 36).reshape(-1, 3)
    man = json.load(open(os.path.join(assets, level + ".json"), encoding="utf-8"))
    f = man["focus"]
    center = np.array([(f[0] + f[3]) / 2, (f[1] + f[4]) / 2, (f[2] + f[5]) / 2])
    radius = max(1.0, np.linalg.norm([f[3] - f[0], f[4] - f[1], f[5] - f[2]]) / 2)
    env = man.get("env") or {}
    sun_el = float(np.radians((env.get("sunAngleY") or {}).get("arr", [55])[0] if isinstance(env.get("sunAngleY"), dict) else 55))
    return verts, idx, center, radius, env


def main():
    assets, level = sys.argv[1], sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else f"/tmp/qa-preview-{level}.png"
    verts, idx, center, radius, env = load_level(assets, level)

    dist = radius * 1.15 * ZOOM
    eye = center + np.array([np.cos(EL) * np.cos(AZ), np.sin(EL), np.cos(EL) * np.sin(AZ)]) * dist
    fwd = center - eye; fwd /= np.linalg.norm(fwd)
    up = np.array([0.0, 1.0, 0.0])
    right = np.cross(fwd, up); right /= np.linalg.norm(right)
    cam_up = np.cross(right, fwd)
    near = max(dist * 0.01, 0.05); far = dist * 20
    vp = perspective(FOVY, W / H, near, far) @ look_at(eye, center, cam_up)

    ph = np.hstack([verts, np.ones((len(verts), 1))])
    clip = ph @ vp.T
    w = clip[:, 3]
    safe = np.where(np.abs(w) < 1e-9, 1e-9, w)
    ndc = clip[:, :3] / safe[:, None]
    inside = (w > 0) & (ndc[:, 0] >= -1) & (ndc[:, 0] <= 1) & (ndc[:, 1] >= -1) & (ndc[:, 1] <= 1) & (ndc[:, 2] >= 0) & (ndc[:, 2] <= 1)
    frac = inside.mean()

    # 光栅：z-buffer + 平面法线着色，仅看轮廓是否正常
    img = np.zeros((H, W, 3), dtype=np.uint8)
    zbuf = np.full((H, W), np.inf)
    tri = idx[inside[idx].all(axis=1)] if len(idx) else idx
    if len(tri) == 0:
        tri = idx
    sx = (ndc[:, 0] * 0.5 + 0.5) * W
    sy = (0.5 - ndc[:, 1] * 0.5) * H
    sun_dir = np.array([0.3, 0.8, 0.2]); sun_dir /= np.linalg.norm(sun_dir)
    nrm = np.zeros_like(verts)
    nrm[:, 1] = 1.0

    for a, b, c in tri[::max(1, len(tri) // 60000)]:
        xs = np.array([sx[a], sx[b], sx[c]]); ys = np.array([sy[a], sy[b], sy[c]]); zs = np.array([ndc[a, 2], ndc[b, 2], ndc[c, 2]])
        if not np.all(np.isfinite(xs)) or not np.all(np.isfinite(ys)):
            continue
        x0, x1 = int(max(0, np.floor(xs.min()))), int(min(W - 1, np.ceil(xs.max())))
        y0, y1 = int(max(0, np.floor(ys.min()))), int(min(H - 1, np.ceil(ys.max())))
        if x1 < x0 or y1 < y0:
            continue
        if (x1 - x0) * (y1 - y0) > 400000:
            continue
        yy, xx = np.mgrid[y0:y1 + 1, x0:x1 + 1]
        d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if d < 0:
            continue   # 顺时针为背面：视口 y 向下，正面积才是正面（对应 Metal 默认 .back 剔除）
        l0 = ((ys[1] - ys[2]) * (xx - xs[2]) + (xs[2] - xs[1]) * (yy - ys[2])) / d
        l1 = ((ys[2] - ys[0]) * (xx - xs[2]) + (xs[0] - xs[2]) * (yy - ys[2])) / d
        l2 = 1 - l0 - l1
        m = (l0 >= 0) & (l1 >= 0) & (l2 >= 0)
        if not m.any():
            continue
        z = l0 * zs[0] + l1 * zs[1] + l2 * zs[2]
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        upd = m & (z < sub)
        if not upd.any():
            continue
        v0 = verts[b] - verts[a]; v1 = verts[c] - verts[a]
        n = np.cross(v0, v1); nl = np.linalg.norm(n)
        n = n / nl if nl > 0 else np.array([0, 1, 0])
        shade = 0.25 + 0.75 * abs(float(n @ sun_dir))
        col = np.array([90, 120, 90]) * shade
        sub[upd] = z[upd]
        img[y0:y1 + 1, x0:x1 + 1][upd] = col.astype(np.uint8)

    Image.fromarray(img).save(out)
    cover = float((zbuf < np.inf).mean())
    print(f"{level}: vertices={len(verts)} tris={len(idx)} 顶点进屏占比={frac*100:.1f}% 屏幕覆盖={cover*100:.1f}% radius={radius:.1f} dist={dist:.1f} -> {out}")
    if frac < 0.05 or cover < 0.05:
        print("GEO FAIL: 相机视野里几乎没有地形")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
