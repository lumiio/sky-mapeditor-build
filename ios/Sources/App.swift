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
    private var segmented: UISegmentedControl!
    private var info: UILabel!
    private var expoSlider: UISlider!
    private var expoLabel: UILabel!
    private var btnReset: UIButton!
    private var btnFog: UIButton!
    private var btnDome: UIButton!
    private let levelIDs = ["CandleSpace", "Prairie_ButterflyFields", "Prairie_Village",
                            "Dawn_TrialsEarth", "Dawn_TrialsAir", "Night_JarCave", "AR_WheatField"]
    private let levels = ["烛窟", "蝶原", "草原村", "土试炼", "风试炼", "罐洞", "麦田"]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

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
        // 3× 屏下 drawable 是 1320×2868，一帧十几张全屏贴图 ≈300MB，切关卡时新旧渲染器叠加会被系统 jetsam 杀掉。
        // 编辑器不需要 3× 精度，封顶 2×（880×1912），内存直接降 55%。
        view3d.contentScaleFactor = min(UIScreen.main.scale, 2.0)
        view.addSubview(view3d)

        segmented = UISegmentedControl(items: levels)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 11, weight: .medium)], for: .normal)
        segmented.selectedSegmentIndex = 0
        segmented.apportionsSegmentWidthsByContent = true
        segmented.translatesAutoresizingMaskIntoConstraints = false
        segmented.addTarget(self, action: #selector(changeLevel), for: .valueChanged)
        segmented.backgroundColor = UIColor(white: 0.1, alpha: 0.9)
        segmented.selectedSegmentTintColor = UIColor(white: 0.3, alpha: 1)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        view.addSubview(segmented)

        expoSlider = UISlider()
        expoSlider.minimumValue = -2          // 10^-2 = 0.01×
        expoSlider.maximumValue = 2.5         // 10^2.5 ≈ 316×
        expoSlider.value = 0                  // 10^0 = 1×
        expoSlider.translatesAutoresizingMaskIntoConstraints = false
        expoSlider.addTarget(self, action: #selector(onExposure), for: .valueChanged)
        view.addSubview(expoSlider)

        expoLabel = UILabel()
        expoLabel.translatesAutoresizingMaskIntoConstraints = false
        expoLabel.textColor = .white
        expoLabel.font = .systemFont(ofSize: 11, weight: .medium)
        expoLabel.text = "曝光 ×1.00"
        view.addSubview(expoLabel)

        func chip(_ title: String, _ act: Selector) -> UIButton {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.setTitleColor(.white, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
            b.backgroundColor = UIColor(white: 0.16, alpha: 0.9)
            b.layer.cornerRadius = 8
            b.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            b.addTarget(self, action: act, for: .touchUpInside)
            return b
        }
        btnReset = chip("重置视角", #selector(onReset))
        btnFog = chip("雾：开", #selector(onToggleFog))
        btnDome = chip("穹顶：开", #selector(onToggleDome))
        let chipRow = UIStackView(arrangedSubviews: [btnReset, btnFog, btnDome])
        chipRow.axis = .horizontal
        chipRow.spacing = 8
        chipRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chipRow)

        info = UILabel()
        info.translatesAutoresizingMaskIntoConstraints = false
        info.textColor = .white
        info.font = .systemFont(ofSize: 12, weight: .medium)
        info.text = "拖动旋转 · 双指缩放"
        view.addSubview(info)

        NSLayoutConstraint.activate([
            view3d.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view3d.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            view3d.topAnchor.constraint(equalTo: view.topAnchor),
            view3d.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            segmented.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segmented.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            info.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 6),
            info.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            expoSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            expoSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            expoSlider.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -22),
            expoLabel.leadingAnchor.constraint(equalTo: expoSlider.leadingAnchor),
            expoLabel.bottomAnchor.constraint(equalTo: expoSlider.topAnchor, constant: -2),
            chipRow.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            chipRow.bottomAnchor.constraint(equalTo: expoLabel.topAnchor, constant: -10),
        ])

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        view3d.addGestureRecognizer(pinch)
        let dbl = UITapGestureRecognizer(target: self, action: #selector(onReset))
        dbl.numberOfTapsRequired = 2
        view3d.addGestureRecognizer(dbl)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.minimumNumberOfTouches = 2
        view3d.addGestureRecognizer(pan)

        // 先读上一轮的启动日志：没有「first frame」就说明上次启动阶段崩了，把断点留住
        let prevLog = Boot.tail(30)
        Boot.reset()
        load(level: levelIDs[0])
        if !prevLog.isEmpty && !prevLog.contains("first frame") {
            let lines = prevLog.split(separator: "\n").suffix(2).map { String($0).prefix(60) }
            info.text = "上次断在：" + lines.joined(separator: " ← ")
        }
    }

    /// 当前进程占用（phys_footprint），切关卡时打点，便于判断是不是被内存杀掉
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

    private func load(level: String) {
        guard let root = Bundle.main.url(forResource: "Assets", withExtension: nil) else {
            info.text = "Assets 资源目录缺失"; return
        }
        let bin = root.appendingPathComponent("\(level).terrain.bin")
        guard FileManager.default.fileExists(atPath: bin.path) else {
            info.text = "\(level) 的地形数据不在这版包里"
            Boot.log("切换被拦：缺 \(level).terrain.bin")
            return
        }
        // 先把旧渲染器彻底放掉再建新的：两份同时在线时显存会翻倍，切关卡闪退多半死在这里
        Boot.log("UI 切换 → \(level) 内存=\(memMB())MB")
        view3d.isPaused = true
        view3d.renderer = nil
        renderer = nil
        Boot.log("UI 旧渲染器已释放 内存=\(memMB())MB")
        var nr: MetalRenderer?
        autoreleasepool { nr = MetalRenderer(level: level) }
        Boot.log("UI 新建完成 \(level) ok=\(nr != nil) 内存=\(memMB())MB drawable=\(Int(view3d.drawableSize.width))×\(Int(view3d.drawableSize.height))")
        renderer = nr
        view3d.renderer = nr
        view3d.isPaused = false
        if nr == nil {
            info.text = "初始化失败（Metal 不可用或数据缺失）"
            return
        }
        renderer?.exposureGain = Float(pow(10.0, Double(expoSlider.value)))
        if let err = renderer?.lastError {
            info.text = "加载失败：" + err
        } else {
            webLog(level)
        }
        // 换关后按钮标题要跟新渲染器的状态对齐，不然会显示反的
        btnFog.setTitle(renderer?.debugSkipFogPost == true ? "雾：关" : "雾：开", for: .normal)
        btnDome.setTitle(renderer?.debugSkipSkyDome == true ? "穹顶：关" : "穹顶：开", for: .normal)
    }

    private func webLog(_ s: String) {
        info.text = "\(s) · 拖动旋转 · 双指缩放"
    }

    @objc private func changeLevel() {
        let i = segmented.selectedSegmentIndex
        guard i >= 0, i < levelIDs.count else { return }
        load(level: levelIDs[i])
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
        btnFog.setTitle(r.debugSkipFogPost ? "雾：关" : "雾：开", for: .normal)
    }

    @objc private func onToggleDome() {
        guard let r = renderer else { return }
        r.debugSkipSkyDome.toggle()
        btnDome.setTitle(r.debugSkipSkyDome ? "穹顶：关" : "穹顶：开", for: .normal)
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        guard let r = renderer else { return }
        let t = g.translation(in: view3d)
        r.targetShift.x -= Float(t.x) * 0.02
        r.targetShift.y -= Float(t.y) * 0.02
        g.setTranslation(.zero, in: view3d)
    }

    @objc private func onExposure() {
        let gain = Float(pow(10.0, Double(expoSlider.value)))
        expoLabel.text = String(format: "曝光 ×%.2f", gain)
        renderer?.exposureGain = gain
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        guard let r = renderer else { return }
        r.zoom = min(3.0, max(0.35, r.zoom / Float(g.scale)))
        g.scale = 1
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let r = renderer else { return }
        r.draw(in: view)
        if !Boot.framed {
            Boot.framed = true
            Boot.log("first frame ok")
        }
        if let err = r.lastError, (info.text ?? "").hasPrefix("加载失败") != true {
            info.text = "加载失败：" + err
        }
    }
}
