import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { TgclFile } from '../../web/js/tgcl.js';
import { MeshFile } from '../../web/js/meshfile.js';
import { BakedLevel } from '../../web/js/bake.js';
import { collectTerrain, expandTerrain } from './terrain.mjs';

const DATA = process.argv[2] || '../work/run/files/Data';
const LEVEL = process.argv[3] || 'CandleSpace';
const OUT = process.argv[4] || 'native/Assets';

const fieldValue = (node, name) => {
  const f = (node.fields || []).find((x) => x.name === name);
  if (!f) return undefined;
  let v = f.value;
  if (v && typeof v === 'object' && !Array.isArray(v)) v = v.uint ?? v.float ?? v.value;
  return v;
};
const guidOf = (node) => { const f = (node.fields || []).find((x) => x.name === 'bstGuid'); return f ? Number(f.value?.uint ?? f.value) : undefined; };
const meshMatrix = (node) => {
  const m = (node.fields || []).find((f) => f.name === 'transform' && f.kind === 'matrix4');
  return m && Array.isArray(m.value) && m.value.length === 16 ? new Float32Array(m.value) : null;
};

function buildPalette(tgcl) {
  const map = new Map();
  for (const n of tgcl.nodes) {
    if (n.className !== 'LevelMaterial') continue;
    const idx = fieldValue(n, 'material');
    const color = fieldValue(n, 'baseColor') || [0.5, 0.5, 0.5, 1];
    const params = {};
    const sp = (n.fields || []).find((f) => f.name === 'shaderParams');
    for (const ch of sp?.children || []) {
      const get = (name) => {
        const f = (ch.children || []).find((x) => x.name === name);
        if (!f) return undefined;
        let v = f.value;
        if (v && typeof v === 'object' && !Array.isArray(v)) v = v.uint ?? v.float ?? v.value;
        return v;
      };
      const param = get('name');
      if (typeof param !== 'string') continue;
      if (param === 'u_diffuse1Tex') params.diffuse1 = get('tex');
      else if (param === 'u_diffuse2Tex') params.diffuse2 = get('tex');
      else if (param === 'u_normTex') params.norm = get('tex');
      else if (param === 'u_lightTex') params.light = get('tex');
      else if (param === 'u_selfLit') params.selfLit = get('vec');
      else if (param === 'u_normTexScale') params.normScale = Array.isArray(get('vec')) ? get('vec')[0] : undefined;
      else if (param === 'u_diffuse1TexScale') params.scale = Array.isArray(get('vec')) ? get('vec')[0] : undefined;
      else if (param === 'u_diffuseColor') { const v = get('vec'); if (Array.isArray(v)) params.color = v; }
    }
    map.set(idx, { color, ...params });
  }
  return map;
}

const levelDir = join(DATA, 'Levels', LEVEL);
const tgcl = new TgclFile(new Uint8Array(readFileSync(join(levelDir, 'Objects.level.bin'))));
const bakedPath = join(levelDir, 'BstBaked.meshes');
const baked = existsSync(bakedPath) ? new BakedLevel(new Uint8Array(readFileSync(bakedPath))) : null;
const pal = buildPalette(tgcl);

const perMesh = new Map();
for (const n of tgcl.nodes) {
  if (n.className !== 'SetMeshShaderParam') continue;
  const target = Number(fieldValue(n, 'meshes'));
  const uniform = String(fieldValue(n, 'uniformName') || '').trim();
  if (!uniform || !Number.isFinite(target)) continue;
  const rec = perMesh.get(target) || {};
  const f4 = fieldValue(n, 'valFloat4');
  if (uniform === 'diffuseColor' && Array.isArray(f4)) rec.diffuseColor = f4.slice(0, 3);
  perMesh.set(target, rec);
}

// 海平面：关卡 TerrainBlobGroup 的 cutoffLevel（seaLevelCutoff=1 时就是海面高度）
let seaLevel = -5.0;
for (const n of tgcl.nodes) {
  if (n.className !== 'TerrainBlobGroup') continue;
  const f = (n.fields || []).find((x) => x.name === 'cutoffLevel');
  const v = f?.value;
  const num = v && typeof v === 'object' ? (v.float ?? v.uint) : v;
  if (Number.isFinite(num)) seaLevel = num;
  break;
}

// 环境（原版烘焙用的 Ambience 参数，取自关卡 EnvNode / SetEnvDefault）
function readEnv(tgcl) {
  const node = tgcl.nodes.find((n) => n.className === 'EnvNode') || tgcl.nodes.find((n) => n.className === 'SetEnvDefault');
  const out = {};
  if (!node) return out;
  const pick = (name) => {
    const f = (node.fields || []).find((x) => x.name === name);
    if (!f) return undefined;
    const v = f.value;
    if (Array.isArray(v)) return v;
    if (v && typeof v === 'object') {
      if ('float' in v || 'uint' in v) return v.float ?? v.uint;
      if ('r' in v) return [v.r, v.g, v.b, v.a ?? 1];
    }
    return v;
  };
  for (const k of ['tintTop', 'tintBot', 'tintMidTop', 'tintMidMid', 'tintMidBot', 'sunColor',
                   'sunInt', 'sunAngleXZ', 'sunAngleY', 'sunSize', 'exposure', 'bloomIntensity',
                   'fogDensity', 'fogHeight', 'fogVolumeIntensity',
                   'pointColor', 'pointIntensity']) {
    const v = pick(k);
    if (v !== undefined) out[k] = v;
  }
  return out;
}
const envNode = readEnv(tgcl);

/** Level 的 PointLight 节点 -> 光簇输入（原版 editor 的 AmbiencePointLight 参数） */
function buildPointLights(tgcl, env) {
  const col = Array.isArray(env.pointColor) ? env.pointColor.slice(0, 3) : [1, 0.85, 0.6];
  const inten = Number(env.pointIntensity ?? 1);
  const out = [];
  for (const n of tgcl.nodes || []) {
    if (n.className !== 'PointLight') continue;
    const t = (n.fields || []).find((f) => f.name === 'transform');
    if (!t || !Array.isArray(t.value)) continue;
    const sx = Math.hypot(t.value[0], t.value[1], t.value[2]);
    out.push({
      pos: [t.value[12], t.value[13], t.value[14]],
      radius: Math.max(1, sx * 1.6),
      color: col.map((c) => c * inten),
      sharp: 0.35,
    });
  }
  return out;
}
const lights = buildPointLights(tgcl, envNode);
console.log('pointLights', lights.length, JSON.stringify(lights.slice(0, 3)));

const cache = new Map();
function loadMesh(name) {
  if (cache.has(name)) return cache.get(name);
  let mesh = null;
  for (const cand of [name, name + '_CompOcc']) {
    const p = join(DATA, 'Meshes', 'Bin', cand + '.mesh');
    if (existsSync(p)) { mesh = new MeshFile(new Uint8Array(readFileSync(p)), cand).first; break; }
  }
  cache.set(name, mesh);
  return mesh;
}

const f32 = [], lightBuf = [], colBuf = [], uvBuf = [], indices = [], ranges = [];
// Beamo：体积光遮挡体（原版用 FogVolume 的 shader 画它们，正面写正、背面写负）
const bPos = [], bIdx = [], beamos = [];
const stride = 72;
const textures = new Set();
const overall = [Infinity, Infinity, Infinity, -Infinity, -Infinity, -Infinity];
const focus = [Infinity, Infinity, Infinity, -Infinity, -Infinity, -Infinity];
let vbase = 0, ibase = 0;

for (const node of tgcl.nodes) {
  if (node.className !== 'LevelMesh') continue;
  const res = fieldValue(node, 'resourceName');
  if (typeof res !== 'string' || !res) continue;
  // 原版可见性规则（LevelMesh 的 render / visibleInWorld 字段）：不可见的辅助体（编辑器背景壳等）不画
  const renderFlag = fieldValue(node, 'render');
  if (Number(renderFlag) === 0) continue;
  // 星座星场（ConstellationAchievementStarField）也是 LevelMesh，材质同样是 Mesh，原版会画
  if (!/^[\w .+()-]+$/.test(res)) continue;
  const mesh = loadMesh(res);
  const model = meshMatrix(node);
  if (!mesh || !model) continue;

  const b = mesh.bounds;
  const sc = Math.hypot(model[0], model[1], model[2]);
  const span = Math.max(Math.abs(b[3] - b[0]), Math.abs(b[4] - b[1]), Math.abs(b[5] - b[2]))
    * Math.max(sc, Math.hypot(model[4], model[5], model[6]), Math.hypot(model[8], model[9], model[10]));
  if (span > 1000) continue;
  if (/^Cube$/i.test(res) && mesh.positions.length === 72) continue;

  const guid = guidOf(node);
  const record = baked && guid ? baked.forGuid(guid) : null;
  const lights = record ? BakedLevel.expand(record, mesh) : null;
  const matIdx = fieldValue(node, 'material');
  const entry = pal.get(matIdx) || { color: [0.5, 0.5, 0.5, 1] };
  const ov = perMesh.get(node.id) || {};
  const color = ov.diffuseColor ? [...ov.diffuseColor, Number(entry.color?.[3] ?? 1)] : entry.color;
  const uvScale = Number(entry.scale) || 1;

  const n = mesh.vertexCount;
  const m = model;
  const det = m[0] * (m[5] * m[10] - m[6] * m[9]) - m[4] * (m[1] * m[10] - m[2] * m[9]) + m[8] * (m[1] * m[6] - m[2] * m[5]) || 1;
  const inv = new Float32Array([
    (m[5] * m[10] - m[6] * m[9]) / det, -(m[1] * m[10] - m[2] * m[9]) / det, (m[1] * m[6] - m[2] * m[5]) / det,
    -(m[4] * m[10] - m[6] * m[8]) / det, (m[0] * m[10] - m[2] * m[8]) / det, -(m[0] * m[6] - m[2] * m[4]) / det,
    (m[4] * m[9] - m[5] * m[8]) / det, -(m[0] * m[9] - m[1] * m[8]) / det, (m[0] * m[5] - m[1] * m[4]) / det,
  ]);

  // 星场/天空这类远景不参与取景（原版编辑器取景也是按前景）
  const skipFrame = /StarField|Constellation/i.test(res);
  let imn = [Infinity, Infinity, Infinity], imx = [-Infinity, -Infinity, -Infinity];
  for (let k = 0; k < n; k++) {
    const x = mesh.positions[k * 3], y = mesh.positions[k * 3 + 1], z = mesh.positions[k * 3 + 2];
    const wx = m[0] * x + m[4] * y + m[8] * z + m[12];
    const wy = m[1] * x + m[5] * y + m[9] * z + m[13];
    const wz = m[2] * x + m[6] * y + m[10] * z + m[14];
    f32.push(wx, wy, wz);
    if (!skipFrame) {
      imn[0] = Math.min(imn[0], wx); imn[1] = Math.min(imn[1], wy); imn[2] = Math.min(imn[2], wz);
      imx[0] = Math.max(imx[0], wx); imx[1] = Math.max(imx[1], wy); imx[2] = Math.max(imx[2], wz);
    }
    if (!skipFrame) {
      overall[0] = Math.min(overall[0], wx); overall[1] = Math.min(overall[1], wy); overall[2] = Math.min(overall[2], wz);
      overall[3] = Math.max(overall[3], wx); overall[4] = Math.max(overall[4], wy); overall[5] = Math.max(overall[5], wz);
    }

    const nx = mesh.normals[k * 3], ny = mesh.normals[k * 3 + 1], nz = mesh.normals[k * 3 + 2];
    const tnx = inv[0] * nx + inv[3] * ny + inv[6] * nz;
    const tny = inv[1] * nx + inv[4] * ny + inv[7] * nz;
    const tnz = inv[2] * nx + inv[5] * ny + inv[8] * nz;
    const tl = Math.hypot(tnx, tny, tnz) || 1;
    f32.push(tnx / tl, tny / tl, tnz / tl);
    // 顶点色（原版 a_color，来自 positions 尾部的 4 字节）
    colBuf.push(mesh.colors[k * 4], mesh.colors[k * 4 + 1], mesh.colors[k * 4 + 2], mesh.colors[k * 4 + 3]);
    // 原版 a_uv0 / a_uv1 各是 vec4：uv01.xy = diffuse1 uv，uv01.zw = lightmap uv，uv23.zw = diffuse2 uv
    for (let q = 0; q < 4; q++) uvBuf.push(mesh.uvs[k * 8 + q]);
    for (let q = 0; q < 4; q++) uvBuf.push(mesh.uvs[k * 8 + 4 + q]);
    if (lights) lightBuf.push(lights[k * 12], lights[k * 12 + 1], lights[k * 12 + 2], lights[k * 12 + 3], lights[k * 12 + 4], lights[k * 12 + 5], lights[k * 12 + 6], lights[k * 12 + 7], lights[k * 12 + 8], lights[k * 12 + 9], lights[k * 12 + 10], lights[k * 12 + 11]);
    else lightBuf.push(110, 105, 100, 255, 0, 0, 0, 255, 0, 0, 0, 255);
  }
  for (let t = 0; t < mesh.indices.length; t++) indices.push(mesh.indices[t] + vbase);

  ranges.push({
    start: ibase, count: mesh.indices.length, name: res, material: matIdx,
    min: imn, max: imx, color: color.slice(0, 4),
    texture: entry.diffuse1 || null, texture2: entry.diffuse2 || null, uvScale,
    normTex: entry.norm || null, lightTex: entry.light || null, normScale: Number(entry.normScale ?? 1),
    selfLit: entry.selfLit || null,
  });
  if (entry.diffuse1) textures.add(entry.diffuse1);
  if (entry.diffuse2) textures.add(entry.diffuse2);
  if (entry.norm) textures.add(entry.norm);
  if (entry.light) textures.add(entry.light);

  // 取景只认实体道具：小的 DCube 装饰块和平面不参与
  const solid = !/^(DCube|Plane|Sky|Cloud|Cube)$/i.test(res) && mesh.indices.length >= 300;
  if (solid) {
    focus[0] = Math.min(focus[0], imn[0]); focus[1] = Math.min(focus[1], imn[1]); focus[2] = Math.min(focus[2], imn[2]);
    focus[3] = Math.max(focus[3], imx[0]); focus[4] = Math.max(focus[4], imx[1]); focus[5] = Math.max(focus[5], imx[2]);
  }
  vbase += n; ibase += mesh.indices.length;
}

mkdirSync(join(OUT, 'Data', 'Images', 'Bin'), { recursive: true });
let missing = 0;
for (const t of textures) {
  const src = join(DATA, 'Images', 'Bin', t + '.png');
  if (existsSync(src)) copyFileSync(src, join(OUT, 'Data', 'Images', 'Bin', t + '.png'));
  else { missing++; console.warn('缺贴图', t); }
}

/*terrain*/
// 用关卡 TerrainBlob / TerrainBlobPrefab 的原版参数生成地形（形状由参数推出，不是另编一套）
{
  const { blobs, group } = collectTerrain(tgcl, join(DATA, 'BlobPrefabs'));
  const T = expandTerrain(blobs);
  if (T.pos.length) {
    const tbase = vbase;
    for (const f of T.pos) f32.push(f);
    for (let i = 0; i < T.pos.length / 3; i++) lightBuf.push(118, 116, 110, 255, 0, 0, 0, 255, 0, 0, 0, 255);
    for (const t of T.idx) indices.push(t + tbase);
    vbase += T.pos.length / 3;
    for (const p of T.parts) {
      const entry = pal.get(p.material) || { color: [0.16, 0.20, 0.14, 1] };
      ranges.unshift({
        start: ibase, count: p.count, name: 'TerrainBlob', material: p.material,
        min: p.min, max: p.max, color: entry.color, texture: entry.diffuse1 || null,
        texture2: entry.diffuse2 || 'StoneGrunge2', uvScale: Number(entry.scale) || 1,
        normTex: entry.norm || null, lightTex: entry.light || null, normScale: Number(entry.normScale ?? 1),
        selfLit: entry.selfLit || null,
      });
      if (entry.diffuse1) textures.add(entry.diffuse1);
      if (entry.diffuse2) textures.add(entry.diffuse2);
      if (entry.norm) textures.add(entry.norm);
      if (entry.light) textures.add(entry.light);
      ibase += p.count;
    }
    // 没有 LevelMesh 的关卡（如 CarryLand3）仅靠地形定包围盒
    for (const p2 of T.parts) {
      for (let k = 0; k < 3; k++) {
        overall[k] = Math.min(overall[k], p2.min[k]);
        overall[k + 3] = Math.max(overall[k + 3], p2.max[k]);
        focus[k] = Math.min(focus[k], p2.min[k]);
        focus[k + 3] = Math.max(focus[k + 3], p2.max[k]);
      }
    }
    console.log('terrain blobs', blobs.length, 'tris', T.idx.length / 3);
  } else {
    console.log('terrain blobs 0');
  }
}

const vcount = f32.length / 6;
// ---- Beamo 体积：只取网格与变换，不需要材质/uv/烘焙光 ----
let bvbase = 0;
for (const n of tgcl.nodes) {
  if (n.className !== 'Beamo') continue;
  const res = fieldValue(n, 'meshName');
  const model = meshMatrix(n);
  if (typeof res !== 'string' || !model) continue;
  const mesh = loadMesh(res);
  if (!mesh) continue;
  const bstart = bIdx.length;
  const nv = mesh.vertexCount;
  const m = model;
  for (let k = 0; k < nv; k++) {
    const x = mesh.positions[k * 3], y = mesh.positions[k * 3 + 1], z = mesh.positions[k * 3 + 2];
    bPos.push(m[0]*x + m[4]*y + m[8]*z + m[12], m[1]*x + m[5]*y + m[9]*z + m[13], m[2]*x + m[6]*y + m[10]*z + m[14]);
  }
  for (const t of mesh.indices) bIdx.push(t + bvbase);
  bvbase += nv;
  beamos.push({ start: bstart, count: mesh.indices.length, mesh: res,
                skirt: Number(fieldValue(n, 'skirtHeight')) || 0,
                density: Number(fieldValue(n, 'density')) || 0,
                blurLighting: Number(fieldValue(n, 'blurLighting')) || 0 });
}
if (beamos.length) {
  writeFileSync(join(OUT, LEVEL + '.beamo.verts'), Buffer.from(Float32Array.from(bPos).buffer));
  writeFileSync(join(OUT, LEVEL + '.beamo.idx'), Buffer.from(Uint32Array.from(bIdx).buffer));
}
console.log('beamo volumes', beamos.length, 'tris', bIdx.length / 3);

const out = Buffer.alloc(vcount * stride);
for (let i = 0; i < vcount; i++) {
  for (let k = 0; k < 6; k++) out.writeFloatLE(f32[i * 6 + k], i * stride + k * 4);   // pos3 + nrm3
  for (let k = 0; k < 4; k++) out[i * stride + 24 + k] = colBuf[i * 4 + k];          // a_color rgba8
  for (let k = 0; k < 8; k++) out.writeFloatLE(uvBuf[i * 8 + k], i * stride + 28 + k * 4); // uv01 / uv23
  for (let k = 0; k < 12; k++) out[i * stride + 60 + k] = lightBuf[i * 12 + k];      // light0/1/2
}

writeFileSync(join(OUT, LEVEL + '.verts'), out);
writeFileSync(join(OUT, LEVEL + '.idx'), Buffer.from(Uint32Array.from(indices).buffer));
const clean = (o) => {
  if (typeof o === 'number') return Number.isFinite(o) ? o : 0;
  if (o === null || o === undefined) return 0;
  if (Array.isArray(o)) return o.map(clean);
  if (typeof o === 'object') {
    const r = {};
    for (const [k, v] of Object.entries(o)) {
      if (v === null || v === undefined) continue;
      r[k] = clean(v);
    }
    return r;
  }
  return o;
};
writeFileSync(join(OUT, LEVEL + '.json'), JSON.stringify(clean({
  level: LEVEL, seaLevel, env: envNode, lights, beamos, vertices: vcount, indices: indices.length, stride,
  layout: { pos: 0, normal: 12, color: 24, uv0: 28, uv1: 44, light0: 60, light1: 64, light2: 68 },
  bounds: overall, focus, ranges,
}), null, 1));
console.log(LEVEL, 'verts', vcount, 'idx', indices.length, 'ranges', ranges.length, 'textures', textures.size, 'missing', missing);
console.log('bounds', overall.map((v) => v.toFixed(1)).join('/'), 'focus', focus.map((v) => v.toFixed(1)).join('/'));
