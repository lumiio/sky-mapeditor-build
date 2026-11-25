# 逆向审计：APK 实测后的定稿格式与 ABI

本轮把 `Sky 地图编辑器.apk`（690,508,734 字节，sha1 `7a3351e6…`）真正拿到手并拆了：
dex、清单、原生库、`server.cjs`、666 个 GLSL、30 张图的真实 `Objects.level.bin` / `BstBaked.meshes` 全部对齐。

**结论：此前按对话整理的两处格式假设是错的，这里按编辑器自己的实现改正。** 所有数字都能用 `tools/reverse/` 里的脚本在 APK 资产上重现。

## 0. APK 结构

| 项 | 值 |
|---|---|
| 包名 / 版本 | `com.sky.editor` / `0.3.1-android-preview`（versionCode 5） |
| SDK | minSdk 26，targetSdk 35，`usesCleartextTraffic=true` |
| 权限 | 仅 `INTERNET`；`uses-feature android.hardware.vulkan.version` |
| dex | 15 个类 / 239 方法 / 20,912 字节 —— 纯壳：`MainActivity` + WebViewClient + 若干 Runnable 回调 |
| 原生库 | `libnode.so` 62.5MB、`libsky_vulkan.so` 183KB、`libglslang.so` 8MB、`libsky_spirv_opt.so` 4.6MB、`libSPIRV-Tools-shared.so` 1.9MB、`libsky_spirv_val.so` 1.8MB、`libc++_shared.so` |
| 运行时 | `assets/runtime/server.cjs` 1.76MB、`web/app.js` 1.4MB、`web/classes.json`（1063 个类）、`vulkan-shaders/<hash>/{vert.spv,frag.spv,manifest.json}`、`beamo-rsqrt-capability.bin` 16.7MB |
| 数据 | `assets/Data` 756MB：Audio 484MB、Levels 149MB（30 张图）、Meshes 70MB、Images 46MB、Shaders 3.7MB（666 个 `.vert/.frag` + `.osx.metallib`） |

`libsky_vulkan.so` 未 strip，导出 281 个函数，命令面与之前分析一致：

```
skyVulkanRun(FILE*,FILE*,FILE*,bool)
Renderer::Renderer() / description() / scene(uchar*,size_t)
Renderer::render(uint,uint,float*,float,bool,bool,bool)
Renderer::fastRender / fastComposition / fastCompositionUniforms
Renderer::viewportCore / viewportBackground / viewportMaterials / viewportAlpha
Renderer::viewportDrawOrder / viewportDrawVisibility / viewportAlphaRender
Renderer::createPipelines
MaterialRenderer / SkySurfacePresenter
NEEDED: libnode.so libvulkan.so libandroid.so libc++_shared.so
```

函数地址（例）：`scene` 0x010d90、`viewportCore` 0x0123dc、`fastComposition` 0x012610、`createPipelines` 0x0134c0。

## 1. TGCL —— `Objects.level.bin`（已按实现改正）

真实头是 **44 字节 = magic + 10 × u32**，顺序与之前的猜测不同：

```
0  magic "TGCL"
4  version            == 1
8  classCount         (≤ 10000)
12 fieldCount         (≤ 100000)
16 nodeCount          (≤ 1000000)
20 (解析器忽略的保留字)
24 classTableOffset   (≥ 44)
28 fieldTableOffset   (class 表在前，field 表在后)
32 namePoolOffset
36 nodeAreaOffset
40 fileLength         == 文件长度
```

- **class 表在前**：`classCount × 12` → `{ nameOffset, firstField, fieldCount }`，要求 `classOff + classCount×12 ≤ fieldOff`
- **field 表在后**：`fieldCount × 16` → `{ type, nameOffset, size, classIndex }`，要求 `fieldOff + fieldCount×16 ≤ namePoolOff`
- **`nameOffset` 是名称池内的字节偏移**（不是字符串下标）——之前两版实现都按“第几个字符串”处理，会读错名字
- 节点：`classIndex u32` + `name cstr` + 按类字段顺序排列的字段
- 结束条件：解析完必须恰好等于 `fileLength`，否则编辑器直接拒绝

### 字段类型只有 0–3

| type | 含义 | 编码 |
|---|---|---|
| 0 | raw(size) | 1→u8，2→u16，4→bits32（uint/int/float），8→bits64（hex），12/16→vector（3/4 个 float），64→matrix4，其他→raw hex |
| 1 | string | NUL 结尾 |
| 2 | reference | u32，节点下标；0xFFFFFFFF 表示空 |
| 3 | array | u32 count + count 项；`classIndex == 0xFFFFFFFF` 时每项是 u32 引用，否则每项是 `classIndex` 类的嵌套结构 |

### 验证结果

- **33/33 个 `Objects.level.bin` 全部解析通过、字节数恰好归零**（0 失败）
- CarryLand3：40 节点 / 15 类 / 183 字段；`TerrainBlob` 的 44 个字段全部读出（`spiralAngleBegin_End`、`groundNoise*`、`materialTop/Bottom`、`wedgeBulge`、`erosionParams`、`rail*` 等）
- `EnvNode` 46 个字段（`sunColor`、`tintTop/MidTop/…`、`cheapFog*`、`exposure`、`bloomIntensity`、`fogVolumeIntensity`、`undulationScale`、`pointIntensity`…），与 `native/Assets/*.json` 里的环境导出逐字段对应

## 2. LVL0 —— `BstBaked.meshes`（已按实现改正）

```
0    magic "LVL0"
4    version u32            51 / 52
8    sectionCount u8        (≤ 10)
9    3 字节填充
12   段目录：{ tag[4], offset u32, length u32 }，offset ≥ 132，段不得重叠
```

**`LOD0` 段是裸 LZ4 block**（没有长度前缀）——之前按“u32 解压后长度”处理是错的。

LOD0 内部顺序：

1. `bakeCount u32`；每个 bake：`name string`、`guid u32`、`submeshCount u32`、`uniform u8`
   - 每个 submesh：`vertexCount u32`、`indexBytes u32`、光照块（uniform 时 12 字节，否则 `vertexCount×12`）、索引块 `indexBytes`
2. `terrainCount u32`；每条地形记录：
   `linkedId u32, flags u8, bounds(6×f32), vertexCount u32, indexCount u32, 顶点(vertexCount×36)`
   → `collisionBytes u32 + 数据` → `gridBounds(6×f32)` → `cellSize f32` → `dimensions(3×u32)`
   → `patchCount u32 + (count, raw) u32×2` → `edgeCount u32, pairCount u32, refCount u32`
   → `pairCount×{u16,u16}` → `refCount×u16` → `edgeCount×u32` → 索引（u16；边表非空时按边表重建）
3. 云（若有）：`origin 3×i32`、`dimensions 3×i32`、稀疏块、活动块坐标、三张表（Dist/Amb01/Amb2）、`sunOcclusionScale`、两个分辨率、代理网格（16 字节步长）
4. 裙边：`skirtCount u32`；每条：`vertexCount u32`、`顶点(×40)`、`indexCount u32`、索引 u16
5. 遮挡体：`occluderCount u32`；每条：`vertexCount u32, indexCount u32, 顶点(×16), 索引 u16`
6. 必须恰好读完 LOD0 全部字节

### 36 / 40 字节顶点流（实测确认）

| 偏移 | 字段 | 说明 |
|---|---|---|
| +0 | pos float3 | |
| +12 | normal snorm4 | 4 个 int8，编辑器读取时 clamp 到 −127 |
| +16 | materialIds u8×4 | 主材质 id 在首字节 |
| +20 | weights u8×4 | 255 = 该槽满权重 |
| +24 | light u8×12 | light0/1/2 各 4 字节 |
| +36 | userData1 u8×4 | **仅裙边**（stride 40） |

### 验证结果

从 APK 直接抽出全部 **33 份** `BstBaked.meshes` 逐份解析：**33/33 通过，`LOD0` 字节恰好归零**。

出货数据普查（这就是 `Core/FormatSelfTest.swift` 里那张基准表）：

| 项 | 值 |
|---|---|
| 解析通过 | 33 / 33 |
| 版本 | 32 张 v52，`WorldEmpty` v51 |
| 地形记录总数 | 77 条，单图 0/1/2/3/4/6 条都有（22 张图是多条） |
| 地形顶点 / 索引 | 1,679,808 / 9,823,857 |
| 裙边 | 27 张图，共 2,533 条，363,788 顶点 / 1,339,572 索引（最多 `Prairie_Cave` 243 条） |
| 遮挡体 | 每张图 1 条，共 190,987 顶点 |
| 烘焙 | 10,653 个 |
| 云体 | **0 张图有** |
| 边表 | **0 张图非空** |

单图极值：`Prairie_ButterflyFields` 100,901 顶点（6 条地形 + 44 条裙边）；
`CarryLand3` 仍是 63,761 / 382,353，与早期分析数字完全一致。
`CandleSpace` 88 个 bake、无地形记录、只有遮挡体。
索引在文件里是 **u16**；编辑器在内存里统一转 `Uint32Array`（合并多块后会超 65535）。

## 3. 编辑器服务端（`server.cjs`）

- 本地 HTTP：只监听 `127.0.0.1` 随机端口，URL 带 32 字节随机前缀，校验 `Host`/`Origin`
- RPC：POST `rpc/<name>`，自定义编码 `magic 827935571 + u32 JSON 长度 + JSON + 8 字节对齐的二进制块表`
- 保存四道保护：`_i(path, oldHash, bytes)` 先比对 SHA-256、再备份（返回 backup 路径）、再原子写
- 导出：只打包存在 `.sky-editor-backups` 的地图，生成 `SkyMapEdits.zip`
- 编辑器 RPC 面：`openLevel / save / discard / editObjects / editGeometry / addGeometry(加裙边) / editBake / editBakeSample / bakeData / bakedResource / beamoBakeInfo / beamoGeometry / meshSurfaceInfo / undo / redo / materialInfo / environmentInfo / classCatalog`，以及 `vulkan*` 一整套（`vulkanScene / vulkanMaterialScene / vulkanFrame / vulkanCloudPass / vulkanCloudDepth / vulkanShaderCheck`）
- 材质库：`tables.default`，30 条 `{ index, materialId, rawHex }`，并记录原版 `MaterialDef` 函数地址（`executableSha256 3fa493e2…`、`barnInitialize 0x100407ae0`、`generateParameters 0x100443a70` 等）与字符串表（`u_matColor`、`u_matUvScale`、`SandSh`、`GrassSh`、`RockFaceSh`…）
- 环境：`queue{limit:16, stride:1040}`；插值类型 0–5 整数截断、6/7 float、8/10 四分量、11 bool 阈值 0.5 —— 与本仓库 `Ambience.swift` 的规则一致

## 4. 原版 iOS 着色器 ABI（上一轮，保留）

- 14 个 `MTLB` 容器，`vsmain`/`fsmain`，Metal 3.1（`metalfe-32023.864`），bitcode 在 +367/+278
- 顶点属性 `a_position(0) a_normal(1) a_light0(2) a_light1(3) a_light2(4) a_color(5)`，VATY `[5,6,6,6,6,6]`
- varying `v_eye / v_normSkirt / v_color / v_light0 / v_light1 / v_light2 / v_uv0`
- uniform 结构体 `PerObjectUniforms_257/692`、`PerPassUniforms_371`、`PerFrameUniforms_111`（Sand fs 111 个成员），纹理 `u_waterSim / u_lightPRTex / u_lightCSTex / u_grassMaskTexture / u_normalTex`，Cloud 额外 `texture3d u_cloudNoise3D`
- 完整目录：`reverse/shader-abi.json`

## 5. 复跑方式

```bash
python3 tools/reverse/survey.py <Data>                # 全图普查（本文件所有数字的来源）
python3 tools/reverse/survey.py <Data> --swift        # 重新生成 FormatSelfTest 的基准表
python3 tools/reverse/skyformats.py <地图目录>        # 单图 TGCL + LVL0 解析
python3 tools/reverse/dex_dump.py classes.dex         # 类/方法/字段
python3 tools/reverse/android_binary_xml.py AndroidManifest.xml
python3 tools/reverse/elf_symbols.py libsky_vulkan.so --filter Renderer
python3 tools/reverse/metallib_abi.py --metallib <dir> --out shader-abi.json
python3 tools/reverse/terrain_stream.py <*.terrain.bin>
```

## 6. 仍未完成

- `libsky_vulkan.so` 只做到符号级（容器里没有 objdump/capstone，未拆指令）
- 1063 个类的行为逻辑（`classes.json` 有类型与字段，`behavior` 仍是“未复刻”）
- 地形碰撞树/区块重建（编辑器自身也拒绝重建，只允许保存材质编辑）
- 云渲染管线、光簇、雾合成等渲染细节在 `server.cjs` 里有大量注释标注为 pending
- 边表非空的地形记录：重建路径已按 JS 实现，但 33 张出货图**边表全空**，没有样本可验证
- 云体段：33 张图**一张都没有**，该路径同样只有镜像实现
- 遮挡体 16 字节顶点布局未拆

## 7. Swift 侧落地

本轮把上面的实证结论写进了原生工程，替换掉之前按推测写的实现：

| 文件 | 变化 |
|---|---|
| `Core/TGCL.swift` | 44B 头、class 表在前、字段类型 0–3、名称池字节偏移、数组/嵌套结构、精确读完才通过；补丁强制等长 |
| `Core/LVL0.swift` | `u8 段数 + 3 pad`、裸 LZ4、bake/地形/云/裙边/遮挡体整链、边表重建、`u16 → u32` 索引 |
| `Core/Scene.swift` | 地形 + 裙边拍平成同一 36 字节顶点流（裙边丢 +36 的 `userData1`） |
| `Core/LZ4.swift` | 增加“长度未知”的解压入口（`LOD0` 没有长度前缀） |
| `Core/FormatSelfTest.swift` | 33 张图的基准表 + App 内「自检」按钮，逐图比对 |

回归入口：App 底部「自检」，或 `python3 tools/reverse/skyformats.py <Data>`。

## 8. 搬进真正出 ipa 的工程（`ios/`）

`lumiio/sky-mapeditor-build` 里真正打包的是 `ios/Sources/`（UIKit + Metal，1767 行渲染器）。
它**没有**任何游戏格式解析：`TerrainPass` 只读离线导出的

- `<level>.terrain.bin` = `[u32 顶点数][u32 索引数][顶点×36][索引×u32]`
- `<level>.terrain.meta.json` = 按材质分组的索引区间

两份文件由 `native/terrain.mjs` 在电脑上生成后再打进 App 包。本轮把这条路搬进 App：

| 动作 | 位置 |
|---|---|
| 新增 TGCL / LVL0 / LZ4 / ByteReader 解析器 | `ios/Sources/{TGCL,LVL0,LZ4,ByteReader}.swift` |
| 新增就地生成层 | `ios/Sources/GameAssets.swift` |
| `Documents/Data` → `Documents/Assets` 生成同格式资源 | `GameAssets.build()` |
| 每张图该从哪个根目录读 | `GameAssets.root(forLevel:)`，`assetsURL()` / `TerrainPass` / 选关检查都改用它 |
| 选关列表动态化（原来写死 7 关、两行） | 4 列滚动网格 + `skyGameAssetsReady` 通知 |

生成物每张图四份：`<level>.terrain.bin`、`<level>.terrain.meta.json`、
`<level>.json`（纯地形 manifest，`ranges` 留空所以引擎不去找 `.verts/.idx`）、
`<level>.materials.json`（借用包内原版材质表）。

**索引按材质重排**：`TerrainPass.encode` 是「一个区间一次 draw」，而原版地形的三角形按材质交替，
直接照抄会产生几百个区间。所以先按材质把三角形分桶、再拼接，每张图就只剩一个材质一个区间。
实测 33 张图的材质 id 全部落在原版材质表（1–52 与 80）里，每张图 3–7 种材质，
`SandSh=32 / GrassSh=48–52 / RockFaceSh=16–31 / SandRainSh=33 / CloudSh=80` 都能对上着色器家族。

**纯 prefab 关卡走不了这条路**：烛窟（CandleSpace）与 WorldEmpty 的 LVL0 里没有地形记录，
它们的地形来自 `Objects.level.bin` 的 `TerrainBlobPrefab`，由 `terrain.mjs` 程序化生成
（螺旋角、边缘凸起、侵蚀噪声、上下材质按角度切分）。这部分仍是离线产物。

交付：`reverse/ios-gamedata-intake.patch`（8 个文件，+1925 行）。已在干净副本上
`git apply --check` 通过，应用后与本地暂存树逐字节一致。**未编译验证**——本机没有 Swift 工具链。

```bash
cd sky-mapeditor-build && git apply /path/to/ios-gamedata-intake.patch
# 再把游戏的 Data 目录放进 App 的 Documents/Data（文件 App 里可见），启动后自动生成
```
