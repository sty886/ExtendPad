import AppKit
import ApplicationServices

/// The streamed display's menu bar (PROTOCOL.md 6.18).
///
/// macOS draws a menu bar on every display, but a windowless Finder's desktop menus open on
/// the main display: the menu window cannot be moved (AX position is not settable and the
/// private window move is refused). So in Mirror/Extend the receiver draws the drop-down
/// itself: this service reads the frontmost app's menus through Accessibility, the receiver
/// shows them on the picture, and a press comes back here. Status items and the Apple menu
/// are not app menus: the Mac opens their original AppKit menu and tells the receiver so.
final class BarMenuService: @unchecked Sendable {
    struct Context {
        var inputGranted: @Sendable () -> Bool
        var displayBounds: @Sendable () -> CGRect?
        var frontmostPID: @Sendable () -> pid_t?
        /// Ends a native menu/panel a previous touch left tracking.
        var dismissNativeMenu: @Sendable () -> Void
        var send: @Sendable ([String: Any]) -> Void
    }

    private let context: Context
    // Accessibility calls can wait for a busy app; keep them off the sender's control queue.
    private let queue = DispatchQueue(label: "com.extendpad.bar-menu", qos: .userInitiated)
    /// The app whose menu bar the receiver is currently showing. The bar on the streamed
    /// display can belong to a different app than the globally frontmost one (separate
    /// Spaces); a submenu and a press must stay on the same app the title was read from.
    private var lastMenuPID: pid_t?

    init(context: Context) {
        self.context = context
    }

    func handle(type: String, message: [String: Any]) {
        queue.async { [weak self] in
            guard let self else { return }
            switch type {
            case WireMessage.barMenuRequest: self.read(message)
            case WireMessage.barMenuPress: self.press(message)
            default: break
            }
        }
    }

    private func read(_ message: [String: Any]) {
        let req = message["req"] as? Int
        let path = (message["path"] as? [Int]) ?? []
        guard context.inputGranted() else { return reply(ok: false, error: "control", req: req) }
        // The receiver is about to draw the menu itself: close whatever native tracking a
        // previous status-item/Apple-menu touch (or an earlier failed attempt) left behind.
        context.dismissNativeMenu()

        let point: CGPoint? = {
            guard let x = message["x"] as? Double, let y = message["y"] as? Double,
                  x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y),
                  let bounds = context.displayBounds(), bounds.width > 0, bounds.height > 0 else {
                return nil
            }
            return CGPoint(x: bounds.minX + x * bounds.width,
                           y: bounds.minY + y * bounds.height)
        }()

        // The menu bar on the streamed display can show a different app than the globally
        // frontmost one (separate Spaces: Finder on the extended desktop, another app active
        // on the main display). The AX element at the touched point names the app whose bar
        // copy was actually tapped; using the global frontmost app here read the wrong menus
        // and left the tapped title doing nothing. A submenu comes with the same point, so it
        // stays on that app too.
        let pid = point.flatMap(menuBarPID(at:)) ?? context.frontmostPID()
        guard let pid else { return reply(ok: false, error: "unavailable", req: req) }
        lastMenuPID = pid

        if !path.isEmpty {
            // A submenu of the menu already shown; no hit test or native fallback here.
            guard path.count < AppMenuReader.maxDepth, path[0] >= 1,
                  path.allSatisfy({ $0 >= 0 && $0 < 500 }),
                  let (app, items) = AppMenuReader.items(pid: pid, path: path) else {
                return reply(ok: false, error: "changed", req: req)
            }
            return sendLevel(app: app, title: nil, path: path, items: items, req: req)
        }

        guard let point else { return reply(ok: false, error: "notFound", req: req) }

        // An app menu title on the streamed display's menu bar copy: mirror it. Everything
        // else (status items, the Apple menu, a window) is the original AppKit menu's job.
        guard let target = appMenuTitle(at: point, pid: pid) else {
            // Status items and the Apple menu: the receiver plays the original touch through
            // the normal input path, so the AppKit menu opens exactly as a local click does.
            reply(ok: true, native: true, req: req)
            return
        }
        guard let (app, items) = AppMenuReader.items(pid: pid, path: [target.index]) else {
            return reply(ok: false, error: "unavailable", req: req)
        }
        sendLevel(app: app, title: target.title, path: [target.index], items: items, req: req)
    }

    private func press(_ message: [String: Any]) {
        let req = message["req"] as? Int
        let path = (message["path"] as? [Int]) ?? []
        let titles = ((message["titles"] as? [String]) ?? []).map { String($0.prefix(120)) }
        guard context.inputGranted() else { return replyPress(ok: false, error: "control", req: req) }
        guard let pid = lastMenuPID ?? context.frontmostPID(),
              AppMenuReader.isValidPath(path, titles: titles) else {
            return replyPress(ok: false, error: "notFound", req: req)
        }
        let ok = AppMenuReader.press(pid: pid, path: path, titles: titles)
        replyPress(ok: ok, error: ok ? nil : "changed", req: req)
    }

    /// The frontmost app's menu-bar title under `point`, if that is what is there.
    ///
    /// Geometry, not `AXUIElementCopyElementAtPosition`: that often returns the whole
    /// `AXMenuBar` for a title on a virtual display (the item's text hit area is narrow), and
    /// on another display its element belongs to a different bar copy. The app's own AX menu
    /// bar exposes the titles' exact frames; status items are not its children and fall through.
    /// The app whose menu bar copy is at `point`. Unlike `NSWorkspace.frontmostApplication`,
    /// this stays correct when the extended display's Space shows a different app (Finder on
    /// the desktop) than the globally frontmost one.
    private func menuBarPID(at point: CGPoint) -> pid_t? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.2)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
              let hit,
              DirectTouchMenuRouting.isMenuRole(attribute(hit, kAXRoleAttribute) as? String) else {
            return nil
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success, pid > 0 else { return nil }
        return pid
    }

    private func appMenuTitle(at point: CGPoint, pid: pid_t) -> (index: Int, title: String)? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let bar = element(app, kAXMenuBarAttribute) else { return nil }
        let titles = children(bar)
        let mapped = mappedPoint(point, into: frame(bar))
        for (index, item) in titles.enumerated() where index >= 1 {
            guard let itemFrame = frame(item) else { continue }
            guard itemFrame.contains(point) || mapped.map({ itemFrame.contains($0) }) == true else { continue }
            let title = (attribute(item, kAXTitleAttribute) as? String) ?? ""
            guard !title.isEmpty else { continue }
            return (index, String(title.prefix(120)))
        }
        return nil   // index 0 is the Apple menu, status items are not titles at all
    }

    /// The same point in the menu bar's own display space, when the bar is anchored elsewhere
    /// (menu-bar layout scales with display width).
    private func mappedPoint(_ point: CGPoint, into barFrame: CGRect?) -> CGPoint? {
        guard let barFrame else { return nil }
        var shown = CGDirectDisplayID()
        var shownCount: UInt32 = 0
        var reference = CGDirectDisplayID()
        var referenceCount: UInt32 = 0
        let center = CGPoint(x: barFrame.midX, y: barFrame.midY)
        guard CGGetDisplaysWithPoint(point, 1, &shown, &shownCount) == .success, shownCount == 1,
              CGGetDisplaysWithPoint(center, 1, &reference, &referenceCount) == .success,
              referenceCount == 1, shown != reference else { return nil }
        return DirectTouchMenuRouting.statusItemPoint(at: point, displayFrame: CGDisplayBounds(shown),
                                                       referenceFrame: CGDisplayBounds(reference))
    }

    private func sendLevel(app: String, title: String?, path: [Int], items: [AppMenuItem], req: Int?) {
        var message: [String: Any] = [
            "type": WireMessage.barMenu,
            "ok": true,
            "app": String(app.prefix(80)),
            "path": path,
            "items": items.map(\.wire),
        ]
        if let title { message["title"] = title }
        if let bounds = context.displayBounds(), bounds.height > 0 {
            message["height"] = min(0.2, 30.0 / Double(bounds.height))
        }
        if let req { message["req"] = req }
        context.send(message)
    }

    private func reply(ok: Bool, native: Bool = false, error: String? = nil, req: Int?) {
        var message: [String: Any] = ["type": WireMessage.barMenu, "ok": ok]
        if native { message["native"] = true }
        if let error { message["error"] = error }
        if let req { message["req"] = req }
        context.send(message)
    }

    private func replyPress(ok: Bool, error: String? = nil, req: Int?) {
        var message: [String: Any] = ["type": WireMessage.barMenuResult, "ok": ok]
        if let error { message["error"] = error }
        if let req { message["req"] = req }
        context.send(message)
    }

    // MARK: AX

    private func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)   // swiftlint:disable:this force_cast
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return []
        }
        return (value as? [AXUIElement]) ?? []
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute),
              let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue((position as! AXValue), .cgPoint, &origin),   // swiftlint:disable:this force_cast
              AXValueGetValue((size as! AXValue), .cgSize, &dimensions) else { return nil }   // swiftlint:disable:this force_cast
        return CGRect(origin: origin, size: dimensions)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
