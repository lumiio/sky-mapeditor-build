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
        let lo: Float = r.firstPerson ? -1.35 : -0.2
        r.el = min(1.35, max(lo, r.el - dy * 0.006))
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
}

final class ViewerController: UIViewController, MTKViewDelegate {
    private var renderer: MetalRenderer?
    private var view3d: MetalView!

    // 极简 HUD：左上角关卡胶囊 + 右下角一个圆按钮；所有设置收在点开后的底部面板里。
    private var pill: UIButton!
    private var titleLabel: UILabel!
    private var hud: UILabel!
    private var gear: UIButton!
    private var scrim: UIControl!
    private var sheet: UIView!
    private var levelChips: [UIButton] = []
    private var swFog: UISwitch!
    private var swCloud: UISwitch!
    private var swDome: UISwitch!
    private var swFP: UISwitch!
    private var swObj: UISwitch!
    private var expoSlider: UISlider!
    private var expoLabel: UILabel!
    private var sheetShown = false

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
        // ---- 左上角：关卡胶囊 ----
        pill = UIButton(type: .system)
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.backgroundColor = UIColor(white: 1, alpha: 0.10)
        pill.layer.cornerRadius = 17
        pill.layer.cornerCurve = .continuous
        pill.layer.borderWidth = 1
        pill.layer.borderColor = UIColor(white: 1, alpha: 0.08).cgColor
        pill.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 12)
        pill.addTarget(self, action: #selector(showSheet), for: .touchUpInside)

        titleLabel = UILabel()
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.isUserInteractionEnabled = false
        pill.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: pill.trailingAnchor, constant: -12),
        ])
        view.addSubview(pill)

        hud = UILabel()
        hud.textColor = UIColor(white: 1, alpha: 0.45)
        hud.font = .systemFont(ofSize: 10.5, weight: .regular)
        hud.numberOfLines = 2
        hud.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hud)

        // ---- 右下角：设置 ----
        gear = UIButton(type: .system)
        gear.translatesAutoresizingMaskIntoConstraints = false
        gear.setImage(UIImage(systemName: "slider.horizontal.3",
                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)),
                      for: .normal)
        gear.tintColor = UIColor(white: 1, alpha: 0.92)
        gear.backgroundColor = UIColor(white: 1, alpha: 0.10)
        gear.layer.cornerRadius = 24
        gear.layer.cornerCurve = .continuous
        gear.layer.borderWidth = 1
        gear.layer.borderColor = UIColor(white: 1, alpha: 0.08).cgColor
        gear.addTarget(self, action: #selector(showSheet), for: .touchUpInside)
        view.addSubview(gear)

        NSLayoutConstraint.activate([
            pill.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            pill.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            pill.heightAnchor.constraint(equalToConstant: 34),
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
            hud.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 4),
            hud.topAnchor.constraint(equalTo: pill.bottomAnchor, constant: 6),
            hud.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -14),
            gear.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            gear.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            gear.widthAnchor.constraint(equalToConstant: 48),
            gear.heightAnchor.constraint(equalToConstant: 48),
        ])

        // ---- 遮罩 + 底部设置面板 ----
        scrim = UIControl()
        scrim.translatesAutoresizingMaskIntoConstraints = false
        scrim.backgroundColor = UIColor(white: 0, alpha: 0.35)
        scrim.alpha = 0
        scrim.isHidden = true
        scrim.addTarget(self, action: #selector(hideSheet), for: .touchUpInside)
        view.addSubview(scrim)

        sheet = UIView()
        sheet.translatesAutoresizingMaskIntoConstraints = false
        sheet.backgroundColor = UIColor(white: 0.055, alpha: 0.99)
        sheet.layer.cornerRadius = 24
        sheet.layer.cornerCurve = .continuous
        sheet.layer.borderWidth = 1
        sheet.layer.borderColor = UIColor(white: 1, alpha: 0.08).cgColor
        sheet.isHidden = true
        view.addSubview(sheet)

        let grabber = UIView()
        grabber.translatesAutoresizingMaskIntoConstraints = false
        grabber.backgroundColor = UIColor(white: 1, alpha: 0.24)
        grabber.layer.cornerRadius = 2
        sheet.addSubview(grabber)

        // 关卡区：七关排两行
        let levelTitle = UILabel()
        levelTitle.text = "关卡"
        levelTitle.textColor = UIColor(white: 1, alpha: 0.45)
        levelTitle.font = .systemFont(ofSize: 11, weight: .medium)

        func chipRow(_ idxs: [Int]) -> UIStackView {
            let row = UIStackView()
            row.axis = .horizontal; row.spacing = 6; row.alignment = .leading
            for i in idxs {
                let b = makeChip(levelNames[i])
                b.tag = i
                b.addTarget(self, action: #selector(onLevelTap(_:)), for: .touchUpInside)
                levelChips.append(b)
                row.addArrangedSubview(b)
            }
            row.addArrangedSubview(UIView())   // 撑开，靠左排
            return row
        }
        let levelGrid = UIStackView(arrangedSubviews: [chipRow([0,1,2,3]), chipRow([4,5,6])])
        levelGrid.axis = .vertical
        levelGrid.spacing = 6
        levelGrid.alignment = .leading

        // 显示开关
        swFog = makeSwitch(#selector(onSwitchFog))
        swCloud = makeSwitch(#selector(onSwitchCloud))
        swDome = makeSwitch(#selector(onSwitchDome))
        swFP = makeSwitch(#selector(onSwitchFP))
        swObj = makeSwitch(#selector(onSwitchObj))

        var rowsV: [UIView] = [levelTitle, levelGrid, hairline(), makeRow("雾", swFog),
                       makeRow("云（原版体积云）", swCloud), makeRow("天空穹顶", swDome),
                       makeRow("第一人称（贴地视角）", swFP), hairline()]

        expoLabel = UILabel()
        expoLabel.textColor = UIColor(white: 1, alpha: 0.45)
        expoLabel.font = .systemFont(ofSize: 11, weight: .medium)
        expoLabel.text = "曝光 ×1.00"

        expoSlider = UISlider()
        expoSlider.minimumValue = -2
        expoSlider.maximumValue = 2.5
        expoSlider.value = 0.0
        expoSlider.minimumTrackTintColor = accent
        expoSlider.maximumTrackTintColor = UIColor(white: 1, alpha: 0.12)
        expoSlider.thumbTintColor = .white
        expoSlider.addTarget(self, action: #selector(onExposure), for: .valueChanged)

        let expoRow = UIStackView(arrangedSubviews: [expoLabel, expoSlider])
        expoRow.axis = .horizontal; expoRow.spacing = 12; expoRow.alignment = .center
        rowsV.append(expoRow)

        let stack = UIStackView(arrangedSubviews: rowsV)
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(stack)

        NSLayoutConstraint.activate([
            scrim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrim.topAnchor.constraint(equalTo: view.topAnchor),
            scrim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            sheet.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            grabber.topAnchor.constraint(equalTo: sheet.topAnchor, constant: 8),
            grabber.centerXAnchor.constraint(equalTo: sheet.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 4),
            stack.topAnchor.constraint(equalTo: sheet.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: sheet.bottomAnchor, constant: -20),
        ])

        refreshLevelChips()
        refreshToggles()
        syncTitle()
    }

    private func makeSwitch(_ action: Selector) -> UISwitch {
        let sw = UISwitch()
        sw.onTintColor = accent
        sw.translatesAutoresizingMaskIntoConstraints = false
        sw.addTarget(self, action: action, for: .valueChanged)
        return sw
    }

    private func makeRow(_ title: String, _ sw: UISwitch) -> UIView {
        let l = UILabel()
        l.text = title
        l.textColor = UIColor(white: 1, alpha: 0.9)
        l.font = .systemFont(ofSize: 13, weight: .regular)
        let row = UIStackView(arrangedSubviews: [l, sw])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing
        row.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return row
    }

    private func hairline() -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor(white: 1, alpha: 0.07)
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func syncTitle() {
        guard pill != nil else { return }
        titleLabel.text = levelNames[cur] + "  ▾"
    }

    @objc private func showSheet() {
        guard !sheetShown else { return }
        sheetShown = true
        scrim.isHidden = false
        sheet.isHidden = false
        sheet.transform = CGAffineTransform(translationX: 0, y: 40)
        sheet.alpha = 0
        view.bringSubviewToFront(sheet)
        view.bringSubviewToFront(gear)
        UIView.animate(withDuration: 0.26, delay: 0, options: [.curveEaseOut]) {
            self.scrim.alpha = 1
            self.sheet.alpha = 1
            self.sheet.transform = .identity
        }
    }

    @objc private func hideSheet() {
        guard sheetShown else { return }
        sheetShown = false
        UIView.animate(withDuration: 0.2, animations: {
            self.scrim.alpha = 0
            self.sheet.alpha = 0
            self.sheet.transform = CGAffineTransform(translationX: 0, y: 40)
        }) { _ in
            self.scrim.isHidden = true
            self.sheet.isHidden = true
        }
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
        guard let r = renderer, swFog != nil else { return }
        swFog.setOn(!r.debugSkipFogPost, animated: false)
        swDome.setOn(!r.debugSkipSkyDome, animated: false)
        swCloud.setOn(!r.hideCloud, animated: false)
        swFP.setOn(r.firstPerson, animated: false)
        swObj.setOn(r.showObjects, animated: false)
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
        syncTitle()
        hideSheet()
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
                self.hud.text = "v12 · " + text
                self.refreshToggles()
                self.syncTitle()
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
        r.az = 2.10; r.el = r.firstPerson ? 0 : 0.28; r.zoom = 1.0; r.targetShift = SIMD2<Float>(0, 0)
        r.exposureGain = 1.0
        expoSlider.value = 0.0          // 10^0.88 ≈ 7.6×，烛窟平均亮度 0.018 的可用档位
        expoLabel.text = "曝光 ×1.00"
    }

    @objc private func onSwitchFog(_ sw: UISwitch) {
        renderer?.debugSkipFogPost = !sw.isOn
    }

    @objc private func onSwitchDome(_ sw: UISwitch) {
        renderer?.debugSkipSkyDome = !sw.isOn
    }

    @objc private func onSwitchCloud(_ sw: UISwitch) {
        renderer?.hideCloud = !sw.isOn
    }

    @objc private func onSwitchObj(_ sw: UISwitch) {
        renderer?.showObjects = sw.isOn
    }

    @objc private func onSwitchFP(_ sw: UISwitch) {
        guard let r = renderer else { return }
        r.firstPerson = sw.isOn
        r.el = 0
        r.targetShift = SIMD2<Float>(0, 0)
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
        let k: Float = r.firstPerson ? 0.06 : 0.02
        let s = Float(t.x) * k, f = Float(t.y) * k
        if r.firstPerson {
            // 地面视角：两指平移 = 沿相机朝向水平移动（前推/横移），和游戏里走位一致
            let dx = -sin(r.az), dz = cos(r.az)
            r.targetShift.x += (cos(r.az) * s + dx * f)
            r.targetShift.y += (-sin(r.az) * s + dz * f)
        } else {
            r.targetShift.x -= s
            r.targetShift.y -= f
        }
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
