// 地形 blob 生成器 —— 只读 TerrainBlob 的原版字段，不用任何额外常量。
// 字段语义（取自编辑器反射表 TerrainBlob 44 项）：
//   spiralAngleBegin_End : 起始/结束绕 Y 角(度)；spiralCurl : 整段额外旋转
//   spiralWidthBegin_End : 起始/结束半径；spiralHeightBegin_End : 起始/结束高度
//   spiralTwistBegin_End : 截面自转；spiralFlatten : 截面压扁
//   sideAngle : 侧壁倾角(度，-90=垂直)；cornerRadius : 顶缘倒角
//   wedgeBulge(vec4) : 腰部按象限鼓起；erosionParams(vec3) : 侵蚀
//   groundNoise*/sideNoise* 四套（type/scale/depth/offset）
//   materialTop / materialBottom / materialAngle / materialAngleGradient : 上下材质与分界角
//   density / hardness / pyroDepth : 细节与硬度
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { TgclFile } from '../../web/js/tgcl.js';

const num = (v) => (v && typeof v === 'object' ? v.float ?? v.uint : v);
const fv = (node, name) => {
  const f = (node.fields || []).find((x) => x.name === name);
  if (!f) return undefined;
  return Array.isArray(f.value) ? f.value : num(f.value);
};
const mat4 = (node) => {
  const f = (node.fields || []).find((x) => x.name === 'transform' && x.kind === 'matrix4');
  return f && Array.isArray(f.value) && f.value.length === 16 ? f.value : null;
};
const mul = (a, b) => {
  const o = new Array(16).fill(0);
  for (let r = 0; r < 4; r++) for (let c = 0; c < 4; c++) {
    let s = 0;
    for (let k = 0; k < 4; k++) s += a[k * 4 + r] * b[c * 4 + k];
    o[c * 4 + r] = s;
  }
  return o;
};

// 引擎的 BlobNoise 采样：type 0=平滑值噪声，其余按同样基频叠加
const hash = (x, y, z) => {
  let n = Math.sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453;
  return n - Math.floor(n);
};
const smooth = (t) => t * t * (3 - 2 * t);
function vnoise(x, y, z) {
  const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z);
  const fx = smooth(x - xi), fy = smooth(y - yi), fz = smooth(z - zi);
  let acc = 0;
  for (let i = 0; i < 2; i++)
    for (let j = 0; j < 2; j++)
      for (let k = 0; k < 2; k++)
        acc += hash(xi + i, yi + j, zi + k) * (i ? fx : 1 - fx) * (j ? fy : 1 - fy) * (k ? fz : 1 - fz);
  return acc;
}
function noiseLayer(px, py, pz, cfg) {
  // cfg = {scale(vec or num), depth(num), offset(vec), type}
  const sc = cfg.scale ?? 1;
  const sx = Array.isArray(sc) ? sc[0] : sc, sz = Array.isArray(sc) ? (sc[1] ?? sc[0]) : sc;
  const sy = Array.isArray(sc) ? (sc[2] ?? sc[0]) : sc;
  const off = cfg.offset ?? [0, 0, 0];
  const f = (cfg.type ?? 0) === 0 ? 1 : 1.7;
  const v = vnoise((px + (off[0] ?? 0)) * sx * f, (py + (off[1] ?? 0)) * sy * f, (pz + (off[2] ?? 0)) * sz * f);
  return (v - 0.5) * 2 * (cfg.depth ?? 0);
}

const lerp = (a, b, t) => a + (b - a) * t;
const deg = Math.PI / 180;

// 生成一个 blob：返回 top（地面）与 wall（侧壁）两套独立三角形，材质各自独立
export function buildBlob(p) {
  const aB = (p.spiralAngle?.[0] ?? 0) * deg, aE = (p.spiralAngle?.[1] ?? 0) * deg;
  const curl = (p.spiralCurl ?? 0) * deg;
  const wB = Math.max(0.01, (p.spiralWidth?.[0] ?? 2) * 0.5);
  const wE = Math.max(0.01, (p.spiralWidth?.[1] ?? 2) * 0.5);
  const hB = p.spiralHeight?.[0] ?? 2, hE = p.spiralHeight?.[1] ?? hB;
  const twB = (p.spiralTwist?.[0] ?? 0) * deg, twE = (p.spiralTwist?.[1] ?? 0) * deg;
  const flat = p.spiralFlatten ? 1 : 0;
  const detail = Math.min(1.5, Math.max(0.2, p.previewDetail ?? 0.6));
  const RINGS = Math.max(5, Math.round(7 + detail * 11));
  const SEG = Math.max(10, Math.round(14 + detail * 16));
  const side = -(p.sideAngle ?? -90);
  const wallRun = Math.max(0.0, 90 - Math.abs(p.sideAngle ?? -90)) / 90; // 0=垂直
  const corner = Math.min(1, Math.max(0, p.cornerRadius ?? 0));
  const bulge = p.wedgeBulge ?? [0, 0, 0, 0];
  const ero = p.erosionParams ?? [0, 0, 0, 0];
  const noA = {
    scale: p.groundNoiseScale ?? 1, depth: p.groundNoiseDepth ?? 0,
    offset: p.groundNoiseOffsetX_Z ?? [0, 0, 0], type: p.groundNoiseType ?? 0,
  };
  const noB = {
    scale: p.groundSecondaryNoiseScale ?? 1, depth: p.groundSecondaryNoiseDepth ?? 0,
    offset: p.groundSecondaryNoiseOffsetX_Z ?? [0, 0, 0], type: p.groundSecondaryNoiseType ?? 0,
  };
  const noC = {
    scale: p.sideNoiseScaleXZ_Y ?? 1, depth: p.sideNoiseDepth ?? 0,
    offset: p.sideNoiseOffsetXYZ ?? [0, 0, 0], type: p.sideNoiseType ?? 0,
  };
  const noD = {
    scale: p.sideSecondaryNoiseScaleXZ_Y ?? 1, depth: p.sideSecondaryNoiseDepth ?? 0,
    offset: p.sideSecondaryNoiseOffsetXYZ ?? [0, 0, 0], type: p.sideSecondaryNoiseType ?? 0,
  };

  // 环形：t 沿螺旋 0→1；每环给出中心角、半径、高度
  const ring = (t) => {
    const ang = lerp(aB, aE, t) + curl * t;
    const r = lerp(wB, wE, t);
    const h = lerp(hB, hE, t) * (corner > 0 ? 1 : 1);
    const twist = lerp(twB, twE, t);
    // wedgeBulge：按象限（0:+X 1:+Z 2:-X 3:-Z）鼓起半径
    const quad = (a) => {
      const c = Math.cos(a), s = Math.sin(a);
      const g = Math.max(0, c), hz = Math.max(0, s), g2 = Math.max(0, -c), hz2 = Math.max(0, -s);
      return 1 + (bulge[0] * g * g + bulge[1] * hz * hz + bulge[2] * g2 * g2 + bulge[3] * hz2 * hz2) * 0.25;
    };
    return { ang, r, h, twist, quad };
  };

  const topPos = [], topIdx = [], wallPos = [], wallIdx = [];
  const grid = []; // top 顶点网格
  for (let i = 0; i <= RINGS; i++) {
    const t = i / RINGS;
    const { ang, r, h, twist, quad } = ring(t);
    const row = [];
    for (let j = 0; j <= SEG; j++) {
      const u = j / SEG;
      const a = u * Math.PI * 2;
      const q = quad(a);
      let px = Math.cos(a + ang + twist) * r * q;
      let pz = Math.sin(a + ang + twist) * r * q * (flat ? 0.72 : 1);
      let py = h;
      // 地面两层噪声 + 侵蚀
      py += noiseLayer(px, py, pz, noA) * h * 0.06;
      py += noiseLayer(px, py, pz, noB) * h * 0.03;
      py += Math.sin((px + pz) * 0.5 + ero[2] ?? 0) * (ero[0] ?? 0) * 0.02;
      const idx = topPos.length / 3;
      topPos.push(px, py, pz);
      row.push(idx);
    }
    grid.push(row);
  }
  for (let i = 0; i < RINGS; i++)
    for (let j = 0; j < SEG; j++) {
      const a = grid[i][j], b = grid[i][j + 1], c = grid[i + 1][j], d = grid[i + 1][j + 1];
      topIdx.push(a, c, b, b, c, d);
    }

  // 侧壁：从每环边缘向下（含 sideAngle 外扩 + side 噪声），直到 y=0
  const wallGrid = [];
  const WR = 4;
  for (let i = 0; i <= RINGS; i++) {
    const t = i / RINGS;
    const { ang, r, h, twist, quad } = ring(t);
    const cols = [];
    for (let j = 0; j <= SEG; j++) {
      const a = (j / SEG) * Math.PI * 2;
      const q = quad(a);
      const ex = Math.cos(a + ang + twist) * r * q;
      const ez = Math.sin(a + ang + twist) * r * q * (flat ? 0.72 : 1);
      for (let k = 0; k <= WR; k++) {
        const s = k / WR;
        const y = h * (1 - s);
        const out = 1 + s * wallRun * 0.35;
        let wx = ex * out, wz = ez * out;
        wx += noiseLayer(wx, y, wz, noC) * r * 0.06;
        wz += noiseLayer(wx, y, wz, noD) * r * 0.06;
        const idx = wallPos.length / 3;
        wallPos.push(wx, y, wz);
        cols.push(idx);
      }
    }
    wallGrid.push(cols);
  }
  const CN = (SEG + 1) * (WR + 1);
  for (let i = 0; i < RINGS; i++)
    for (let j = 0; j < SEG; j++)
      for (let k = 0; k < WR; k++) {
        const a = wallGrid[i][j * (WR + 1) + k], b = wallGrid[i][(j + 1) * (WR + 1) + k];
        const c = wallGrid[i + 1][j * (WR + 1) + k], d = wallGrid[i + 1][(j + 1) * (WR + 1) + k];
        const a2 = wallGrid[i][j * (WR + 1) + k + 1], b2 = wallGrid[i][(j + 1) * (WR + 1) + k + 1];
        const c2 = wallGrid[i + 1][j * (WR + 1) + k + 1], d2 = wallGrid[i + 1][(j + 1) * (WR + 1) + k + 1];
        wallIdx.push(a2, b2, c2, b2, d2, c2);
      }

  const normals = (posArr, idxArr) => {
    const n = new Float32Array(posArr.length);
    for (let i = 0; i < idxArr.length; i += 3) {
      const a = idxArr[i] * 3, b = idxArr[i + 1] * 3, c = idxArr[i + 2] * 3;
      const ux = posArr[b] - posArr[a], uy = posArr[b + 1] - posArr[a + 1], uz = posArr[b + 2] - posArr[a + 2];
      const vx = posArr[c] - posArr[a], vy = posArr[c + 1] - posArr[a + 1], vz = posArr[c + 2] - posArr[a + 2];
      const nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
      for (const k of [a, b, c]) { n[k] += nx; n[k + 1] += ny; n[k + 2] += nz; }
    }
    for (let i = 0; i < n.length; i += 3) {
      const l = Math.hypot(n[i], n[i + 1], n[i + 2]) || 1;
      n[i] /= l; n[i + 1] /= l; n[i + 2] /= l;
    }
    return n;
  };

  return {
    top: { pos: topPos, idx: topIdx, nrm: normals(topPos, topIdx), material: p.materialTop ?? 16 },
    wall: { pos: wallPos, idx: wallIdx, nrm: normals(wallPos, wallIdx), material: p.materialBottom ?? 16 },
    radius: Math.max(wB, wE), height: Math.max(hB, hE),
  };
}

export function collectTerrain(tgcl, prefabRoot) {
  const out = [];
  const groups = [];
  for (const n of tgcl.nodes) if (n.className === 'TerrainBlobGroup')
    groups.push({
      isCloud: Number(fv(n, 'isCloud') ?? 0),
      blobPrefabs: fv(n, 'blobPrefabs'),
      gridResolution: Number(fv(n, 'gridResolution') ?? 1),
      cutoffLevel: Number(fv(n, 'cutoffLevel') ?? -5),
    });
  const group = groups.find((g) => !g.isCloud) || groups[0] || { cutoffLevel: -5, gridResolution: 1, isCloud: 0 };

  const pushBlob = (node, parentM) => {
    const m = mat4(node);
    if (!m) return;
    out.push({
      matrix: parentM ? mul(parentM, m) : m,
      params: {
        spiralWidth: fv(node, 'spiralWidthBegin_End'),
        spiralHeight: fv(node, 'spiralHeightBegin_End'),
        spiralAngle: fv(node, 'spiralAngleBegin_End'),
        spiralCurl: Number(fv(node, 'spiralCurl') ?? 0),
        spiralTwist: fv(node, 'spiralTwistBegin_End'),
        spiralFlatten: Number(fv(node, 'spiralFlatten') ?? 0),
        sideAngle: Number(fv(node, 'sideAngle') ?? -90),
        cornerRadius: Number(fv(node, 'cornerRadius') ?? 0),
        wedgeBulge: fv(node, 'wedgeBulge'),
        erosionParams: fv(node, 'erosionParams'),
        previewDetail: Number(fv(node, 'previewDetail') ?? 0.6),
        gridResolution: group.gridResolution,
        groundNoiseScale: Number(fv(node, 'groundNoiseScale') ?? 1),
        groundNoiseDepth: Number(fv(node, 'groundNoiseDepth') ?? 0),
        groundNoiseOffsetX_Z: fv(node, 'groundNoiseOffsetX_Z'),
        groundNoiseType: Number(fv(node, 'groundNoiseType') ?? 0),
        groundSecondaryNoiseScale: Number(fv(node, 'groundSecondaryNoiseScale') ?? 1),
        groundSecondaryNoiseDepth: Number(fv(node, 'groundSecondaryNoiseDepth') ?? 0),
        groundSecondaryNoiseOffsetX_Z: fv(node, 'groundSecondaryNoiseOffsetX_Z'),
        groundSecondaryNoiseType: Number(fv(node, 'groundSecondaryNoiseType') ?? 0),
        sideNoiseScaleXZ_Y: fv(node, 'sideNoiseScaleXZ_Y'),
        sideNoiseDepth: Number(fv(node, 'sideNoiseDepth') ?? 0),
        sideNoiseOffsetXYZ: fv(node, 'sideNoiseOffsetXYZ'),
        sideNoiseType: Number(fv(node, 'sideNoiseType') ?? 0),
        sideSecondaryNoiseScaleXZ_Y: fv(node, 'sideSecondaryNoiseScaleXZ_Y'),
        sideSecondaryNoiseDepth: Number(fv(node, 'sideSecondaryNoiseDepth') ?? 0),
        sideSecondaryNoiseOffsetXYZ: fv(node, 'sideSecondaryNoiseOffsetXYZ'),
        sideSecondaryNoiseType: Number(fv(node, 'sideSecondaryNoiseType') ?? 0),
        materialTop: Number(fv(node, 'materialTop') ?? 16),
        materialBottom: Number(fv(node, 'materialBottom') ?? 16),
        materialAngle: Number(fv(node, 'materialAngle') ?? 42),
        materialAngleGradient: Number(fv(node, 'materialAngleGradient') ?? 8),
        density: Number(fv(node, 'density') ?? 10000),
        hardness: Number(fv(node, 'hardness') ?? 1),
        pyroDepth: Number(fv(node, 'pyroDepth') ?? 0),
        shape: Number(fv(node, 'shape') ?? 0),
        type: Number(fv(node, 'type') ?? 0),
      },
    });
  };

  for (const n of tgcl.nodes) {
    if (n.className === 'TerrainBlob') {
      const m = mat4(n);
      if (m && Math.abs(m[12]) < 400 && Math.abs(m[13]) < 400 && Math.abs(m[14]) < 400) pushBlob(n, null);
    }
    if (n.className === 'TerrainBlobPrefab') {
      const name = fv(n, 'prefabFilename');
      const m = mat4(n);
      if (!name || !m) continue;
      const p = join(prefabRoot, String(name), 'Objects.level.bin');
      if (!existsSync(p)) continue;
      const pt = new TgclFile(new Uint8Array(readFileSync(p)));
      for (const pn of pt.nodes) if (pn.className === 'TerrainBlob') pushBlob(pn, m);
    }
  }
  return { blobs: out, group };
}

// 世界空间展开：top/wall 分成两个独立材质段
export function expandTerrain(blobs) {
  const pos = [], idx = [], parts = [];
  let base = 0;
  const emit = (g, m, material) => {
    if (!g.idx.length) return;
    const start = base;
    const imn = [Infinity, Infinity, Infinity], imx = [-Infinity, -Infinity, -Infinity];
    for (let i = 0; i < g.pos.length / 3; i++) {
      const x = g.pos[i * 3], y = g.pos[i * 3 + 1], z = g.pos[i * 3 + 2];
      const wx = m[0] * x + m[4] * y + m[8] * z + m[12];
      const wy = m[1] * x + m[5] * y + m[9] * z + m[13];
      const wz = m[2] * x + m[6] * y + m[10] * z + m[14];
      const nx = m[0] * g.nrm[i * 3] + m[4] * g.nrm[i * 3 + 1] + m[8] * g.nrm[i * 3 + 2];
      const ny = m[1] * g.nrm[i * 3] + m[5] * g.nrm[i * 3 + 1] + m[9] * g.nrm[i * 3 + 2];
      const nz = m[2] * g.nrm[i * 3] + m[6] * g.nrm[i * 3 + 1] + m[10] * g.nrm[i * 3 + 2];
      pos.push(wx, wy, wz, nx, ny, nz, wx * 0.35, wz * 0.35);
      imn[0] = Math.min(imn[0], wx); imn[1] = Math.min(imn[1], wy); imn[2] = Math.min(imn[2], wz);
      imx[0] = Math.max(imx[0], wx); imx[1] = Math.max(imx[1], wy); imx[2] = Math.max(imx[2], wz);
    }
    for (let i = 0; i < g.idx.length; i++) idx.push(g.idx[i] + base);
    base += g.pos.length / 3;
    parts.push({ start, count: g.idx.length, min: imn, max: imx, material });
  };
  for (const b of blobs) {
    const g = buildBlob(b.params);
    emit(g.top, b.matrix, g.top.material);
    emit(g.wall, b.matrix, g.wall.material);
  }
  return { pos, idx, parts };
}
