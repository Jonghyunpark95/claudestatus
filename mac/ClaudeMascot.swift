//
//  Claude 마스코트 — macOS 데스크톱 펫 껍데기
//
//  테두리 없는 투명 창을 바탕화면 위에 띄우고 그 안에 pet.html 을 그린다.
//  캐릭터 몸통 위에서만 마우스를 받고, 투명한 부분은 아래 창으로 클릭이 통과한다.
//
//  Electron 없음. 외부 패키지 없음. Cocoa + WebKit 만 사용.
//

import Cocoa
import WebKit

// MARK: - 설정 값

enum Config {
    static var port: String {
        ProcessInfo.processInfo.environment["MASCOT_PORT"]
            ?? info("MascotPort")
            ?? "4573"
    }
    static var base: String { "http://127.0.0.1:\(port)" }
    static var petURL: URL { URL(string: "\(base)/pet.html")! }
    static var dashboardURL: URL { URL(string: base)! }

    /// 빌드할 때 build.sh 가 Info.plist 에 박아둔 값
    static var root: String? { info("MascotRoot") }
    static var node: String? { info("MascotNode") }

    private static func info(_ key: String) -> String? {
        guard let v = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !v.isEmpty else { return nil }
        return v
    }
}

enum PetSize: String, CaseIterable {
    case tiny, small, medium, large

    var dims: NSSize {
        switch self {
        case .tiny:   return NSSize(width: 88,  height: 101)
        case .small:  return NSSize(width: 132, height: 152)
        case .medium: return NSSize(width: 176, height: 202)
        case .large:  return NSSize(width: 232, height: 264)
        }
    }

    var title: String {
        switch self {
        case .tiny:   return "아주 작게"
        case .small:  return "작게"
        case .medium: return "보통"
        case .large:  return "크게"
        }
    }
}

enum Key {
    static let originX = "pet.originX"
    static let originY = "pet.originY"
    static let size = "pet.size"
    static let clickThrough = "pet.clickThrough"
    static let onTop = "pet.onTop"
}

// MARK: - 창

/// 테두리 없는 창은 기본적으로 키 윈도우가 못 된다. 우클릭 메뉴를 위해 열어준다.
final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// 드래그 이동과 우클릭 메뉴를 직접 처리하는 WebView.
final class PetWebView: WKWebView {
    var onRightMouse: ((NSEvent) -> Void)?
    var onDoubleClick: (() -> Void)?
    var onDragEnd: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        // 창 전체를 잡고 끌 수 있게 한다 (드래그가 끝날 때까지 블록됨)
        window?.performDrag(with: event)
        onDragEnd?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightMouse?(event)   // super 를 부르지 않아 WebKit 기본 메뉴를 막는다
    }

    override var mouseDownCanMoveWindow: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

// MARK: - 클릭 통과 판정용 영역

struct HitArea {
    let rect: CGRect      // 창 좌상단 기준 (CSS 좌표계)
    let isEllipse: Bool

    func contains(_ p: CGPoint) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return false }
        guard isEllipse else { return rect.contains(p) }
        let rx = rect.width / 2, ry = rect.height / 2
        let dx = (p.x - rect.midX) / rx
        let dy = (p.y - rect.midY) / ry
        return dx * dx + dy * dy <= 1
    }
}

// MARK: - 앱

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {

    private var window: PetWindow!
    private var webView: PetWebView!
    private var statusItem: NSStatusItem!

    private var hitAreas: [HitArea] = []
    private var currentState = "idle"
    private var currentLabel = "쉬는 중"
    private var currentEmoji = "😴"
    private var currentProject = ""
    private var sessionCount = 0

    private var monitors: [Any] = []
    private var reloadTries = 0

    private let defaults = UserDefaults.standard

    private var petSize: PetSize {
        get { PetSize(rawValue: defaults.string(forKey: Key.size) ?? "") ?? .tiny }
        set { defaults.set(newValue.rawValue, forKey: Key.size); applySize() }
    }
    private var pinnedClickThrough: Bool {
        get { defaults.bool(forKey: Key.clickThrough) }
        set { defaults.set(newValue, forKey: Key.clickThrough); updateClickThrough() }
    }
    private var alwaysOnTop: Bool {
        get { defaults.object(forKey: Key.onTop) == nil ? true : defaults.bool(forKey: Key.onTop) }
        set { defaults.set(newValue, forKey: Key.onTop); applyLevel() }
    }

    // MARK: 시작

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // Dock 아이콘 / Cmd+Tab 에 안 나옴
        buildStatusItem()
        buildWindow()
        ensureServerThenLoad()
        installMouseMonitors()
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveOrigin()
        monitors.forEach { NSEvent.removeMonitor($0) }
    }

    // MARK: 창 만들기

    private func buildWindow() {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "hit")
        cfg.userContentController.add(self, name: "state")

        let size = petSize.dims
        webView = PetWebView(frame: NSRect(origin: .zero, size: size), configuration: cfg)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")   // 배경 투명
        if #available(macOS 12.0, *) { webView.underPageBackgroundColor = .clear }

        webView.onRightMouse = { [weak self] event in self?.popUpMenu(event) }
        webView.onDoubleClick = { [weak self] in self?.openDashboard() }
        webView.onDragEnd = { [weak self] in self?.saveOrigin() }

        window = PetWindow(contentRect: NSRect(origin: defaultOrigin(size), size: size),
                           styleMask: [.borderless],
                           backing: .buffered,
                           defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView = webView
        applyLevel()
        window.orderFrontRegardless()
        window.ignoresMouseEvents = true   // 좌표를 받기 전엔 통과시켜 둔다
    }

    /// 저장된 위치가 있으면 그걸, 없으면 주 화면 오른쪽 아래
    private func defaultOrigin(_ size: NSSize) -> NSPoint {
        if defaults.object(forKey: Key.originX) != nil {
            let p = NSPoint(x: defaults.double(forKey: Key.originX),
                            y: defaults.double(forKey: Key.originY))
            if NSScreen.screens.contains(where: { $0.frame.intersects(NSRect(origin: p, size: size)) }) {
                return p
            }
        }
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: vf.maxX - size.width - 28, y: vf.minY + 28)
    }

    private func saveOrigin() {
        guard let f = window?.frame else { return }
        defaults.set(Double(f.origin.x), forKey: Key.originX)
        defaults.set(Double(f.origin.y), forKey: Key.originY)
    }

    private func applySize() {
        guard let window else { return }
        let s = petSize.dims
        // 아래쪽을 고정한 채 크기만 바꾼다 (발밑이 안 움직이게)
        let f = window.frame
        window.setFrame(NSRect(x: f.minX, y: f.minY, width: s.width, height: s.height), display: true)
        saveOrigin()
        hitAreas = []
    }

    private func applyLevel() {
        window?.level = alwaysOnTop ? .floating : .normal
        refreshMenu()
    }

    // MARK: 서버 확인 / 실행

    private func ensureServerThenLoad() {
        healthCheck { [weak self] alive in
            guard let self else { return }
            if !alive { self.launchServer() }
            DispatchQueue.main.async { self.webView.load(URLRequest(url: Config.petURL)) }
        }
    }

    private func healthCheck(_ done: @escaping (Bool) -> Void) {
        var req = URLRequest(url: URL(string: "\(Config.base)/healthz")!)
        req.timeoutInterval = 1.2
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200 && data != nil
            done(ok)
        }.resume()
    }

    /// 서버가 안 떠 있으면 직접 띄운다 (build.sh 가 node 경로와 프로젝트 경로를 박아둠)
    private func launchServer() {
        guard let root = Config.root, let node = Config.node,
              FileManager.default.isExecutableFile(atPath: node) else { return }
        let script = (root as NSString).appendingPathComponent("server.js")
        guard FileManager.default.fileExists(atPath: script) else { return }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: node)
        p.arguments = [script]
        p.currentDirectoryURL = URL(fileURLWithPath: root)
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        Thread.sleep(forTimeInterval: 0.8)   // 백그라운드 스레드라 UI를 막지 않는다
    }

    // 서버가 아직 안 떴으면 잠시 뒤 다시 시도
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        retryLoad()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        retryLoad()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        reloadTries = 0
    }

    private func retryLoad() {
        reloadTries += 1
        let delay = min(Double(reloadTries) * 0.7, 5.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if self.reloadTries == 3 { self.launchServerAsync() }
            self.webView.load(URLRequest(url: Config.petURL))
        }
    }

    private func launchServerAsync() {
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.launchServer() }
    }

    // MARK: 웹 → 네이티브

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }

        switch message.name {
        case "hit":
            guard let raw = body["rects"] as? [[String: Any]] else { return }
            hitAreas = raw.compactMap { r in
                guard let x = r["x"] as? Double, let y = r["y"] as? Double,
                      let w = r["w"] as? Double, let h = r["h"] as? Double else { return nil }
                return HitArea(rect: CGRect(x: x, y: y, width: w, height: h),
                               isEllipse: (r["shape"] as? String) == "ellipse")
            }
            updateClickThrough()

        case "state":
            currentState = body["state"] as? String ?? "idle"
            currentLabel = body["label"] as? String ?? ""
            currentEmoji = body["emoji"] as? String ?? "😴"
            currentProject = body["project"] as? String ?? ""
            sessionCount = body["count"] as? Int ?? 0
            statusItem.button?.title = currentEmoji
            refreshMenu()

        default:
            break
        }
    }

    // MARK: 클릭 통과

    private func installMouseMonitors() {
        // 다른 앱을 쓰는 중일 때의 마우스 이동 (마우스 이벤트는 접근성 권한이 필요 없다)
        let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged],
            handler: { [weak self] _ in self?.updateClickThrough() })
        if let global { monitors.append(global) }

        // 커서가 캐릭터 위에 올라와 우리 앱이 직접 이벤트를 받을 때
        let local = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved],
            handler: { [weak self] event -> NSEvent? in
                self?.updateClickThrough()
                return event
            })
        if let local { monitors.append(local) }
    }

    private func updateClickThrough() {
        guard let window else { return }

        if pinnedClickThrough || hitAreas.isEmpty {
            if !window.ignoresMouseEvents { window.ignoresMouseEvents = true }
            return
        }

        let mouse = NSEvent.mouseLocation
        let f = window.frame
        var inside = false

        if f.contains(mouse) {
            // 화면 좌표(좌하단 원점) → 창 안 CSS 좌표(좌상단 원점)
            let local = CGPoint(x: mouse.x - f.minX, y: f.maxY - mouse.y)
            inside = hitAreas.contains { $0.contains(local) }
        }

        if window.ignoresMouseEvents == inside { window.ignoresMouseEvents = !inside }
    }

    // MARK: 메뉴

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = currentEmoji
        statusItem.button?.toolTip = "Claude 마스코트"
        refreshMenu()
    }

    private func refreshMenu() {
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let head = currentProject.isEmpty
            ? "\(currentEmoji)  \(currentLabel)"
            : "\(currentEmoji)  \(currentLabel) · \(currentProject)"
        let headItem = NSMenuItem(title: head, action: nil, keyEquivalent: "")
        headItem.isEnabled = false
        menu.addItem(headItem)

        if sessionCount > 1 {
            let c = NSMenuItem(title: "세션 \(sessionCount)개 실행 중", action: nil, keyEquivalent: "")
            c.isEnabled = false
            menu.addItem(c)
        }

        menu.addItem(.separator())
        menu.addItem(item("대시보드 열기", #selector(openDashboard)))

        menu.addItem(.separator())
        let ct = item("클릭 통과 고정", #selector(toggleClickThrough))
        ct.state = pinnedClickThrough ? .on : .off
        ct.toolTip = "켜면 캐릭터 위에서도 클릭이 아래 창으로 통과합니다 (드래그 불가)"
        menu.addItem(ct)

        let top = item("항상 맨 위", #selector(toggleOnTop))
        top.state = alwaysOnTop ? .on : .off
        menu.addItem(top)

        let sizeItem = NSMenuItem(title: "크기", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for s in PetSize.allCases {
            let mi = item(s.title, #selector(changeSize(_:)))
            mi.representedObject = s.rawValue
            mi.state = (s == petSize) ? .on : .off
            sizeMenu.addItem(mi)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        menu.addItem(item("위치 초기화", #selector(resetPosition)))

        menu.addItem(.separator())
        menu.addItem(item("새로고침", #selector(reloadPet)))
        menu.addItem(item("종료", #selector(quit)))

        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        return mi
    }

    private func popUpMenu(_ event: NSEvent) {
        buildMenu().popUp(positioning: nil,
                          at: webView.convert(event.locationInWindow, from: nil),
                          in: webView)
    }

    // MARK: 메뉴 동작

    @objc private func openDashboard() {
        NSWorkspace.shared.open(Config.dashboardURL)
    }

    @objc private func toggleClickThrough() {
        pinnedClickThrough.toggle()
        refreshMenu()
    }

    @objc private func toggleOnTop() {
        alwaysOnTop.toggle()
    }

    @objc private func changeSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let s = PetSize(rawValue: raw) else { return }
        petSize = s
        refreshMenu()
    }

    @objc private func resetPosition() {
        defaults.removeObject(forKey: Key.originX)
        defaults.removeObject(forKey: Key.originY)
        let s = petSize.dims
        window.setFrameOrigin(defaultOrigin(s))
        saveOrigin()
    }

    @objc private func reloadPet() {
        reloadTries = 0
        ensureServerThenLoad()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - 진입점

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
