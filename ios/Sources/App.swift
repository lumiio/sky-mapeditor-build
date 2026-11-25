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

/// MTKView + 手势：单指旋转视角，双指平移，捏合缩放
final class MetalView: MTKView {
    weak var renderer: MetalRenderer?
    private var lastPoint = CGPoint.zero

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
        r.el = min(1.35, max(-1.35, r.el - dy * 0.006))
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {}
}

/// 左下角虚拟摇杆：推杆 → (左右, 前后)，松手回中
final class Joystick: UIView {
    var onMove: ((SIMD2<Float>) -> Void)?
    private let knob = UIView()
    private var radius: CGFloat = 34

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 1, alpha: 0.10)
        layer.borderWidth = 1
        layer.borderColor = UIColor(white: 1, alpha: 0.14).cgColor
        layer.cornerCurve = .continuous
        knob.backgroundColor = UIColor(white: 1, alpha: 0.22)
        knob.layer.borderWidth = 1
        knob.layer.borderColor = UIColor(white: 1, alpha: 0.30).cgColor
        knob.isUserInteractionEnabled = false
        addSubview(knob)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        radius = max(20, bounds.width / 2 - 26)
        let k: CGFloat = 44
        knob.frame = CGRect(x: bounds.midX - k / 2, y: bounds.midY - k / 2, width: k, height: k)
        knob.layer.cornerRadius = k / 2
    }

    @objc private func pan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        var dx = Float(t.x) / Float(radius)
        var dy = Float(t.y) / Float(radius)
        let len = sqrt(dx * dx + dy * dy)
        if len > 1 { dx /= len; dy /= len }
        knob.transform = CGAffineTransform(translationX: CGFloat(dx) * radius * 0.65,
                                           y: CGFloat(dy) * radius * 0.65)
        if g.state == .ended || g.state == .cancelled || g.state == .failed {
            knob.transform = .identity
            onMove?(SIMD2<Float>(0, 0))
        } else {
            onMove?(SIMD2<Float>(dx, -dy))
        }
    }
}

final class ViewerController: UIViewController, MTKViewDelegate {
    private var renderer: MetalRenderer?
    private var view3d: MetalView!

    private var hud: UILabel!
    private var levelButton: UIButton!
    private var objectsButton: UIButton!
    private var envButton: UIButton!

    private var scrim: UIControl!
    private var leftPanel: UIView!
    private var rightPanel: UIView!
    private var leftStack: UIStackView!
    private var rightStack: UIStackView!
    private var levelSheet: UIView!

    private var joystick: Joystick!
    private var btnFocus: UIButton!
    private var btnGrid: UIButton!
    private var btnMark: UIButton!
    private var btnGeo: UIButton!
    private var btnBloom: UIButton!
    private var statusLabel: UILabel!
    private var exportButton: UIButton!

    private var slMix: UISlider!
    private var slElev: UISlider!
    private var slAzim: UISlider!
    private var slFog: UISlider!
    private var valMix: UILabel!
    private var valElev: UILabel!
    private var valAzim: UILabel!
    private var valFog: UILabel!
    private var envReadout: UILabel!

    private var leftOpen = false
    private var rightOpen = false
    private var sheetShown = false
    private var expandedClass: Int = -1
    private var selectedPos = SIMD3<Float>(0, 0, 0)
    private var hasSelection = false

    private var loading = false
    private var cur = 0
    private var pendingPrevLog = ""

    private let levelIDs = ["CandleSpace", "Prairie_ButterflyFields", "Prairie_Village",
                            "Dawn_TrialsEarth", "Dawn_TrialsAir", "Night_JarCave", "AR_WheatField"]
    private let levelNames = ["烛窟", "蝶原", "草原村", "土试炼", "风试炼", "罐洞", "麦田"]

    private let accent = UIColor(red: 0.31, green: 0.55, blue: 0.98, alpha: 1.0)
    private let cardBG = UIColor(white: 0.055, alpha: 0.98)
    private let chipOff = UIColor(white: 1.0, alpha: 0.09)
    private let dim = UIColor(white: 1.0, alpha: 0.55)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupView()
        setupEditorUI()
        let prev = Boot.tail(40)
        Boot.reset()
        if !prev.isEmpty && !prev.contains("first frame") {
            pendingPrevLog = prev.split(separator: "\n").suffix(2).map { String($0.prefix(60)) }.joined(separator: " ← ")
        }
        load(level: levelIDs[0], index: 0)
    }

    // MARK: - 3D 视图

    private func setupView() {
        view3d = MetalView(frame: view.bounds, device: MTLCreateSystemDefaultDevice())
        view3d.translatesAutoresizingMaskIntoConstraints = false
        view3d.colorPixelFormat = .bgra8Unorm_srgb
        view3d.depthStencilPixelFormat = .invalid
        view3d.framebufferOnly = false
        view3d.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view3d.delegate = self
        view3d.isMultipleTouchEnabled = true
        view3d.preferredFramesPerSecond = 60
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

    // MARK: - 编辑器 UI

    private func setupEditorUI() {
        // 顶部品牌
        let brand = UILabel()
        brand.text = "SKY 地图编辑器"
        brand.font = .systemFont(ofSize: 13, weight: .semibold)
        brand.textColor = UIColor(white: 1, alpha: 0.92)
        brand.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(brand)

        let brandSub = UILabel()
        brandSub.text = "METAL PREVIEW"
        brandSub.font = .systemFont(ofSize: 8, weight: .medium)
        brandSub.textColor = UIColor(white: 1, alpha: 0.38)
        brandSub.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(brandSub)

        exportButton = makePillButton("导出", filled: true)
        exportButton.addTarget(self, action: #selector(onExport), for: .touchUpInside)
        view.addSubview(exportButton)

        levelButton = makePillButton(levelNames[0] + "  ▾", filled: false)
        levelButton.addTarget(self, action: #selector(showLevelSheet), for: .touchUpInside)
        view.addSubview(levelButton)

        objectsButton = makeIconButton("square.stack.3d.up", point: 13)
        objectsButton.addTarget(self, action: #selector(toggleLeft), for: .touchUpInside)
        view.addSubview(objectsButton)

        envButton = makeIconButton("slider.horizontal.3", point: 13)
        envButton.addTarget(self, action: #selector(toggleRight), for: .touchUpInside)
        view.addSubview(envButton)

        hud = UILabel()
        hud.textColor = UIColor(white: 1, alpha: 0.45)
        hud.font = .systemFont(ofSize: 9.5, weight: .regular)
        hud.numberOfLines = 3
        hud.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hud)

        NSLayoutConstraint.activate([
            brand.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            brand.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            brandSub.leadingAnchor.constraint(equalTo: brand.leadingAnchor, constant: 1),
            brandSub.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 1),
            exportButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            exportButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            exportButton.heightAnchor.constraint(equalToConstant: 30),
            levelButton.leadingAnchor.constraint(equalTo: brand.leadingAnchor),
            levelButton.topAnchor.constraint(equalTo: brandSub.bottomAnchor, constant: 8),
            levelButton.heightAnchor.constraint(equalToConstant: 30),
            levelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
            envButton.trailingAnchor.constraint(equalTo: exportButton.trailingAnchor),
            envButton.topAnchor.constraint(equalTo: exportButton.bottomAnchor, constant: 8),
            envButton.widthAnchor.constraint(equalToConstant: 34),
            envButton.heightAnchor.constraint(equalToConstant: 34),
            objectsButton.trailingAnchor.constraint(equalTo: envButton.leadingAnchor, constant: -8),
            objectsButton.centerYAnchor.constraint(equalTo: envButton.centerYAnchor),
            objectsButton.widthAnchor.constraint(equalToConstant: 34),
            objectsButton.heightAnchor.constraint(equalToConstant: 34),
            hud.leadingAnchor.constraint(equalTo: brand.leadingAnchor),
            hud.topAnchor.constraint(equalTo: levelButton.bottomAnchor, constant: 6),
            hud.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])

        // 遮罩
        scrim = UIControl()
        scrim.backgroundColor = UIColor(white: 0, alpha: 0.30)
        scrim.alpha = 0
        scrim.isHidden = true
        scrim.translatesAutoresizingMaskIntoConstraints = false
        scrim.addTarget(self, action: #selector(onScrim), for: .touchUpInside)
        view.addSubview(scrim)
        NSLayoutConstraint.activate([
            scrim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrim.topAnchor.constraint(equalTo: view.topAnchor),
            scrim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        leftPanel = makePanel()
        rightPanel = makePanel()
        view.addSubview(leftPanel)
        view.addSubview(rightPanel)
        NSLayoutConstraint.activate([
            leftPanel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: -380),
            leftPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 96),
            leftPanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            leftPanel.widthAnchor.constraint(equalToConstant: 300),
            rightPanel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: 380),
            rightPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 96),
            rightPanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            rightPanel.widthAnchor.constraint(equalToConstant: 300),
        ])
        leftStack = makeScrollStack(in: leftPanel)
        rightStack = makeScrollStack(in: rightPanel)

        // 摇杆
        joystick = Joystick()
        joystick.translatesAutoresizingMaskIntoConstraints = false
        joystick.onMove = { [weak self] v in self?.renderer?.moveInput = v }
        view.addSubview(joystick)
        NSLayoutConstraint.activate([
            joystick.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            joystick.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            joystick.widthAnchor.constraint(equalToConstant: 116),
            joystick.heightAnchor.constraint(equalToConstant: 116),
        ])

        // 底部右侧功能键 2×3
        btnFocus = makeIconButton("scope", point: 14)
        btnGrid = makeIconButton("grid", point: 13)
        btnMark = makeIconButton("mappin.and.ellipse", point: 13)
        btnGeo = makeIconButton("cube", point: 13)
        btnBloom = makeIconButton("sparkles", point: 13)
        let btnShare = makeIconButton("square.and.arrow.up", point: 13)
        btnFocus.addTarget(self, action: #selector(onFocusTap), for: .touchUpInside)
        btnGrid.addTarget(self, action: #selector(onGridTap), for: .touchUpInside)
        btnMark.addTarget(self, action: #selector(onMarkTap), for: .touchUpInside)
        btnGeo.addTarget(self, action: #selector(onGeoTap), for: .touchUpInside)
        btnBloom.addTarget(self, action: #selector(onBloomTap), for: .touchUpInside)
        btnShare.addTarget(self, action: #selector(onExport), for: .touchUpInside)

        func row(_ a: UIButton, _ b: UIButton) -> UIStackView {
            let s = UIStackView(arrangedSubviews: [a, b])
            s.axis = .horizontal; s.spacing = 8
            a.widthAnchor.constraint(equalToConstant: 46).isActive = true
            a.heightAnchor.constraint(equalToConstant: 46).isActive = true
            b.widthAnchor.constraint(equalToConstant: 46).isActive = true
            b.heightAnchor.constraint(equalToConstant: 46).isActive = true
            return s
        }
        let keyStack = UIStackView(arrangedSubviews: [row(btnFocus, btnGrid), row(btnMark, btnGeo), row(btnBloom, btnShare)])
        keyStack.axis = .vertical
        keyStack.spacing = 8
        keyStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyStack)
        NSLayoutConstraint.activate([
            keyStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            keyStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
        ])

        statusLabel = UILabel()
        statusLabel.font = .systemFont(ofSize: 9, weight: .regular)
        statusLabel.textColor = UIColor(white: 1, alpha: 0.42)
        statusLabel.numberOfLines = 2
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            statusLabel.widthAnchor.constraint(equalToConstant: 128),
        ])

        // 升 / 降
        let up = makeIconButton("chevron.up", point: 12)
        let down = makeIconButton("chevron.down", point: 12)
        up.addTarget(self, action: #selector(onLiftUp), for: .touchUpInside)
        down.addTarget(self, action: #selector(onLiftDown), for: .touchUpInside)
        view.addSubview(up); view.addSubview(down)
        NSLayoutConstraint.activate([
            up.leadingAnchor.constraint(equalTo: joystick.trailingAnchor, constant: 8),
            up.bottomAnchor.constraint(equalTo: joystick.centerYAnchor, constant: -2),
            up.widthAnchor.constraint(equalToConstant: 34), up.heightAnchor.constraint(equalToConstant: 34),
            down.leadingAnchor.constraint(equalTo: up.leadingAnchor),
            down.topAnchor.constraint(equalTo: up.bottomAnchor, constant: 6),
            down.widthAnchor.constraint(equalToConstant: 34), down.heightAnchor.constraint(equalToConstant: 34),
        ])

        buildLevelSheet()
        rebuildRightPanel()
        refreshButtons()
        syncTitle()
    }

    private func makePanel() -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = cardBG
        v.layer.cornerRadius = 22
        v.layer.cornerCurve = .continuous
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor(white: 1, alpha: 0.08).cgColor
        return v
    }

    private func makeScrollStack(in panel: UIView) -> UIStackView {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        panel.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: 14),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -14),
        ])
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        return stack
    }

    private func makePillButton(_ title: String, filled: Bool) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        b.layer.cornerRadius = 15
        b.layer.cornerCurve = .continuous
        b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 13, bottom: 0, right: 13)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = filled ? accent : UIColor(white: 1, alpha: 0.10)
        b.layer.borderWidth = filled ? 0 : 1
        b.layer.borderColor = UIColor(white: 1, alpha: 0.08).cgColor
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    private func makeIconButton(_ symbol: String, point: CGFloat) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: point, weight: .semibold)), for: .normal)
        b.tintColor = UIColor(white: 1, alpha: 0.92)
        b.backgroundColor = UIColor(white: 1, alpha: 0.10)
        b.layer.cornerRadius = 17
        b.layer.cornerCurve = .continuous
        b.layer.borderWidth = 1
        b.layer.borderColor = UIColor(white: 1, alpha: 0.08).cgColor
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    private func syncTitle() {
        levelButton?.setTitle(levelNames[cur] + "  ▾", for: .normal)
    }

    // MARK: - 面板内容

    private func rebuildLeftPanel() {
        leftStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let head = UIStackView()
        head.axis = .horizontal
        let t = UILabel(); t.text = "场景对象"; t.font = .systemFont(ofSize: 14, weight: .bold); t.textColor = .white
        let totalObjects = renderer?.sceneClasses.reduce(0) { $0 + $1.count } ?? 0
        let badge = UILabel(); badge.text = "\(totalObjects)"
        badge.font = .systemFont(ofSize: 10, weight: .semibold); badge.textColor = dim
        badge.textAlignment = .right
        head.addArrangedSubview(t); head.addArrangedSubview(badge)
        leftStack.addArrangedSubview(head)

        let mat = UILabel()
        mat.text = materialSummary()
        mat.font = .systemFont(ofSize: 9.5); mat.textColor = dim
        mat.numberOfLines = 2
        leftStack.addArrangedSubview(mat)
        leftStack.addArrangedSubview(hairline())

        guard let classes = renderer?.sceneClasses, !classes.isEmpty else {
            let e = UILabel(); e.text = "该关卡暂无对象数据"; e.font = .systemFont(ofSize: 11); e.textColor = dim
            leftStack.addArrangedSubview(e)
            return
        }
        for (i, c) in classes.enumerated() {
            let b = UIButton(type: .system)
            b.contentHorizontalAlignment = .left
            b.setTitle("\(c.name)    \(c.count)", for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .medium)
            b.setTitleColor(UIColor(white: 1, alpha: 0.86), for: .normal)
            b.tag = i
            b.addTarget(self, action: #selector(onClassTap(_:)), for: .touchUpInside)
            b.heightAnchor.constraint(equalToConstant: 26).isActive = true
            leftStack.addArrangedSubview(b)
            if i == expandedClass {
                for it in c.items.prefix(60) {
                    let ib = UIButton(type: .system)
                    ib.contentHorizontalAlignment = .left
                    ib.setTitle("· " + it.name, for: .normal)
                    ib.titleLabel?.font = .systemFont(ofSize: 10)
                    ib.setTitleColor(UIColor(white: 1, alpha: 0.55), for: .normal)
                    ib.tag = i
                    ib.accessibilityHint = it.name
                    ib.addTarget(self, action: #selector(onItemTap(_:)), for: .touchUpInside)
                    ib.heightAnchor.constraint(equalToConstant: 22).isActive = true
                    leftStack.addArrangedSubview(ib)
                }
            }
        }
    }

    private func rebuildRightPanel() {
        rightStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let head = UIStackView()
        head.axis = .horizontal
        let t = UILabel(); t.text = "环境"; t.font = .systemFont(ofSize: 14, weight: .bold); t.textColor = .white
        let badge = UILabel(); badge.text = "Ambience"; badge.font = .systemFont(ofSize: 10, weight: .medium); badge.textColor = dim
        badge.textAlignment = .right
        head.addArrangedSubview(t); head.addArrangedSubview(badge)
        rightStack.addArrangedSubview(head)

        slMix = makeSlider(0, 1, 0.15, #selector(onMix))
        slElev = makeSlider(-5, 90, 55, #selector(onElev))
        slAzim = makeSlider(-180, 180, 145, #selector(onAzim))
        slFog = makeSlider(0, 0.06, 0.004, #selector(onFog))

        valMix = valueLabel("0.15"); valElev = valueLabel("55°"); valAzim = valueLabel("145°"); valFog = valueLabel("0.004")
        rightStack.addArrangedSubview(sliderRow("昼 → 黄昏", slMix, valMix))
        rightStack.addArrangedSubview(sliderRow("太阳高度", slElev, valElev))
        rightStack.addArrangedSubview(sliderRow("太阳方位", slAzim, valAzim))
        rightStack.addArrangedSubview(sliderRow("雾密度", slFog, valFog))

        envReadout = UILabel()
        envReadout.font = .systemFont(ofSize: 9.5)
        envReadout.textColor = dim
        envReadout.numberOfLines = 2
        updateEnvReadout()
        rightStack.addArrangedSubview(envReadout)
        rightStack.addArrangedSubview(hairline())

        let shHead = UIStackView()
        shHead.axis = .horizontal
        let st = UILabel(); st.text = "原版着色器"; st.font = .systemFont(ofSize: 12, weight: .bold); st.textColor = .white
        let sc = UILabel(); sc.text = "\(shaderNames().count)"; sc.font = .systemFont(ofSize: 10); sc.textColor = dim
        sc.textAlignment = .right
        shHead.addArrangedSubview(st); shHead.addArrangedSubview(sc)
        rightStack.addArrangedSubview(shHead)
        let note = UILabel(); note.text = "清单来自本关材质表"; note.font = .systemFont(ofSize: 9); note.textColor = dim
        rightStack.addArrangedSubview(note)
        for n in shaderNames().prefix(60) {
            let l = UILabel(); l.text = "\(n)    预览"; l.font = .systemFont(ofSize: 10); l.textColor = UIColor(white: 1, alpha: 0.62)
            rightStack.addArrangedSubview(l)
        }
    }

    private func hairline() -> UIView {
        let v = UIView(); v.backgroundColor = UIColor(white: 1, alpha: 0.07)
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func valueLabel(_ s: String) -> UILabel {
        let l = UILabel(); l.text = s; l.font = .systemFont(ofSize: 9.5); l.textColor = dim
        l.textAlignment = .right
        l.widthAnchor.constraint(equalToConstant: 54).isActive = true
        return l
    }

    private func makeSlider(_ minV: Float, _ maxV: Float, _ v: Float, _ action: Selector) -> UISlider {
        let s = UISlider()
        s.minimumValue = minV; s.maximumValue = maxV; s.value = v
        s.minimumTrackTintColor = accent
        s.maximumTrackTintColor = UIColor(white: 1, alpha: 0.12)
        s.thumbTintColor = .white
        s.addTarget(self, action: action, for: .valueChanged)
        return s
    }

    private func sliderRow(_ title: String, _ s: UISlider, _ v: UILabel) -> UIStackView {
        let l = UILabel(); l.text = title; l.font = .systemFont(ofSize: 10.5); l.textColor = UIColor(white: 1, alpha: 0.80)
        l.widthAnchor.constraint(equalToConstant: 62).isActive = true
        let row = UIStackView(arrangedSubviews: [l, s, v])
        row.axis = .horizontal; row.spacing = 8; row.alignment = .center
        return row
    }

    private func shaderNames() -> [String] {
        guard let u = Bundle.main.url(forResource: "\(levelIDs[cur]).materials", withExtension: "json"),
              let d = try? Data(contentsOf: u),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [] }
        var set = Set<String>()
        for m in arr { if let s = m["shader"] as? String { set.insert(s) } }
        return set.sorted()
    }

    private func materialSummary() -> String {
        guard let u = Bundle.main.url(forResource: "\(levelIDs[cur]).materials", withExtension: "json"),
              let d = try? Data(contentsOf: u),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return "材质 —" }
        let names = arr.compactMap { $0["shader"] as? String }
        let first = names.first ?? "—"
        return "材质 \(first) · \(arr.count) 条 · \(Set(names).count) 种着色器"
    }

    private func updateStatus() {
        guard let r = renderer else { return }
        let objs = r.sceneClasses.reduce(0) { $0 + $1.count }
        statusLabel.text = "\(levelIDs[cur]) · \(objs) 个对象 · \(r.sceneClasses.count) 个类\n1 块地形 · \(materialSummary())"
    }

    private func updateEnvReadout() {
        guard envReadout != nil else { return }
        envReadout.text = String(format: "太阳 %.0f° / %.0f° · 雾 %.3f · 泛光 %@",
                                 slElev.value, slAzim.value, slFog.value, renderer?.showBloom == true ? "开" : "关")
    }

    // MARK: - 面板开关

    private func showPanels(any: Bool) {
        scrim.isHidden = false
        view.bringSubviewToFront(scrim)
        view.bringSubviewToFront(leftPanel)
        view.bringSubviewToFront(rightPanel)
        UIView.animate(withDuration: 0.24) { self.scrim.alpha = 1 }
    }

    @objc private func toggleLeft() {
        if leftOpen { closePanels(); return }
        if rightOpen { closePanels() }
        leftOpen = true
        rebuildLeftPanel()
        showPanels(any: true)
        leftPanel.transform = CGAffineTransform(translationX: -40, y: 0)
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut]) {
            self.leftPanel.transform = .identity
        }
    }

    @objc private func toggleRight() {
        if rightOpen { closePanels(); return }
        if leftOpen { closePanels() }
        rightOpen = true
        rebuildRightPanel()
        showPanels(any: true)
        rightPanel.transform = CGAffineTransform(translationX: 40, y: 0)
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut]) {
            self.rightPanel.transform = .identity
        }
    }

    @objc private func onScrim() {
        if sheetShown { hideLevelSheet() }
        closePanels()
    }

    @objc private func closePanels() {
        guard leftOpen || rightOpen else { return }
        leftOpen = false; rightOpen = false
        UIView.animate(withDuration: 0.2, animations: {
            self.scrim.alpha = 0
            self.leftPanel.transform = CGAffineTransform(translationX: -40, y: 0)
            self.rightPanel.transform = CGAffineTransform(translationX: 40, y: 0)
        }) { _ in
            self.scrim.isHidden = true
            self.leftPanel.transform = .identity
            self.rightPanel.transform = .identity
        }
    }

    // MARK: - 关卡选择

    private func buildLevelSheet() {
        levelSheet = makePanel()
        levelSheet.isHidden = true
        view.addSubview(levelSheet)
        NSLayoutConstraint.activate([
            levelSheet.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            levelSheet.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            levelSheet.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
        ])
        let stack = UIStackView()
        stack.axis = .vertical; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        levelSheet.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: levelSheet.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: levelSheet.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: levelSheet.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: levelSheet.bottomAnchor, constant: -16),
        ])
        let grab = UIView(); grab.backgroundColor = UIColor(white: 1, alpha: 0.22)
        grab.layer.cornerRadius = 2; grab.translatesAutoresizingMaskIntoConstraints = false
        levelSheet.addSubview(grab)
        NSLayoutConstraint.activate([
            grab.centerXAnchor.constraint(equalTo: levelSheet.centerXAnchor),
            grab.topAnchor.constraint(equalTo: levelSheet.topAnchor, constant: 7),
            grab.widthAnchor.constraint(equalToConstant: 34), grab.heightAnchor.constraint(equalToConstant: 4),
        ])
        let title = UILabel(); title.text = "地图"; title.font = .systemFont(ofSize: 12, weight: .medium); title.textColor = dim
        stack.addArrangedSubview(title)
        for rowIdx in 0..<2 {
            let row = UIStackView(); row.axis = .horizontal; row.spacing = 6
            for i in (rowIdx * 4)..<min(7, rowIdx * 4 + 4) {
                let b = UIButton(type: .system)
                b.setTitle(levelNames[i], for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 11.5, weight: .medium)
                b.layer.cornerRadius = 9; b.layer.cornerCurve = .continuous
                b.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
                b.tag = i
                b.backgroundColor = i == cur ? accent : chipOff
                b.setTitleColor(.white, for: .normal)
                b.addTarget(self, action: #selector(onLevelTap(_:)), for: .touchUpInside)
                b.heightAnchor.constraint(equalToConstant: 30).isActive = true
                row.addArrangedSubview(b)
            }
            row.addArrangedSubview(UIView())
            stack.addArrangedSubview(row)
        }
    }

    @objc private func showLevelSheet() {
        closePanels()
        sheetShown = true
        scrim.isHidden = false
        view.bringSubviewToFront(scrim)
        view.bringSubviewToFront(levelSheet)
        levelSheet.isHidden = false
        levelSheet.transform = CGAffineTransform(translationX: 0, y: 30)
        levelSheet.alpha = 0
        UIView.animate(withDuration: 0.24) {
            self.scrim.alpha = 1
            self.levelSheet.alpha = 1
            self.levelSheet.transform = .identity
        }
    }

    @objc private func hideLevelSheet() {
        guard sheetShown else { return }
        sheetShown = false
        UIView.animate(withDuration: 0.18, animations: {
            self.scrim.alpha = 0
            self.levelSheet.alpha = 0
        }) { _ in
            self.levelSheet.isHidden = true
            self.scrim.isHidden = true
        }
    }

    // MARK: - 交互

    @objc private func onClassTap(_ sender: UIButton) {
        expandedClass = (expandedClass == sender.tag) ? -1 : sender.tag
        rebuildLeftPanel()
    }

    @objc private func onItemTap(_ sender: UIButton) {
        guard let r = renderer, let classes = renderer?.sceneClasses, sender.tag < classes.count else { return }
        let cls = classes[sender.tag]
        let name = sender.accessibilityHint ?? ""
        if let it = cls.items.first(where: { $0.name == name }), it.pos.count >= 3 {
            selectedPos = SIMD3<Float>(it.pos[0], it.pos[1], it.pos[2])
            hasSelection = true
            r.focus(on: selectedPos)
            hud.text = "已聚焦：\(it.name)"
        }
    }

    @objc private func onFocusTap() {
        guard let r = renderer else { return }
        if hasSelection {
            r.focus(on: selectedPos)
        } else {
            r.walkPos = SIMD2<Float>(0, 0); r.eyeLift = 0
            r.az = 2.10; r.el = 0
        }
    }

    @objc private func onGridTap() {
        guard let r = renderer else { return }
        r.showGrid.toggle(); refreshButtons()
    }

    @objc private func onMarkTap() {
        guard let r = renderer else { return }
        r.showMarkers.toggle(); refreshButtons()
    }

    @objc private func onGeoTap() {
        guard let r = renderer else { return }
        if !r.useGeo { r.useGeo = true; r.geoRenderMode = 0 }
        else if r.geoRenderMode >= 3 { r.useGeo = false }
        else { r.geoRenderMode += 1 }
        hud.text = r.useGeo ? ["原版材质", "参考材质", "点云", "编辑器 Basic"][r.geoRenderMode] : "原版材质（原版贴图）"
        refreshButtons()
    }

    @objc private func onBloomTap() {
        guard let r = renderer else { return }
        r.showBloom.toggle(); refreshButtons(); updateEnvReadout()
    }

    @objc private func onLiftUp() { renderer?.eyeLift = min(120, (renderer?.eyeLift ?? 0) + 1.2) }
    @objc private func onLiftDown() { renderer?.eyeLift = max(-40, (renderer?.eyeLift ?? 0) - 1.2) }

    private func refreshButtons() {
        guard let r = renderer, btnGrid != nil else { return }
        let on = UIColor(red: 0.31, green: 0.55, blue: 0.98, alpha: 0.85)
        btnGrid.backgroundColor = r.showGrid ? on : UIColor(white: 1, alpha: 0.10)
        btnMark.backgroundColor = r.showMarkers ? on : UIColor(white: 1, alpha: 0.10)
        btnBloom.backgroundColor = r.showBloom ? on : UIColor(white: 1, alpha: 0.10)
        btnGeo.backgroundColor = UIColor(white: 1, alpha: 0.10)
        let icons = ["cube", "square.stack.3d.up", "circle.grid.3x3", "sun.max"]
        btnGeo.setImage(UIImage(systemName: r.useGeo ? icons[min(3, r.geoRenderMode)] : "cube.transparent",
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)), for: .normal)
    }

    @objc private func onMix() { renderer?.daylightMix = slMix.value; valMix.text = String(format: "%.2f", slMix.value); updateEnvReadout() }
    @objc private func onElev() { renderer?.sunElev = slElev.value; valElev.text = String(format: "%.0f°", slElev.value); updateEnvReadout() }
    @objc private func onAzim() { renderer?.sunAzim = slAzim.value; valAzim.text = String(format: "%.0f°", slAzim.value); updateEnvReadout() }
    @objc private func onFog() { renderer?.fogDensity = slFog.value; valFog.text = String(format: "%.3f", slFog.value); updateEnvReadout() }

    @objc private func onExport() {
        guard let url = renderer?.exportGeo() else { hud.text = "导出失败"; return }
        let ac = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        ac.popoverPresentationController?.sourceView = exportButton
        present(ac, animated: true)
        hud.text = "已导出 \(url.lastPathComponent)"
    }

    @objc private func onLevelTap(_ sender: UIButton) {
        let i = sender.tag
        guard i >= 0, i < levelIDs.count else { return }
        hideLevelSheet()
        load(level: levelIDs[i], index: i)
    }

    @objc private func onReset() {
        guard let r = renderer else { return }
        r.az = 2.10; r.el = 0; r.zoom = 1.0
        r.walkPos = SIMD2<Float>(0, 0); r.eyeLift = 0
        hasSelection = false
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        guard let r = renderer else { return }
        r.zoom = min(6.0, max(0.2, r.zoom / Float(g.scale)))
        g.scale = 1
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        guard let r = renderer else { return }
        let t = g.translation(in: view3d)
        let s = Float(t.x) * 0.03, f = Float(t.y) * 0.03
        let dx = -sin(r.az), dz = cos(r.az)
        r.walkPos.x += cos(r.az) * s + dx * f
        r.walkPos.y += -sin(r.az) * s + dz * f
        g.setTranslation(.zero, in: view3d)
    }

    // MARK: - 加载 / 渲染

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
        if loading { return }
        guard let root = Bundle.main.url(forResource: "Assets", withExtension: nil) else { hud.text = "Assets 缺失"; return }
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("\(level).terrain.bin").path) else {
            hud.text = "\(level) 无地形数据"
            return
        }
        cur = index
        syncTitle()
        closePanels()
        hud.text = "加载中…"
        loading = true
        view3d.isPaused = true
        let old = renderer
        renderer = nil
        view3d.renderer = nil
        old?.retire()

        DispatchQueue.global(qos: .userInitiated).async {
            var nr: MetalRenderer?
            autoreleasepool { nr = MetalRenderer(level: level) }
            DispatchQueue.main.async {
                self.renderer = nr
                self.view3d.renderer = nr
                self.view3d.isPaused = false
                self.loading = false
                guard let nr else { self.hud.text = "初始化失败"; return }
                nr.sunElev = self.slElev?.value ?? 55
                nr.sunAzim = self.slAzim?.value ?? 145
                nr.fogDensity = self.slFog?.value ?? 0.004
                nr.daylightMix = self.slMix?.value ?? 0.15
                self.rebuildLeftPanel()
                self.rebuildRightPanel()
                self.refreshButtons()
                self.updateStatus()
                var text = "v26 · 编辑器 Basic · " + nr.stats
                if let err = nr.lastError { text = "加载失败：" + err }
                if !self.pendingPrevLog.isEmpty { text += " · 上次断在 " + self.pendingPrevLog; self.pendingPrevLog = "" }
                self.hud.text = text
                Boot.log("切换完成 \(level) ok=\(nr != nil) 内存=\(self.memMB())MB drawable=\(Int(self.view3d.drawableSize.width))×\(Int(self.view3d.drawableSize.height))")
            }
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let r = renderer else { return }
        r.draw(in: view)
        if !Boot.framed { Boot.framed = true; Boot.log("first frame ok") }
        if let err = r.lastError, (hud.text ?? "").hasPrefix("加载失败") != true {
            hud.text = "加载失败：" + err
        }
    }
}
