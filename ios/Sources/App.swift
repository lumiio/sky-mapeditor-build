import UIKit
import MetalKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Boot.log("didFinishLaunching")
        let vc = ViewerController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = vc
        window.makeKeyAndVisible()
        self.window = window
        Boot.log("window 已显示")
        return true
    }
}

/// MTKView + 手势：单指旋转，双指捏合缩放
final class MetalView: MTKView {
    weak var renderer: MetalRenderer?
    private var lastPoint = CGPoint.zero

    /// MTKView 按屏幕 scale 自己算 drawable，3× 屏会到 1320×2868，一帧十几张全屏贴图 ≈300MB。
    /// 这里强制封在 2×（机身内存和带宽都省一半），不然切关卡时新旧叠加会被系统杀掉。
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 1, bounds.height > 1 else { return }
        let scale = min(UIScreen.main.scale, 2.0)
        let target = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        if abs(drawableSize.width - target.width) > 1 || abs(drawableSize.height - target.height) > 1 {
            drawableSize = target
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastPoint = touches.first?.location(in: self) ?? .zero
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self), let r = renderer else { return }
        let dx = Float(p.x - lastPoint.x), dy = Float(p.y - lastPoint.y)
        lastPoint = p
        r.az += dx * 0.006
        r.el = min(1.3, max(-0.2, r.el - dy * 0.006))
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
}

final class ViewerController: UIViewController, MTKViewDelegate {
    private var renderer: MetalRenderer?
    private var view3d: MetalView!

    // 底部一张圆角卡片，分三区：关卡 / 显示 / 曝光
    private var card: UIView!
    private var titleLabel: UILabel!
    private var hud: UILabel!
    private var levelBar: UIStackView!
    private var levelChips: [UIButton] = []
    private var btnReset: UIButton!
    private var btnFog: UIButton!
    private var btnDome: UIButton!
    private var btnCloud: UIButton!
    private var expoSlider: UISlider!
    private var expoLabel: UILabel!

    private var loading = false
    private var cur = 0
    private var pendingPrevLog = ""

    private let levelIDs = ["CandleSpace", "Prairie_ButterflyFields", "Prairie_Village",
                            "Dawn_TrialsEarth", "Dawn_TrialsAir", "Night_JarCave", "AR_WheatField"]
    private let levelNames = ["烛窟", "蝶原", "草原村", "土试炼", "风试炼", "罐洞", "麦田"]

    /// 全界面只用一个主色
    private let accent = UIColor(red: 0.31, green: 0.55, blue: 0.98, alpha: 1.0)
    private let chipOff = UIColor(white: 1.0, alpha: 0.09)
    private let textDim = UIColor(white: 1.0, alpha: 0.55)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupView()
        setupCard()
        // 上一轮没跑到 first frame 就没了，说明崩在初始化里，把断点留着
        let prev = Boot.tail(40)
        Boot.reset()
        if !prev.isEmpty && !prev.contains("first frame") {
            pendingPrevLog = prev.split(separator: "\n").suffix(2).map { String($0.prefix(70)) }.joined(separator: " ← ")
        }
        load(level: levelIDs[0], index: 0)
    }

    private func setupView() {
        view3d = MetalView(frame: view.bounds, device: MTLCreateSystemDefaultDevice())
        view3d.translatesAutoresizingMaskIntoConstraints = false
        // 原版 Tonemap 输出是线性值，编辑器在回读时手动做 linear→sRGB；
        // 这里用 sRGB drawable 让硬件完成同一转换，否则画面会整体压暗（gamma 2.2）
        view3d.colorPixelFormat = .bgra8Unorm_srgb
        view3d.depthStencilPixelFormat = .invalid
        view3d.framebufferOnly = false
        view3d.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view3d.delegate = self
        view3d.isMultipleTouchEnabled = true
        view3d.preferredFramesPerSecond = 60
        // 3× 屏下 drawable 是 1320×2868，一帧十几张全屏贴图 ≈300MB；封顶 2×，内存降 55%
        view3d.contentScaleFactor = min(UIScreen.main.scale, 2.0)
        view.addSubview(view3d)

        NSLayoutConstraint.activate([
            view3d.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view3d.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            view3d.topAnchor.constraint(equalTo: view.topAnchor),
            view3d.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        view3d.addGestureRecognizer(pinch)
        let dbl = UITapGestureRecognizer(target: self, action: #selector(onReset))
        dbl.numberOfTapsRequired = 2
        view3d.addGestureRecognizer(dbl)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.minimumNumberOfTouches = 2
        view3d.addGestureRecognizer(pan)
    }

    private func setupCard() {
        card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor(white: 0.07, alpha: 0.93)
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(white: 1.0, alpha: 0.07).cgColor
        view.addSubview(card)

        titleLabel = UILabel()
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.text = levelNames[0]

        hud = UILabel()
        hud.textColor = textDim
        hud.font = .systemFont(ofSize: 11, weight: .regular)
        hud.textAlignment = .right
        hud.text = "…"
        hud.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let head = UIStackView(arrangedSubviews: [titleLabel, hud])
        head.axis = .horizontal
        head.alignment = .firstBaseline
        head.spacing = 8

        // 关卡：横向滚动条，避免 7 个字挤成一坨
        levelBar = UIStackView()
        levelBar.axis = .horizontal
        levelBar.spacing = 6
        levelBar.translatesAutoresizingMaskIntoConstraints = false
        for (i, name) in levelNames.enumerated() {
            let b = makeChip(name)
            b.tag = i
            b.addTarget(self, action: #selector(onLevelTap(_:)), for: .touchUpInside)
            levelChips.append(b)
            levelBar.addArrangedSubview(b)
        }
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.addSubview(levelBar)
        NSLayoutConstraint.activate([
            levelBar.topAnchor.constraint(equalTo: scroll.topAnchor),
            levelBar.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            levelBar.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            levelBar.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            levelBar.heightAnchor.constraint(equalTo: scroll.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 30),
        ])

        // 显示区：视角 / 雾 / 穹顶 / 云
        btnReset = makeChip("重置视角")
        btnReset.addTarget(self, action: #selector(onReset), for: .touchUpInside)
        btnFog = makeChip("雾")
        btnFog.addTarget(self, action: #selector(onToggleFog), for: .touchUpInside)
        btnDome = makeChip("穹顶")
        btnDome.addTarget(self, action: #selector(onToggleDome), for: .touchUpInside)
        btnCloud = makeChip("云")
        btnCloud.addTarget(self, action: #selector(onToggleCloud), for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [btnReset, btnFog, btnDome, btnCloud])
        row.axis = .horizontal
        row.spacing = 6
        row.distribution = .fillProportionally

        expoLabel = UILabel()
        expoLabel.textColor = textDim
        expoLabel.font = .systemFont(ofSize: 11, weight: .medium)
        expoLabel.text = "曝光 ×1.00"

        expoSlider = UISlider()
        expoSlider.minimumValue = -2
        expoSlider.maximumValue = 2.5
        expoSlider.value = 0
        expoSlider.minimumTrackTintColor = accent
        expoSlider.maximumTrackTintColor = UIColor(white: 1, alpha: 0.12)
        expoSlider.thumbTintColor = .white
        expoSlider.addTarget(self, action: #selector(onExposure), for: .valueChanged)

        let expoStack = UIStackView(arrangedSubviews: [expoLabel, expoSlider])
        expoStack.axis = .vertical
        expoStack.spacing = 2

        let stack = UIStackView(arrangedSubviews: [head, scroll, row, expoStack])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            card.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])

        refreshLevelChips()
    }

    private func makeChip(_ title: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        b.layer.cornerRadius = 9
        b.layer.cornerCurve = .continuous
        b.contentEdgeInsets = UIEdgeInsets(top: 5, left: 11, bottom: 5, right: 11)
        b.setContentHuggingPriority(.required, for: .horizontal)
        b.heightAnchor.constraint(equalToConstant: 30).isActive = true
        b.backgroundColor = chipOff
        b.setTitleColor(UIColor(white: 1, alpha: 0.75), for: .normal)
        return b
    }

    private func style(_ b: UIButton, on: Bool) {
        b.backgroundColor = on ? accent : chipOff
        b.setTitleColor(on ? .white : UIColor(white: 1, alpha: 0.72), for: .normal)
    }

    private func refreshLevelChips() {
        for (i, b) in levelChips.enumerated() { style(b, on: i == cur) }
    }

    private func refreshToggles() {
        guard let r = renderer else { return }
        style(btnFog, on: !r.debugSkipFogPost)
        style(btnDome, on: !r.debugSkipSkyDome)
        style(btnCloud, on: !r.hideCloud)
        btnFog.setTitle(r.debugSkipFogPost ? "雾 关" : "雾 开", for: .normal)
        btnDome.setTitle(r.debugSkipSkyDome ? "穹顶 关" : "穹顶 开", for: .normal)
        btnCloud.setTitle(r.hideCloud ? "云 关" : "云 开", for: .normal)
    }

    /// 当前进程占用，切关时打点，用来判断是不是被内存杀掉
    private func memMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }

    private func load(level: String, index: Int) {
        if loading {
            Boot.log("忽略重复切换 \(level)（上一关还在建）")
            return
        }
        guard let root = Bundle.main.url(forResource: "Assets", withExtension: nil) else {
            hud.text = "Assets 缺失"; return
        }
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("\(level).terrain.bin").path) else {
            hud.text = "\(level) 无地形数据"
            Boot.log("切换被拦：缺 \(level).terrain.bin")
            return
        }

        cur = index
        refreshLevelChips()
        titleLabel.text = levelNames[index]
        hud.text = "加载中…"
        loading = true

        // 先把旧渲染器停掉、等 GPU 把在飞的命令跑完再释放：Metal 资源还在被 command buffer 引用时释放会直接把进程打死
        Boot.log("切换 → \(level) 内存=\(memMB())MB")
        view3d.isPaused = true
        let old = renderer
        renderer = nil
        view3d.renderer = nil
        old?.retire()
        Boot.log("旧渲染器已退役 内存=\(memMB())MB")

        // 建渲染器放后台，主线程不再阻塞（阻塞超过 20s 会被系统 watchdog 直接掐掉，也没有崩溃日志）
        DispatchQueue.global(qos: .userInitiated).async {
            var nr: MetalRenderer?
            autoreleasepool { nr = MetalRenderer(level: level) }
            DispatchQueue.main.async {
                self.renderer = nr
                self.view3d.renderer = nr
                self.view3d.isPaused = false
                self.loading = false
                Boot.log("切换完成 \(level) ok=\(nr != nil) 内存=\(self.memMB())MB drawable=\(Int(self.view3d.drawableSize.width))×\(Int(self.view3d.drawableSize.height))")
                guard let nr else {
                    self.hud.text = "初始化失败"
                    return
                }
                nr.exposureGain = Float(pow(10.0, Double(self.expoSlider.value)))
                var text = nr.stats
                if let err = nr.lastError { text = "加载失败：" + err }
                if !self.pendingPrevLog.isEmpty {
                    text += " · 上次断在 " + self.pendingPrevLog
                    self.pendingPrevLog = ""
                }
                self.hud.text = text
                self.refreshToggles()
            }
        }
    }

    @objc private func onLevelTap(_ sender: UIButton) {
        let i = sender.tag
        guard i >= 0, i < levelIDs.count else { return }
        load(level: levelIDs[i], index: i)
    }

    @objc private func onReset() {
        guard let r = renderer else { return }
        r.az = 2.10; r.el = 0.28; r.zoom = 1.0; r.targetShift = SIMD2<Float>(0, 0)
        r.exposureGain = 1.0
        expoSlider.value = 0
        expoLabel.text = "曝光 ×1.00"
    }

    @objc private func onToggleFog() {
        guard let r = renderer else { return }
        r.debugSkipFogPost.toggle()
        refreshToggles()
    }

    @objc private func onToggleDome() {
        guard let r = renderer else { return }
        r.debugSkipSkyDome.toggle()
        refreshToggles()
    }

    @objc private func onToggleCloud() {
        guard let r = renderer else { return }
        r.hideCloud.toggle()
        refreshToggles()
    }

    @objc private func onExposure() {
        let gain = Float(pow(10.0, Double(expoSlider.value)))
        renderer?.exposureGain = gain
        expoLabel.text = String(format: "曝光 ×%.2f", gain)
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        guard let r = renderer else { return }
        r.zoom = min(6.0, max(0.2, r.zoom / Float(g.scale)))
        g.scale = 1
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        guard let r = renderer else { return }
        let t = g.translation(in: view3d)
        r.targetShift.x -= Float(t.x) * 0.02
        r.targetShift.y -= Float(t.y) * 0.02
        g.setTranslation(.zero, in: view3d)
    }

    // MARK: - MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let r = renderer else { return }
        r.draw(in: view)
        if !Boot.framed {
            Boot.framed = true
            Boot.log("first frame ok")
        }
        if let err = r.lastError, (hud.text ?? "").hasPrefix("加载失败") != true {
            hud.text = "加载失败：" + err
        }
    }
}
