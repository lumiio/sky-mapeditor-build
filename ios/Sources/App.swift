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
        r.az -= dx * 0.006
        r.el = min(1.3, max(-0.2, r.el + dy * 0.006))
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
    private let levelIDs = ["CandleSpace", "Prairie_ButterflyFields", "Prairie_Village", "Dawn_TrialsEarth", "Night_JarCave"]
    private let levels = ["烛窟", "蝶原", "草原村", "土试炼", "罐洞"]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        view3d = MetalView(frame: view.bounds, device: MTLCreateSystemDefaultDevice())
        view3d.translatesAutoresizingMaskIntoConstraints = false
        view3d.colorPixelFormat = .bgra8Unorm
        view3d.depthStencilPixelFormat = .invalid
        view3d.framebufferOnly = false
        view3d.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view3d.delegate = self
        view3d.isMultipleTouchEnabled = true
        view3d.preferredFramesPerSecond = 60
        view.addSubview(view3d)

        segmented = UISegmentedControl(items: levels)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 12, weight: .medium)], for: .normal)
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
        ])

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        view3d.addGestureRecognizer(pinch)

        // 先读上一轮的启动日志：没有「first frame」就说明上次启动阶段崩了，把断点留住
        let prevLog = Boot.tail(30)
        Boot.reset()
        load(level: levelIDs[0])
        if !prevLog.isEmpty && !prevLog.contains("first frame"),
           let last = prevLog.split(separator: "\n").last {
            info.text = "上次断在：" + String(last)
        }
    }

    private func load(level: String) {
        renderer = MetalRenderer(level: level)
        view3d.renderer = renderer
        if renderer == nil {
            info.text = "初始化失败（Metal 不可用）"
            return
        }
        renderer?.exposureGain = Float(pow(10.0, Double(expoSlider.value)))
        if let err = renderer?.lastError {
            info.text = "加载失败：" + err
        } else {
            webLog(level)
        }
    }

    private func webLog(_ s: String) {
        info.text = "\(s) · 拖动旋转 · 双指缩放"
    }

    @objc private func changeLevel() {
        load(level: levelIDs[max(0, segmented.selectedSegmentIndex)])
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
