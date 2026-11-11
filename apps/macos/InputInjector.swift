import CoreGraphics
import AppKit
import Darwin

/// System double-click thresholds. Interval is public API; distance is read from
/// AppKit's `NSDoubleClickDistance()` (same value the Window Server uses).
private enum SystemClickMetrics {
    static var interval: TimeInterval { NSEvent.doubleClickInterval }

    static var distance: CGFloat {
        doubleClickDistanceFn?() ?? 4
    }

    private typealias DoubleClickDistanceFn = @convention(c) () -> CGFloat
    private static let doubleClickDistanceFn: DoubleClickDistanceFn? = {
        guard let handle = dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_LAZY),
              let sym = dlsym(handle, "NSDoubleClickDistance") else { return nil }
        return unsafeBitCast(sym, to: DoubleClickDistanceFn.self)
    }()
}

/// Where `InputInjector`'s synthetic events go. The app always posts to the
/// HID event tap; tests record them instead, so grant and revocation paths
/// can be checked end to end without moving the real pointer or typing.
protocol SyntheticEventSink: Sendable {
    func post(_ event: CGEvent)
    func postDirectTouch(_ event: CGEvent)
    /// The gesture is cancelled (capture paused, input revoked, session ending): release any
    /// contact and put back a pointer a menu-bar click moved.
    func cancelDirectTouch()
    /// Ends a native menu/panel tracking session (the receiver is drawing its own menu).
    func dismissMenuOverlay()
}

extension SyntheticEventSink {
    /// Test sinks record the event without needing a real target process.
    func postDirectTouch(_ event: CGEvent) { post(event) }
    func cancelDirectTouch() {}
    func dismissMenuOverlay() {}
}

/// Native Mac menus are tracked by the Window Server rather than the target
/// application's ordinary mouse-event queue. Their accessibility press action
/// opens/chooses the item at the touched point without relocating the cursor.
enum DirectTouchMenuRouting {
    static func isMenuRole(_ role: String?) -> Bool {
        role == kAXMenuBarItemRole as String || role == kAXMenuItemRole as String || role == kAXMenuBarRole as String
    }

    static func preferredAction(_ actions: [String]) -> String? {
        if actions.contains(kAXShowMenuAction as String) { return kAXShowMenuAction as String }
        if actions.contains(kAXPressAction as String) { return kAXPressAction as String }
        return nil
    }

    /// Whether performing [action] on a menu item leaves a native menu-tracking session
    /// running. A successful AXPress on a leaf command performs it and closes the menu;
    /// AXShowMenu (a submenu parent) or a failed/superseded press opens one instead, which
    /// only Escape can end. Per-PID mouse events never reach that session, so an untracked
    /// one freezes the app for every later remote tap.
    static func leavesMenuTracking(action: String, succeeded: Bool, hasSubmenu: Bool) -> Bool {
        !succeeded || hasSubmenu || action != kAXPressAction as String
    }

    /// The menu bar strip at the top of the display containing [point]. Menu-bar AX work
    /// (status items, the app's own menu titles) is only relevant there; doing it for every
    /// tap walked the whole menu bar of the app under the finger and showed up as click
    /// latency while that app was busy.
    static func isMenuBarPoint(_ point: CGPoint) -> Bool {
        var display = CGDirectDisplayID()
        var displayCount: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &display, &displayCount) == .success,
              displayCount == 1 else { return false }
        let displayFrame = CGDisplayBounds(display)
        return point.y >= displayFrame.minY && point.y < displayFrame.minY + 34
    }

    /// An open menu or panel that owns the pointer while it is on screen: a native menu
    /// (pop-up menu level) or Control Center's full-screen panel.
    struct OpenOverlay: Equatable {
        var pid: pid_t
        var frame: CGRect
        var layer: Int
        /// A menu takes its item presses through AX; a panel takes ordinary clicks.
        var isMenu: Bool
    }

    /// Menus are owned by the app whose menu bar item opened them (layer 101, measured on
    /// macOS 26.5). Control Center's panel is Notification Center's full-screen layer-21
    /// window. Both close on Escape without moving the operator's pointer.
    static func openOverlays() -> [OpenOverlay] {
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { info in
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary),
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            if layer == 101 { return OpenOverlay(pid: pid, frame: frame, layer: layer, isMenu: true) }
            guard let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return nil }
            if layer == 21, bundle == "com.apple.notificationcenterui" {
                return OpenOverlay(pid: pid, frame: frame, layer: layer, isMenu: false)
            }
            // Control Center's own popovers (Wi-Fi, Bluetooth, …): taller than its menu-bar chips.
            if layer == 25, bundle == "com.apple.controlcenter", frame.height > 34 {
                return OpenOverlay(pid: pid, frame: frame, layer: layer, isMenu: false)
            }
            return nil
        }
    }

    /// A tap outside an open menu/panel in a *different* app has to dismiss it first.
    /// Taps inside a menu choose from it; taps on the panel's own controls stay in it.
    static func shouldDismissOverlay(at point: CGPoint, targetPID: pid_t?, overlays: [OpenOverlay]) -> Bool {
        guard !overlays.isEmpty else { return false }
        let menus = overlays.filter(\.isMenu)
        if !menus.isEmpty {
            var touched = CGDirectDisplayID()
            var touchedCount: UInt32 = 0
            let touchedOK = CGGetDisplaysWithPoint(point, 1, &touched, &touchedCount) == .success && touchedCount == 1
            let touchedFrame = touchedOK ? CGDisplayBounds(touched) : .zero
            for menu in menus {
                if menu.frame.contains(point) { return false }
                guard touchedOK else { continue }
                var reference = CGDirectDisplayID()
                var referenceCount: UInt32 = 0
                let center = CGPoint(x: menu.frame.midX, y: menu.frame.midY)
                guard CGGetDisplaysWithPoint(center, 1, &reference, &referenceCount) == .success,
                      referenceCount == 1 else { continue }
                if menuContains(menu.frame, point: point, pointDisplay: touchedFrame,
                                frameDisplay: CGDisplayBounds(reference)) { return false }
            }
        }
        if let targetPID, overlays.contains(where: { !$0.isMenu && $0.pid == targetPID }) { return false }
        return true
    }

    /// A native menu is drawn on every display, but its one window can be reported in another
    /// display's coordinate space (menu-bar layout scales with display width). A tap on the
    /// menu's visible copy on the touched display still chooses from it.
    static func menuContains(_ frame: CGRect, point: CGPoint,
                             pointDisplay: CGRect, frameDisplay: CGRect) -> Bool {
        if frame.contains(point) { return true }
        guard let mapped = statusItemPoint(at: point, displayFrame: pointDisplay,
                                           referenceFrame: frameDisplay) else { return false }
        return frame.contains(mapped)
    }

    /// Status items are exposed in the main display's AX coordinate space even
    /// when their visible copy is touched on a secondary display. Their layout
    /// scales with display width; menu-bar thickness stays in display points.
    static func statusItemPoint(
        at point: CGPoint, displayFrame: CGRect, referenceFrame: CGRect
    ) -> CGPoint? {
        guard displayFrame.width > 0, referenceFrame.width > 0 else { return nil }
        return CGPoint(
            x: referenceFrame.minX + (point.x - displayFrame.minX)
                * referenceFrame.width / displayFrame.width,
            y: referenceFrame.minY + point.y - displayFrame.minY)
    }
}

/// Window-level fallback for applications whose UI does not expose an AX hit
/// (custom-rendered views, not only one particular app). CGWindowList is ordered
/// front to back, so the first eligible window containing the point is the one
/// the user sees. System overlays are rejected by the caller's activation policy.
enum DirectTouchWindowTargeting {
    struct Candidate: Equatable {
        var pid: pid_t
        var frame: CGRect
        var layer: Int
        var alpha: Double
        var windowID: UInt32 = 0
    }

    static func target(at point: CGPoint, candidates: [Candidate], ownPID: pid_t) -> Candidate? {
        candidates.first {
            $0.pid != ownPID && $0.layer == 0 && $0.alpha > 0.01 && $0.frame.contains(point)
        }
    }

    static func targetPID(at point: CGPoint, candidates: [Candidate], ownPID: pid_t) -> pid_t? {
        target(at: point, candidates: candidates, ownPID: ownPID)?.pid
    }

    static func target(at point: CGPoint, ownPID: pid_t) -> Candidate? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let candidates = windows.compactMap { info -> Candidate? in
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return Candidate(pid: pid, frame: frame,
                             layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                             alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                             windowID: (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
        }
        return target(at: point, candidates: candidates, ownPID: ownPID)
    }
}

/// Menu extras are drawn in small Control Center-owned windows, even though
/// their AX elements belong to the app that created the status item. Posting
/// to that app cannot generate the tray mouse-up it expects. Resolve the real
/// hosted window so the event follows the same path as a local mouse click.
enum DirectTouchStatusItemTargeting {
    struct Candidate: Equatable {
        var pid: pid_t
        var bundleIdentifier: String
        var frame: CGRect
        var layer: Int
        var alpha: Double
        var windowID: UInt32
    }

    static func target(at point: CGPoint, candidates: [Candidate], ownPID: pid_t) -> Candidate? {
        candidates.first {
            $0.pid != ownPID && $0.bundleIdentifier == "com.apple.controlcenter"
                && $0.layer == 25 && $0.alpha > 0.01 && $0.frame.height <= 34
                && $0.frame.contains(point)
        }
    }

    static func target(at point: CGPoint, ownPID: pid_t) -> Candidate? {
        var display = CGDirectDisplayID()
        var displayCount: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &display, &displayCount) == .success,
              displayCount == 1 else { return nil }
        let displayFrame = CGDisplayBounds(display)
        guard point.y >= displayFrame.minY, point.y < displayFrame.minY + 34 else { return nil }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let candidates = windows.compactMap { info -> Candidate? in
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return Candidate(
                pid: pid,
                bundleIdentifier: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "",
                frame: frame,
                layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                windowID: (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
        }
        return target(at: point, candidates: candidates, ownPID: ownPID)
    }
}

final class HIDEventTapSink: SyntheticEventSink, @unchecked Sendable {
    private typealias SetWindowLocationFn = @convention(c) (CGEvent, Double, Double) -> Void
    private typealias PostToPidFn = @convention(c) (pid_t, CGEvent) -> Void
    // The process-wide dynamic-library handle is immutable after initialization;
    // SkyLight owns its thread safety, just like the other dlopen handles here.
    private nonisolated(unsafe) static let skyLightHandle = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let setWindowLocation: SetWindowLocationFn? = {
        guard let symbol = skyLightHandle.flatMap({ dlsym($0, "CGEventSetWindowLocation") }) else { return nil }
        return unsafeBitCast(symbol, to: SetWindowLocationFn.self)
    }()
    private static let postToPid: PostToPidFn? = {
        guard let symbol = skyLightHandle.flatMap({ dlsym($0, "SLEventPostToPid") }) else { return nil }
        return unsafeBitCast(symbol, to: PostToPidFn.self)
    }()

    // One direct-touch drag stays with the process and window where its finger went down.
    private var directTouchPID: pid_t?
    private var directTouchWindowID: UInt32 = 0
    private var directTouchWindowFrame: CGRect?
    private var directTouchClickGroupID: Int64 = 0
    private var directTouchMenuItem: AXUIElement?
    private var directTouchMenuAction: String?
    private var directTouchStatusItemHost = false
    // Native controls expose AXPress, which clicks without involving the global
    // pointer. Defer their mouse-down until we know whether this is a tap or drag.
    private var directTouchControlItem: AXUIElement?
    private var deferredDirectTouchDown: CGEvent?
    /// The last touch opened a native menu or a status-item panel, so the next touch may have to
    /// dismiss it before it can reach what is underneath. Cleared as soon as no overlay is on screen.
    private var menuMayBeOpen = false
    /// A menu-bar touch is a real HID click, not an AX press: Window Server menu tracking only
    /// follows real events, and it opens the drop-down on the display that was actually clicked.
    /// An AX press opens it on whichever display owns the active AX menu bar, which is why the
    /// menu used to appear on another screen (or just leave the title highlighted). This
    /// gesture moves the cursor for the click and restores it once the menu is used/dismissed.
    private var directTouchMenuBarGesture = false
    private var directTouchMenuBarCursorBefore: CGPoint?

    func post(_ event: CGEvent) {
        // While the Privacy Shield asks for the login password, only this Mac's own input counts;
        // releases still go out so nothing a device held stays stuck down.
        guard !PrivacyShieldWindows.isUnlocking || PrivacyShieldPolicy.postsWhileUnlocking(event.type, flags: event.flags) else { return }
        event.post(tap: .cghidEventTap)
    }

    // AX hit-testing and actions can wait for the target application's run
    // loop. Keep the complete gesture on one serial queue so a slow menu does
    // not block the transport input queue or race the next down/drag/up.
    private let directTouchQueue = DispatchQueue(
        label: "com.extendpad.direct-touch", qos: .userInteractive)
    private static let accessibilityActionTimeout: Float = 0.25

    /// Located events posted to the global HID queue move the real cursor even
    /// when no mouseMoved event is emitted. Direct Touch instead posts to the
    /// application under the finger, leaving the operator's pointer untouched —
    /// except a menu-bar touch, which is a real click on the touched display's
    /// menu bar and puts the pointer back afterwards (`beginMenuBarGesture`).
    func postDirectTouch(_ event: CGEvent) {
        directTouchQueue.async { self.handleDirectTouch(event) }
    }

    func cancelDirectTouch() {
        directTouchQueue.async {
            if self.directTouchMenuBarGesture {
                self.directTouchMenuBarGesture = false
                self.dismissOpenOverlay()
            }
            self.restoreMenuBarCursorIfNeeded()
        }
    }

    func dismissMenuOverlay() {
        directTouchQueue.async {
            self.dismissOpenOverlay()
            self.menuMayBeOpen = false
            self.restoreMenuBarCursorIfNeeded()
        }
    }

    private func handleDirectTouch(_ event: CGEvent) {
        guard !PrivacyShieldWindows.isUnlocking || PrivacyShieldPolicy.postsWhileUnlocking(event.type, flags: event.flags) else { return }
        // The rest of a menu-bar gesture is a real drag/up at the finger's current point, so
        // the native menu tracks the finger exactly as it tracks a local mouse.
        if directTouchMenuBarGesture {
            switch event.type {
            case .leftMouseDragged, .rightMouseDragged:
                CGWarpMouseCursorPosition(event.location)
                post(event)
                return
            case .leftMouseUp, .rightMouseUp:
                CGWarpMouseCursorPosition(event.location)
                post(event)
                directTouchMenuBarGesture = false
                if event.getIntegerValueField(.mouseEventClickState) == 0 {
                    // A cancelled touch (a second finger joined): end any tracking
                    // session and put the local pointer back.
                    dismissOpenOverlay()
                    restoreMenuBarCursorIfNeeded()
                }
                return
            default:
                break
            }
        }
        if (event.type == .leftMouseDown || event.type == .rightMouseDown),
           DirectTouchMenuRouting.isMenuBarPoint(event.location),
           Self.menuBarHasTarget(at: event.location) {
            beginMenuBarGesture(event)
            return
        }
        switch event.type {
        case .leftMouseDown:
            var target = Self.applicationTarget(at: event.location)
            var dismissedMenu = false
            // An open menu/panel owns the pointer: Window Server menu tracking ignores the
            // per-PID mouse events used here, so without this the menu bar stayed dimmed and
            // every later tap was inert. Escape ends that tracking session without moving the
            // operator's pointer; only checked after a touch that may have opened one, so
            // ordinary taps stay cheap. A tracking session can outlive its window (the menu
            // bar title stays highlighted with nothing on screen), so an empty overlay list
            // still means "dismiss" when a menu may be open.
            if menuMayBeOpen {
                let overlays = DirectTouchMenuRouting.openOverlays()
                if overlays.isEmpty || DirectTouchMenuRouting.shouldDismissOverlay(at: event.location, targetPID: target?.pid, overlays: overlays) {
                    dismissOpenOverlay()
                    menuMayBeOpen = false
                    dismissedMenu = true
                    restoreMenuBarCursorIfNeeded()
                    target = Self.applicationTarget(at: event.location)
                } else {
                    menuMayBeOpen = true
                }
            }
            // The touch that dismisses a menu belongs to what is underneath it. Accessibility
            // still answers with the closing menu's items for a few frames, and pressing one
            // (AXPress/AXShowMenu on a menu that is no longer open) makes AppKit open that menu
            // again and park the app in a menu-tracking session remote events can never end —
            // Finder then ignored every later tap until it was restarted. A dismissed tap is
            // therefore an ordinary click on the app, never a menu action.
            let menuItem = dismissedMenu ? nil : target?.menuItem
            let menuAction = dismissedMenu ? nil : target?.menuAction
            let controlItem = dismissedMenu ? nil : target?.controlItem
            let statusItemHost = dismissedMenu ? false : (target?.statusItemHost ?? false)
            menuMayBeOpen = menuMayBeOpen || menuItem != nil || statusItemHost
            directTouchPID = target?.pid
            directTouchWindowID = target?.windowID ?? 0
            directTouchWindowFrame = target?.windowFrame
            directTouchClickGroupID &+= 1
            directTouchMenuItem = menuItem
            directTouchMenuAction = menuAction
            directTouchControlItem = controlItem
            directTouchStatusItemHost = statusItemHost
            deferredDirectTouchDown = directTouchControlItem == nil ? nil : event
            activateTargetIfNeeded()
        case .rightMouseDown:
            var target = Self.applicationTarget(at: event.location)
            if menuMayBeOpen {
                let overlays = DirectTouchMenuRouting.openOverlays()
                if overlays.isEmpty || DirectTouchMenuRouting.shouldDismissOverlay(at: event.location, targetPID: target?.pid, overlays: overlays) {
                    dismissOpenOverlay()
                    menuMayBeOpen = false
                    restoreMenuBarCursorIfNeeded()
                    target = Self.applicationTarget(at: event.location)
                }
            }
            directTouchPID = target?.pid
            directTouchWindowID = target?.windowID ?? 0
            directTouchWindowFrame = target?.windowFrame
            directTouchClickGroupID &+= 1
            directTouchMenuItem = nil
            directTouchMenuAction = nil
            directTouchControlItem = nil
            directTouchStatusItemHost = target?.statusItemHost ?? false
            deferredDirectTouchDown = nil
            // A context menu commonly opens on release; make the next touch check for one.
            menuMayBeOpen = true
            activateTargetIfNeeded()
        case .leftMouseDragged:
            // A drag cancels the deferred AX click. Preserve normal press/drag
            // semantics for controls that can also be dragged.
            if let down = deferredDirectTouchDown {
                directTouchControlItem = nil
                deferredDirectTouchDown = nil
                postDirectTouchToApplication(down)
            }
        default:
            break
        }
        if let menuItem = directTouchMenuItem, let action = directTouchMenuAction {
            // Perform on release, as for an ordinary click. A cancelled touch
            // releases the button but must not invoke the menu command.
            if event.type == .leftMouseUp, event.getIntegerValueField(.mouseEventClickState) != 0 {
                AXUIElementSetMessagingTimeout(menuItem, Self.accessibilityActionTimeout)
                let start = DispatchTime.now().uptimeNanoseconds
                let result = AXUIElementPerformAction(menuItem, action as CFString)
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                Log.info("directTouch: menu action=\(action) pid=\(directTouchPID ?? 0) result=\(result.rawValue) elapsed=\(elapsed)ms")
                // Only a successful AXPress on a leaf command performs it and ends the menu
                // by itself. Pressing an item that owns a submenu, or a press that failed,
                // leaves a tracking session running; remember that so the next touch ends it
                // with Escape instead of pressing a stale item and reopening it forever.
                let submenu = (Self.attribute(menuItem, kAXChildrenAttribute) as? [AXUIElement]) ?? []
                let menuStillOpen = DirectTouchMenuRouting.leavesMenuTracking(
                    action: action, succeeded: result == .success, hasSubmenu: !submenu.isEmpty)
                menuMayBeOpen = menuStillOpen
                if !menuStillOpen {
                    // The menu is used: put the local pointer back where it was before the
                    // menu-bar click moved it.
                    restoreMenuBarCursorIfNeeded()
                }
            }
        } else if let controlItem = directTouchControlItem {
            if event.type == .leftMouseUp, event.getIntegerValueField(.mouseEventClickState) != 0 {
                AXUIElementSetMessagingTimeout(controlItem, Self.accessibilityActionTimeout)
                let result = AXUIElementPerformAction(controlItem, kAXPressAction as CFString)
                Log.info("directTouch: control press pid=\(directTouchPID ?? 0) result=\(result.rawValue)")
            }
        } else if directTouchPID != nil {
            postDirectTouchToApplication(event)
        } else {
            Log.info("directTouch: no application target at \(event.location); event suppressed to keep the cursor stationary")
        }
        if event.type == .leftMouseUp || event.type == .rightMouseUp {
            directTouchPID = nil
            directTouchWindowID = 0
            directTouchWindowFrame = nil
            directTouchMenuItem = nil
            directTouchMenuAction = nil
            directTouchControlItem = nil
            directTouchStatusItemHost = false
            deferredDirectTouchDown = nil
        }
    }

    /// Brings the touched app forward, exactly as a press on its window does. Skipped when it
    /// already is frontmost: the common case for tapping inside the active app, where an
    /// activation round trip per tap only adds latency and window-server churn.
    private func activateTargetIfNeeded() {
        guard let pid = directTouchPID, directTouchMenuItem == nil, !directTouchStatusItemHost,
              NSWorkspace.shared.frontmostApplication?.processIdentifier != pid else { return }
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    }

    /// Ends Window Server menu tracking (a native menu or Control Center's panel) with Escape.
    /// Per-PID mouse events never dismiss it: the menu bar stays dimmed and later taps are
    /// swallowed until a real Escape arrives. Escape moves no pointer, and a menu that is no
    /// longer open simply ignores it.
    private func dismissOpenOverlay() {
        guard !PrivacyShieldWindows.isUnlocking else { return }
        Log.info("directTouch: dismissing an open menu/panel before the tap")
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let key = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: down) else { return }
            key.flags = []
            post(key)
            if down { Thread.sleep(forTimeInterval: 0.02) }
        }
        // A couple of frames for the Window Server to finish closing the menu before the
        // click; measured Escape closes a layer-101 menu well within 60 ms.
        Thread.sleep(forTimeInterval: 0.04)
    }

    /// Whether the top strip of the touched display actually holds a menu title or status
    /// item. The top strip also exists while a full-screen app hides the menu bar; a tap
    /// there must stay an ordinary app tap, never a menu-bar click.
    private static func menuBarHasTarget(at point: CGPoint) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.02)
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
           let hit, DirectTouchMenuRouting.isMenuRole(attribute(hit, kAXRoleAttribute) as? String) {
            return true
        }
        // Some status items (especially on a virtual display) are not returned by
        // element-at-position; their hosted Control Center window still is.
        return DirectTouchStatusItemTargeting.target(at: point, ownPID: getpid()) != nil
    }

    /// Starts a menu-bar touch as a real HID click on the display that was actually touched.
    /// Window Server menu tracking only follows real events, and it anchors the drop-down to
    /// the clicked display; an AX press instead opens it on whichever display owns the active
    /// AX menu bar (so it appeared on another screen, or left the title highlighted with no
    /// menu). The cursor is saved once and restored when the menu is used or dismissed.
    private func beginMenuBarGesture(_ event: CGEvent) {
        // Close a menu that is actually on screen before switching to another title. Do not
        // send Escape when no overlay exists: on an inactive display's Space the first real
        // click activates that Space, and an Escape before it only cancels the activation.
        if !DirectTouchMenuRouting.openOverlays().isEmpty {
            dismissOpenOverlay()
        }
        if directTouchMenuBarCursorBefore == nil {
            directTouchMenuBarCursorBefore = CGEvent(source: nil)?.location
        }
        directTouchMenuBarGesture = true
        menuMayBeOpen = true
        CGWarpMouseCursorPosition(event.location)
        Log.info("directTouch: menu bar click at \(event.location)")
        post(event)
    }

    /// Puts the local pointer back after a menu-bar click, once the menu no longer needs it.
    private func restoreMenuBarCursorIfNeeded() {
        guard let before = directTouchMenuBarCursorBefore else { return }
        directTouchMenuBarCursorBefore = nil
        CGWarpMouseCursorPosition(before)
        Log.info("directTouch: menu bar cursor restored")
    }

    private func postDirectTouchToApplication(_ event: CGEvent) {
        guard let pid = directTouchPID else { return }
        let isRight = event.type == .rightMouseDown || event.type == .rightMouseUp || event.type == .rightMouseDragged
        // Ordinary app events use a fresh source. The hosted status-item path
        // retains HID source state but stays strictly PID/window-directed, so
        // neither variant relocates the operator's visible cursor.
        let eventSource: CGEventSource? = directTouchStatusItemHost
            ? CGEventSource(stateID: .hidSystemState) : nil
        guard let appEvent = CGEvent(mouseEventSource: eventSource, mouseType: event.type,
                                     mouseCursorPosition: event.location,
                                     mouseButton: isRight ? .right : .left) else { return }
        appEvent.flags = event.flags
        stampDirectTouchEvent(appEvent, pid: pid, clickState: event.getIntegerValueField(.mouseEventClickState))
        if event.type == .leftMouseDown || event.type == .rightMouseDown,
           let move = CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved,
                              mouseCursorPosition: event.location, mouseButton: .left) {
            move.flags = event.flags
            stampDirectTouchEvent(move, pid: pid, clickState: 0)
            postEventToApplication(move, pid: pid)
            // Let AppKit's run loop update its hit-test/hover state before the press. Both
            // events are already ordered in the app's queue; one run-loop turn is enough, and
            // every extra millisecond here is latency on every direct touch (a busy app made
            // this queue up under rapid taps).
            Thread.sleep(forTimeInterval: 0.01)
        }
        Log.info("directTouch: app event type=\(event.type.rawValue) pid=\(pid) window=\(directTouchWindowID) hostedStatusItem=\(directTouchStatusItemHost) at=\(event.location)")
        postEventToApplication(appEvent, pid: pid)
        if directTouchStatusItemHost,
           event.type == .leftMouseDown || event.type == .rightMouseDown {
            // Tray handlers open on mouse-up. Keep a real click interval even
            // when the receiver delivers down/up in the same network packet.
            Thread.sleep(forTimeInterval: 0.028)
        }
    }

    private func postEventToApplication(_ event: CGEvent, pid: pid_t) {
        if directTouchStatusItemHost, let postToPid = Self.postToPid {
            postToPid(pid, event)
        } else {
            event.postToPid(pid)
        }
    }

    private func stampDirectTouchEvent(_ event: CGEvent, pid: pid_t, clickState: Int64) {
        let isRight = event.type == .rightMouseDown || event.type == .rightMouseUp || event.type == .rightMouseDragged
        let isDrag = event.type == .leftMouseDragged || event.type == .rightMouseDragged
        let windowID = Int64(directTouchWindowID)
        event.setIntegerValueField(.mouseEventClickState, value: clickState)
        event.setIntegerValueField(.mouseEventButtonNumber, value: isRight ? 1 : 0)
        event.setIntegerValueField(.mouseEventSubtype, value: isDrag ? 0 : 3)
        // NSEvent's window-number bridge and one gesture id must agree across
        // hover/down/drag/up. Custom UI engines use these in addition to 91/92.
        event.setIntegerValueField(CGEventField(rawValue: 51)!, value: windowID)
        event.setIntegerValueField(CGEventField(rawValue: 58)!, value: directTouchClickGroupID)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowID)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowID)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        guard directTouchWindowID != 0, let frame = directTouchWindowFrame else { return }
        // macOS 27 interprets this stamp as window-local. Earlier systems expect
        // the original global point; retaining both branches keeps the app portable.
        let point: CGPoint
        if #available(macOS 27.0, *) {
            point = CGPoint(x: event.location.x - frame.minX, y: event.location.y - frame.minY)
        } else {
            point = event.location
        }
        Self.setWindowLocation?(event, Double(point.x), Double(point.y))
    }

    private static func applicationTarget(at point: CGPoint) -> (pid: pid_t, menuItem: AXUIElement?, menuAction: String?, controlItem: AXUIElement?, windowID: UInt32, windowFrame: CGRect?, statusItemHost: Bool)? {
        let ownPID = getpid()
        if let host = DirectTouchStatusItemTargeting.target(at: point, ownPID: ownPID) {
            return (host.pid, nil, nil, nil, host.windowID, host.frame, true)
        }

        let systemWide = AXUIElementCreateSystemWide()
        // A busy app may not answer AX at all. Keep the per-tap ceiling short: the
        // window/raw-event fallback still delivers the click, while a long timeout here
        // made rapid taps queue behind each other (a tap only lands after its probe).
        // Measured: a healthy AX hit answers in ~1 ms; WeChat on a virtual display fails
        // in ~9 ms. 20 ms leaves room for both without letting a busy app stall the tap.
        AXUIElementSetMessagingTimeout(systemWide, 0.02)
        var hit: AXUIElement?
        AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit)
        var hitPID = pid_t(0)
        let hasHitPID = hit.map { AXUIElementGetPid($0, &hitPID) == .success } ?? false
        let hitRole = hit.flatMap { attribute($0, kAXRoleAttribute) } as? String

        // Never drive our own windows or menu bar item from a remote touch: the
        // menu-bar action re-enters main-actor UI on the direct-touch queue (a real
        // crash in MenuBarPresenceController.togglePopover), and our popover is not
        // part of the captured picture.
        if hasHitPID && hitPID == ownPID {
            Log.info("directTouch: own window or menu bar at \(point); touch suppressed")
            return nil
        }

        if let hit, DirectTouchMenuRouting.isMenuRole(hitRole), hasHitPID,
           let target = menuActionTarget(hit, at: point) {
            return (hitPID, target.element, target.action, nil, 0, nil, false)
        }

        // Some menu-bar items are owned by the Window Server and are not returned
        // by element-at-position, especially on a virtual display. The frontmost
        // application still exposes their exact global AX frames. Resolve that
        // geometric hit instead of falling back to global mouse events. Computed at
        // most once: a full window list is only needed for what this tap will use.
        var windowValue: DirectTouchWindowTargeting.Candidate?
        var windowComputed = false
        func windowTarget() -> DirectTouchWindowTargeting.Candidate? {
            if !windowComputed {
                windowComputed = true
                windowValue = DirectTouchWindowTargeting.target(at: point, ownPID: ownPID).flatMap { candidate in
                    NSRunningApplication(processIdentifier: candidate.pid)?.activationPolicy == .regular ? candidate : nil
                }
            }
            return windowValue
        }
        let pid = hasHitPID ? hitPID : (windowTarget()?.pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
        // Menu-bar work only in a menu bar. This used to walk the touched app's whole AX
        // menu bar for every tap anywhere, which cost real milliseconds and made a busy
        // app (WeChat while switching chats) render for input that never involved it.
        if pid != 0, pid != ownPID, DirectTouchMenuRouting.isMenuBarPoint(point) {
            if let target = statusItemTarget(at: point, preferredPID: pid) {
                return (target.pid, target.element, target.action, nil, 0, nil, false)
            }
            if let menuItem = applicationMenuItem(at: point, pid: pid),
               let action = actionNames(menuItem).flatMap(DirectTouchMenuRouting.preferredAction) {
                return (pid, menuItem, action, nil, 0, nil, false)
            }
        }
        if hasHitPID {
            Log.info("directTouch: application target pid=\(hitPID) role=\(hitRole ?? "nil")")
            let hitWindow = windowTarget().flatMap { $0.pid == hitPID ? $0 : nil }
            return (hitPID, nil, nil, hit.flatMap(pressableControl), hitWindow?.windowID ?? 0, hitWindow?.frame, false)
        }
        if let window = windowTarget() {
            Log.info("directTouch: window target pid=\(window.pid)")
            return (window.pid, nil, nil, nil, window.windowID, window.frame, false)
        }
        return nil
    }

    private static func statusItemTarget(
        at point: CGPoint, preferredPID: pid_t
    ) -> (pid: pid_t, element: AXUIElement, action: String)? {
        var display = CGDirectDisplayID()
        var displayCount: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &display, &displayCount) == .success,
              displayCount == 1 else { return nil }
        let displayFrame = CGDisplayBounds(display)
        guard point.y >= displayFrame.minY, point.y < displayFrame.minY + 34 else { return nil }

        // AX frames migrate between displays as the menu bar is used. Compare
        // each item in its own display's coordinate space rather than assuming
        // that every status item is exposed on the main display.
        let runningPIDs = NSWorkspace.shared.runningApplications.map(\.processIdentifier)
        var visited = Set<pid_t>()
        for candidate in [preferredPID] + runningPIDs {
            guard candidate > 0, candidate != getpid(), visited.insert(candidate).inserted,
                  let item = applicationStatusItem(at: point, displayFrame: displayFrame, pid: candidate),
                  let action = actionNames(item).flatMap(DirectTouchMenuRouting.preferredAction) else { continue }
            return (candidate, item, action)
        }
        return nil
    }

    private static func applicationStatusItem(at point: CGPoint, displayFrame: CGRect, pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.03)
        guard let menuBarValue = attribute(application, "AXExtrasMenuBar") else { return nil }
        let menuBar = menuBarValue as! AXUIElement
        guard let children = attribute(menuBar, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children where DirectTouchMenuRouting.isMenuRole(attribute(child, kAXRoleAttribute) as? String) {
            guard let itemFrame = frame(of: child) else { continue }
            if itemFrame.contains(point) { return child }
            var referenceDisplay = CGDirectDisplayID()
            var displayCount: UInt32 = 0
            let center = CGPoint(x: itemFrame.midX, y: itemFrame.midY)
            guard CGGetDisplaysWithPoint(center, 1, &referenceDisplay, &displayCount) == .success,
                  displayCount == 1,
                  let menuPoint = DirectTouchMenuRouting.statusItemPoint(
                    at: point, displayFrame: displayFrame,
                    referenceFrame: CGDisplayBounds(referenceDisplay)) else { continue }
            if itemFrame.contains(menuPoint) { return child }
        }
        return nil
    }

    private static func applicationMenuItem(at point: CGPoint, pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.03)
        guard let menuBarValue = attribute(application, kAXMenuBarAttribute) else { return nil }
        let menuBar = menuBarValue as! AXUIElement
        guard let menuBarFrame = frame(of: menuBar),
              let children = attribute(menuBar, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        var display = CGDirectDisplayID()
        var displayCount: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &display, &displayCount) == .success,
              displayCount == 1 else { return nil }
        let displayFrame = CGDisplayBounds(display)
        // AppKit exposes the active menu bar's global frame, while macOS draws
        // equivalent menu items on every display. Translate the touched display's
        // local menu-bar point into that AX coordinate space. No cursor warp is
        // involved; this is only geometric element lookup.
        let menuPoint = CGPoint(x: menuBarFrame.minX + point.x - displayFrame.minX,
                                y: menuBarFrame.minY + point.y - displayFrame.minY)
        return children.first { child in
            DirectTouchMenuRouting.isMenuRole(attribute(child, kAXRoleAttribute) as? String)
                && frame(of: child)?.contains(menuPoint) == true
        }
    }

    private static func actionNames(_ element: AXUIElement) -> [String]? {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return nil }
        return names as? [String]
    }

    private static func menuActionTarget(_ element: AXUIElement, at point: CGPoint, depth: Int = 0) -> (element: AXUIElement, action: String)? {
        if let action = actionNames(element).flatMap(DirectTouchMenuRouting.preferredAction) {
            return (element, action)
        }
        guard depth < 2, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children where frame(of: child)?.contains(point) == true {
            if let target = menuActionTarget(child, at: point, depth: depth + 1) { return target }
        }
        return nil
    }

    private static func pressableControl(_ element: AXUIElement) -> AXUIElement? {
        var current = element
        for _ in 0..<6 {
            if actionNames(current)?.contains(kAXPressAction as String) == true { return current }
            if (attribute(current, kAXRoleAttribute) as? String) == kAXWindowRole as String { return nil }
            guard let parent = attribute(current, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            let next = parent as! AXUIElement   // swiftlint:disable:this force_cast
            if CFEqual(current, next) { return nil }
            current = next
        }
        return nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(element, kAXPositionAttribute),
              let sizeValue = attribute(element, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetType(positionValue as! AXValue) == .cgPoint,
              AXValueGetType(sizeValue as! AXValue) == .cgSize,
              AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

/// Turns normalized touch coordinates from the phone into mouse events on a
/// target display. Touch semantics: finger down = left button down, finger
/// move = drag, finger up = button up — i.e. the phone acts as a touchscreen.
final class InputInjector {

    private let eventSink: SyntheticEventSink
    private let displayID: CGDirectDisplayID
    // This session's ephemeral input grant (per-device-session milestone) —
    // shared with the owning `MacSender`'s own control-message-level gate so
    // both read the exact same bit under the same lock. See
    // `SessionInputGrantBox`'s doc comment for why a plain shared `Bool`
    // isn't safe here.
    private let sessionInputGrant: SessionInputGrantBox
    // Preference changes arrive on the main actor; receiver messages arrive on
    // Network's callback queue. Serialize them so cancellation cannot race a
    // new synthetic down event.
    private let inputLock = NSRecursiveLock()
    private var isDown = false
    private var penDown = false
    // M7 pointer/click wire (pv 5): which synthetic mouse button, if any,
    // `PointerGestureEngine` currently holds down, plus the click count its
    // `mouseDown` carried — every subsequent move/drag/up event echoes that
    // same clickState, matching the CGEvent convention AppKit/WebKit expect
    // across one press.
    private var pointerHeldButton: CGMouseButton?
    private var pointerHeldClickCount: Int64 = 1
    // Direct Touch remembers the touched point for the subsequent button
    // events. Hover is deliberately not posted: the Mac's visible arrow must
    // stay where the local user left it, throughout the touch, not warp and
    // then be restored afterwards. The one exception is a menu-bar touch,
    // which needs a real click on the touched display (see
    // `HIDEventTapSink.beginMenuBarGesture`). Relative/trackpad input clears this.
    private var absolutePointerLocation: CGPoint?
    // A real event source (vs nil) plus non-zero clickState on down/up: menu
    // tracking treats sourceless/zero-click synthetic clicks as malformed — menus
    // open but their tracking session breaks, leaving zombie menu windows
    // composited on the display (visible in the stream, unclickable).
    private let source = CGEventSource(stateID: .hidSystemState)
    // Synthetic OpenDisplay tablet — conspicuous in logs; not Wacom (0x056A) or
    // typical small driver IDs (1, 2, …).
    private let tabletVendorID: Int64 = 0x0D15       // "ODIS"
    private let tabletProductID: Int64 = 0x0101
    private let deviceID: Int64 = 424242
    private let pointerID: Int64 = 0x0D02              // pen tip
    private let vendorPointerType: Int64 = 0x0802    // Grip Pen (what apps expect)
    private let capabilityMask: Int64 = 0x05C7       // pressure + tilt + rotation + buttons
    private var inRange = false

    // Pencil-only synthetic click counting — tablet events don't get click
    // state from the Window Server, so we mirror macOS double-click prefs here.
    private struct PenClickSession {
        let downLocation: CGPoint
        let clickState: Int
    }

    private struct PenCompletedClick {
        let upTime: CFAbsoluteTime
        let downLocation: CGPoint
        let clickState: Int
    }

    private var penClickSession: PenClickSession?
    private var penLastClick: PenCompletedClick?

    // Hardware keys currently held down (M4) — released on cancellation so a
    // dropped session can never leave a modifier or arrow key stuck.
    private var heldKeys = HeldKeyTracker()
    private var scrollRemainder = ScrollRemainder()
    private var heldModifiers = HeldModifierTracker()

    // Window mode: maps canvas points to the right Mac window, or to
    // nothing. Nil for Mirror/Extend, where the canvas is one display.
    private var targetMapper: InputTargetMapper?
    // A mapped point for the tablet path, which positions by `screenPoint`.
    private var mappedOverride: CGPoint?

    /// Install or remove the window-workspace mapper. Held input is released
    /// first: nothing pressed under one mapping is released under another.
    func setTargetMapper(_ mapper: InputTargetMapper?) {
        inputLock.lock()
        defer { inputLock.unlock() }
        cancelActiveInputLocked()
        targetMapper = mapper
    }

    /// Window mode keyboard gate: keys only reach the active tile's window.
    ///
    /// The mapper is read under `inputLock`, but the Accessibility query runs
    /// outside it: `keyboardTargetReady()` can block for up to its 100ms
    /// messaging timeout on a busy target app, and holding the input lock
    /// across that stalls every keyboard event behind it.
    private func keyboardTargetReady() -> Bool {
        let mapper = inputLock.withLock { targetMapper }
        return mapper?.keyboardTargetReady() ?? true
    }

    init(displayID: CGDirectDisplayID, sessionInputGrant: SessionInputGrantBox,
         eventSink: SyntheticEventSink = HIDEventTapSink()) {
        self.displayID = displayID
        self.sessionInputGrant = sessionInputGrant
        self.eventSink = eventSink
    }

    /// The display this injector targets, in global CG coordinates. Used by the receiver-drawn
    /// menu bar (PROTOCOL.md 6.18) to map a normalized touch back to a menu-bar point.
    var displayBounds: CGRect { CGDisplayBounds(displayID) }

    /// Ends a native menu/panel a previous touch left tracking, before the receiver draws its
    /// own menu for the same title.
    func dismissOpenMenu() { eventSink.dismissMenuOverlay() }

    /// Release every synthetic contact when capture is paused, torn down,
    /// or input is disabled while a gesture is active.
    func cancelActiveInput() {
        inputLock.lock()
        defer { inputLock.unlock() }
        cancelActiveInputLocked()
    }

    /// Caller must already hold inputLock.
    private func cancelActiveInputLocked() {
        let point = absolutePointerLocation ?? currentCursor()
        scrollRemainder.reset()

        if isDown {
            if let event = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: point,
                mouseButton: .left
            ) {
                event.setIntegerValueField(.mouseEventClickState, value: 0)
                postInputEvent(event)
            }
            isDown = false
        }

        // M7: release whichever pointer-engine button (left or right) is
        // currently held. This is the stuck-button safety net for the
        // absolute/precision/chord pointer model — it MUST run on
        // disconnect, input-disable, pause, and gesture-ownership takeover,
        // exactly like the legacy touch `isDown` release above.
        if let button = pointerHeldButton {
            let type: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
            if let event = CGEvent(mouseEventSource: source, mouseType: type,
                                   mouseCursorPosition: point, mouseButton: button) {
                event.setIntegerValueField(.mouseEventClickState, value: pointerHeldClickCount)
                postInputEvent(event)
                pointerHeldButton = nil
            }
        }
        // Ordinary Direct Touch never moved the visible arrow. A menu-bar
        // click did (that is what makes the native menu open on the touched
        // display), so let the sink put it back and end any tracking session.
        absolutePointerLocation = nil
        eventSink.cancelDirectTouch()

        if penDown {
            penClickSession = nil
            postTabletPoint(
                phase: .up,
                x: nil,
                y: nil,
                pressure: 0,
                tiltX: 0,
                tiltY: 0,
                rotation: 0,
                cancelClick: true
            )
            penDown = false
        }

        if inRange {
            setProximity(entering: false, at: point)
        }

        penClickSession = nil
        penLastClick = nil

        for usage in heldKeys.releaseAll() {
            postKeyEvent(keyCode: usage.keyCode, keyDown: false, flags: heldModifiers.flags)
        }
        for modifier in heldModifiers.releaseAll() {
            postKeyEvent(keyCode: modifier.keyCode, keyDown: false, flags: heldModifiers.flags)
        }
    }

    static func ensureAccessibilityPermission() -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            Log.info("Accessibility permission missing — prompt requested")
        }
        return trusted
    }

    /// x/y are normalized [0,1] in video space (origin top-left).
    func handleTouch(phase: String, x: Double, y: Double) {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputIsAllowed() else { return }
        let point: CGPoint
        if let mapper = targetMapper {
            let mapPhase: InputMapPhase = phase == "began" ? .down : (phase == "moved" ? (isDown ? .drag : .hover) : .up)
            if let mapped = mapper.mapPointer(phase: mapPhase, x: x, y: y, dx: 0, dy: 0) {
                point = mapped
            } else if mapPhase == .up, isDown {
                point = currentCursor()   // always release what was pressed
            } else {
                return
            }
        } else {
            let bounds = CGDisplayBounds(displayID)   // global CG coords, y-down
            point = InputCoordinateMapper.point(x: x, y: y, in: bounds)
            absolutePointerLocation = point
            // A hover-only absolute update (used to seed Direct Touch scroll)
            // must not move the visible arrow. Button/drag events still carry
            // their own absolute location and act at the touched point.
            if phase == "moved", !isDown { return }
        }

        let type: CGEventType
        // Click count on the release. A cancel means "a second finger joined,
        // this was a scroll, not a tap" — but there is no CGEvent for undoing a
        // press, and a plain up over the press point is indistinguishable from a
        // click, so every two-finger scroll opened whatever was under finger one.
        // Releasing with clickCount 0 keeps the button state honest while telling
        // AppKit and WebKit not to synthesize a click. Only the cancel path gets
        // 0: a zero-click *down* is what breaks menu tracking (see above).
        var clickState = 1
        switch phase {
        case "began":
            type = .leftMouseDown
            isDown = true
        case "moved":
            type = isDown ? .leftMouseDragged : .mouseMoved
        case "ended":
            guard isDown else { return }   // spurious up without a down
            type = .leftMouseUp
            isDown = false
        case "cancelled":
            guard isDown else { return }
            type = .leftMouseUp
            isDown = false
            clickState = 0
        default:
            return
        }

        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        // See `MouseEventFlags`'s doc: never let a touch tap silently
        // inherit ambient/global modifier state left over from some other
        // synthetic event (e.g. a system-gesture keyboard shortcut) —
        // always state explicitly what this click intentionally carries.
        event.flags = heldModifiers.flags
        postInputEvent(event)
        if targetMapper == nil, phase == "ended" || phase == "cancelled" {
            absolutePointerLocation = nil
        }
    }

    /// dx/dy in display pixels, natural-scrolling sign from the phone.
    /// Scroll events take points, so convert via the display's pixel scale.
    func handleScroll(dx: Double, dy: Double) {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputIsAllowed() else { return }
        let whole: (dx: Int32, dy: Int32)
        if let mapper = targetMapper {
            // The tile under the workspace pointer, only where its window is
            // frontmost; the Mac pointer moves onto it first (no focus change).
            guard let p = mapper.mapPointer(phase: .scroll, x: nil, y: nil, dx: 0, dy: 0) else { return }
            let here = currentCursor()
            if pointerHeldButton == nil, !isDown, abs(here.x - p.x) > 1 || abs(here.y - p.y) > 1,
               let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left) {
                move.flags = heldModifiers.flags
                eventSink.post(move)
            }
            let v = mapper.scrollVector(dx: dx, dy: dy)
            whole = scrollRemainder.take(dxPoints: v.dx, dyPoints: v.dy)
        } else {
            let bounds = CGDisplayBounds(displayID)
            let scale = bounds.width > 0 ? Double(CGDisplayPixelsWide(displayID)) / bounds.width : 2
            whole = scrollRemainder.take(dxPoints: dx / scale, dyPoints: dy / scale)
        }
        guard whole.dx != 0 || whole.dy != 0 else { return }
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                                  wheelCount: 2,
                                  wheel1: whole.dy,
                                  wheel2: whole.dx,
                                  wheel3: 0) else { return }
        // Direct Touch never moves the Mac's visible pointer, so a wheel event left at the
        // cursor's location would scroll whatever window the operator's own pointer is over.
        // The Window Server routes wheel events by location: aim it at the touched content.
        if targetMapper == nil, let touched = absolutePointerLocation {
            event.location = touched
        }
        event.flags = heldModifiers.flags   // see `MouseEventFlags`'s doc
        postInputEvent(event)
    }

    // MARK: - Pointer / click gestures (M7)

    /// Absolute Direct Touch location. With no button held this only records
    /// where the eventual down/up must act: posting `mouseMoved` here would
    /// teleport the Mac's visible arrow. During a drag, the absolute drag
    /// events carry each new location without a separate hover move.
    func handlePointerMove(x: Double, y: Double) {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputIsAllowed() else { return }
        if let mapper = targetMapper {
            guard let point = mapper.mapPointer(phase: pointerHeldButton == nil ? .hover : .drag, x: x, y: y, dx: 0, dy: 0) else { return }
            postPointerMotion(to: point)
            return
        }
        let bounds = CGDisplayBounds(displayID)
        let point = InputCoordinateMapper.point(x: x, y: y, in: bounds)
        absolutePointerLocation = point
        guard pointerHeldButton != nil else { return }
        postPointerMotion(to: point)
    }

    /// Relative cursor move (`PointerCommand.moveRelative`) — `dx`/`dy` in
    /// video pixels, same convention as `handleScroll`. Moves from the
    /// Mac's own current cursor position, never the touch location.
    func handlePointerMoveRelative(dx: Double, dy: Double) {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputIsAllowed() else { return }
        // A single event is bounded; a peer cannot fling the pointer through
        // an unrepresentable coordinate or amplify its own deltas.
        let dx = InputSanitizer.finite(dx, limit: 100_000) ?? 0
        let dy = InputSanitizer.finite(dy, limit: 100_000) ?? 0
        absolutePointerLocation = nil
        if let mapper = targetMapper {
            // The workspace pointer moves freely across tiles; the Mac pointer
            // follows only where that is safe (see WorkspaceInputTargeting).
            guard let point = mapper.mapPointer(phase: pointerHeldButton == nil ? .hover : .drag, x: nil, y: nil, dx: dx, dy: dy) else { return }
            postPointerMotion(to: point)
            return
        }
        let bounds = CGDisplayBounds(displayID)
        let scale = bounds.width > 0 ? Double(CGDisplayPixelsWide(displayID)) / bounds.width : 2
        let current = currentCursor()
        let point = CGPoint(x: current.x + dx / scale, y: current.y + dy / scale)
        postPointerMotion(to: point)
    }

    private func postPointerMotion(to point: CGPoint) {
        let type: CGEventType
        let button: CGMouseButton
        if let held = pointerHeldButton {
            type = held == .left ? .leftMouseDragged : .rightMouseDragged
            button = held
        } else {
            type = .mouseMoved
            button = .left
        }
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else { return }
        if pointerHeldButton != nil {
            event.setIntegerValueField(.mouseEventClickState, value: pointerHeldClickCount)
        }
        event.flags = heldModifiers.flags   // see `MouseEventFlags`'s doc
        postInputEvent(event)
    }

    /// Presses at the recorded Direct Touch point, or at the real cursor for
    /// relative/trackpad input. The button event's location does not require
    /// a preliminary visible cursor move.
    func handlePointerDown(button: PointerButton, clickCount: Int) {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputIsAllowed() else { return }
        guard pointerHeldButton == nil else { return }
        let cgButton: CGMouseButton = button == .left ? .left : .right
        let type: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        let point: CGPoint
        if let mapper = targetMapper {
            guard let mapped = mapper.mapPointer(phase: .down, x: nil, y: nil, dx: 0, dy: 0) else { return }
            point = mapped
        } else {
            point = absolutePointerLocation ?? currentCursor()
        }
        let clickState = Int64(InputSanitizer.clickCount(clickCount))
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: cgButton) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: clickState)
        // See `MouseEventFlags`'s doc: a plain click carries exactly
        // OpenDisplay's own intentionally-held modifiers (empty, unless the
        // control tray latched one) — never whatever ambient/global
        // modifier state happens to be set from an unrelated synthetic
        // event (e.g. a system-gesture keyboard shortcut still reporting
        // Control down), which a left-unset `.flags` would otherwise
        // silently inherit and macOS could read as a Control-click.
        event.flags = heldModifiers.flags
        postInputEvent(event)
        pointerHeldButton = cgButton
        pointerHeldClickCount = clickState
    }

    /// Releases at the same synthetic Direct Touch target. No restoration
    /// event follows an ordinary touch: the real Mac arrow stayed at its
    /// original location. (A menu-bar click restores it through the sink's
    /// `restoreMenuBarCursorIfNeeded`.)
    func handlePointerUp(button: PointerButton, clickCount: Int) {
        inputLock.lock()
        defer { inputLock.unlock() }
        // No `inputIsAllowed()` gate on the up path: an up matching a
        // down already posted must always be free to release the button,
        // exactly like legacy touch's `"ended"`/`"cancelled"` handling.
        let cgButton: CGMouseButton = button == .left ? .left : .right
        // Window mode: the release always ends the workspace's drag binding,
        // even when its press was refused (nothing was pressed on the Mac).
        let mapped = targetMapper?.mapPointer(phase: .up, x: nil, y: nil, dx: 0, dy: 0)
        guard pointerHeldButton == cgButton else { return }   // no matching down (already released)
        let type: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
        let point = mapped ?? absolutePointerLocation ?? currentCursor()
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: cgButton) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(InputSanitizer.clickCount(clickCount)))
        event.flags = heldModifiers.flags   // see `MouseEventFlags`'s doc
        postInputEvent(event)
        pointerHeldButton = nil
        absolutePointerLocation = nil
    }

    func handleProximity(entering: Bool, x: Double, y: Double) {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputIsAllowed() else { return }
        if let mapper = targetMapper {
            guard let p = mapper.mapPointer(phase: .hover, x: x, y: y, dx: 0, dy: 0) else { return }
            setProximity(entering: entering, at: p)
            return
        }
        setProximity(entering: entering, at: screenPoint(nx: x, ny: y))
    }

    // MARK: - Keyboard (M4)

    /// Committed Unicode text from the software/hardware keyboard's text
    /// path. Injected as one paired key-down/up carrying the whole string,
    /// so multi-scalar clusters (emoji, accented composed characters) post
    /// as a single event pair.
    func handleKeyboardText(_ text: String) {
        let targetReady = keyboardTargetReady()
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputIsAllowed(), targetReady, let units = KeyboardTextPlanner.plan(text) else { return }
        postUnicodeText(units)
    }

    /// An atomic special key from the software keyboard (no held state to
    /// track — down and up post back to back).
    func handleKeyboardPress(_ usage: HIDKeyUsage, modifiers: [String] = []) {
        let targetReady = keyboardTargetReady()
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputIsAllowed(), targetReady else { return }
        let flags = KeyModifier.flags(named: modifiers).union(heldModifiers.flags)
        #if DEBUG
        if usage == .deleteOrBackspace {
            Log.info("keyboardDebug: posting usage=42 keyCode=\(usage.keyCode) down")
        }
        #endif
        postKeyEvent(keyCode: usage.keyCode, keyDown: true, flags: flags)
        #if DEBUG
        if usage == .deleteOrBackspace {
            Log.info("keyboardDebug: posting usage=42 keyCode=\(usage.keyCode) up")
        }
        #endif
        postKeyEvent(keyCode: usage.keyCode, keyDown: false, flags: flags)
    }

    func handleModifier(name: String, down: Bool) {
        let targetReady = down ? keyboardTargetReady() : true
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputIsAllowed(), let modifier = ControlModifier(rawValue: name) else { return }
        if down {
            guard targetReady, heldModifiers.down(modifier) else { return }
            postKeyEvent(keyCode: modifier.keyCode, keyDown: true, flags: heldModifiers.flags)
        } else {
            guard heldModifiers.up(modifier) else { return }
            postKeyEvent(keyCode: modifier.keyCode, keyDown: false, flags: heldModifiers.flags)
        }
    }

    /// A hardware key going down. A duplicate down for an already-held key
    /// is ignored rather than re-posted — unless it is marked `repeat` (a
    /// receiving Mac's own key repeat), which posts an auto-repeat key-down
    /// for the held key.
    func handleKeyboardDown(usage: HIDKeyUsage, modifiers: [String], isRepeat: Bool = false) {
        let targetReady = keyboardTargetReady()
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputIsAllowed(), targetReady else { return }
        let flags = KeyModifier.flags(named: modifiers).union(heldModifiers.flags)
        if isRepeat {
            guard heldKeys.allowsRepeat(usage) else { return }
            postKeyEvent(keyCode: usage.keyCode, keyDown: true, flags: flags, autorepeat: true)
            return
        }
        guard heldKeys.down(usage) else { return }
        postKeyEvent(keyCode: usage.keyCode, keyDown: true, flags: flags)
    }

    /// The matching release. A spurious up for a key that isn't held (e.g.
    /// after cancellation already released it) is ignored.
    func handleKeyboardUp(usage: HIDKeyUsage, modifiers: [String]) {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard heldKeys.up(usage) else { return }
        postKeyEvent(keyCode: usage.keyCode, keyDown: false,
                     flags: KeyModifier.flags(named: modifiers).union(heldModifiers.flags))
    }

    private func postInputEvent(_ event: CGEvent) {
        if targetMapper == nil, absolutePointerLocation != nil {
            switch event.type {
            case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .leftMouseDragged, .rightMouseDragged:
                eventSink.postDirectTouch(event)
                return
            default:
                break
            }
        }
        eventSink.post(event)
    }

    private func postKeyEvent(keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags, autorepeat: Bool = false) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { return }
        event.flags = flags
        if autorepeat { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        postInputEvent(event)
    }

    /// Attaching the Unicode string to both the key-down and key-up events is
    /// the conventional pattern for `CGEventKeyboardSetUnicodeString`
    /// (mirrored by, among others, Apple's own Quartz Event Services sample
    /// code and every widely used open-source Unicode-typing utility built
    /// on this API): text insertion is driven by the *key-down* event alone
    /// — `keyUp` is never routed through `insertText:`/IME processing, so
    /// carrying the string there cannot cause a second insertion. It matters
    /// only because some apps read the string back off whichever event they
    /// inspect (e.g. matching a down/up pair by content for key-repeat or
    /// event-tap logic); omitting it from `up` risks that pairing seeing a
    /// down for one character and an empty up, not a correctness issue for
    /// insertion itself. Post as one down/up pair per commit either way.
    ///
    /// `.flags` is set explicitly to `KeyboardTextFlags.committed` (always
    /// empty) rather than left at whatever `CGEventCreateKeyboardEvent`
    /// defaults to for this event source — a real-device incident showed
    /// plain typed text ("t") acting as a Command shortcut (Chrome opened a
    /// new tab) after a modified hardware key combo, because an unset
    /// `.flags` on a `.hidSystemState`-sourced event can inherit whatever
    /// modifier state is currently ambient rather than reading as "none".
    /// Committed text must never carry a modifier regardless of what any
    /// other key event recently posted, so both events state that
    /// explicitly instead of relying on a default.
    private func postUnicodeText(_ units: [unichar]) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
        down.flags = KeyboardTextFlags.committed
        up.flags = KeyboardTextFlags.committed
        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        eventSink.post(down)
        eventSink.post(up)
    }

    /// The control-message gate is duplicated here under the input lock so an
    /// OFF transition cannot race an event that already passed its outer gate.
    /// A login session that is switched out (Fast User Switching) never
    /// injects: someone else is using the Mac (`LoginSessionConsole`).
    private func inputIsAllowed() -> Bool {
        guard EffectiveInputAuthorization.allowed(masterEnabled: InputPolicy.allowsInput(),
                                                   sessionGranted: sessionInputGrant.get()),
              LoginSessionConsole.shared.isOnConsole else {
            cancelActiveInputLocked()
            return false
        }
        return true
    }

    func handlePencil(phase: String, x: Double, y: Double,
                      pressure: Double, azimuth: Double, altitude: Double,
                      rotation: Double) {
        inputLock.lock()
        defer { inputLock.unlock() }
        guard inputIsAllowed() else { return }
        // TODO: Wire Apple Pencil Pro barrel roll (UIKit rollAngle) once hardware
        // is available for testing. rotation on the wire is always 0 for now.
        _ = rotation
        if let mapper = targetMapper {
            let mapPhase: InputMapPhase
            switch phase {
            case "down": mapPhase = .down
            case "move": mapPhase = penDown ? .drag : .hover
            case "up": mapPhase = .up
            default: mapPhase = .hover
            }
            if let mapped = mapper.mapPointer(phase: mapPhase, x: x, y: y, dx: 0, dy: 0) {
                mappedOverride = mapped
            } else if mapPhase == .up, penDown {
                mappedOverride = currentCursor()
            } else {
                return
            }
        }
        defer { mappedOverride = nil }
        let p = screenPoint(nx: x, ny: y)
        if phase == "down", !inRange {
            setProximity(entering: true, at: p)
        }
        let (tiltX, tiltY) = deriveTilt(azimuth: azimuth, altitude: altitude)

        switch phase {
        case "down":
            postTabletPoint(phase: .down, x: x, y: y, pressure: pressure,
                            tiltX: tiltX, tiltY: tiltY, rotation: 0)
            penDown = true
        case "move":
            if penDown {
                postTabletPoint(phase: .drag, x: x, y: y, pressure: pressure,
                                tiltX: tiltX, tiltY: tiltY, rotation: 0)
            } else {
                postTabletPoint(phase: .hover, x: x, y: y, pressure: 0,
                                tiltX: tiltX, tiltY: tiltY, rotation: 0)
            }
        case "up":
            if penDown {
                postTabletPoint(phase: .up, x: x, y: y, pressure: 0,
                                tiltX: tiltX, tiltY: tiltY, rotation: 0)
                penDown = false
            }
        case "hover":
            if penDown {
                postTabletPoint(phase: .up, x: x, y: y, pressure: 0,
                                tiltX: tiltX, tiltY: tiltY, rotation: 0)
                penDown = false
            }
            postTabletPoint(phase: .hover, x: x, y: y, pressure: 0,
                            tiltX: tiltX, tiltY: tiltY, rotation: 0)
        default:
            return
        }
    }

    private func setProximity(entering: Bool, at p: CGPoint) {
        guard entering != inRange else { return }
        inRange = entering
        postProximityEvent(entering: entering, at: p)
    }

    private func postProximityEvent(entering: Bool, at p: CGPoint) {
        guard let ev = CGEvent(source: source) else { return }
        ev.type = .tabletProximity
        ev.location = p
        ev.setIntegerValueField(.tabletProximityEventVendorID, value: tabletVendorID)
        ev.setIntegerValueField(.tabletProximityEventTabletID, value: tabletProductID)
        ev.setIntegerValueField(.tabletProximityEventPointerID, value: pointerID)
        ev.setIntegerValueField(.tabletProximityEventDeviceID, value: deviceID)
        ev.setIntegerValueField(.tabletProximityEventSystemTabletID, value: 0)
        ev.setIntegerValueField(.tabletProximityEventPointerType, value: entering ? 1 : 0)
        ev.setIntegerValueField(.tabletProximityEventVendorPointerType, value: vendorPointerType)
        ev.setIntegerValueField(.tabletProximityEventCapabilityMask, value: capabilityMask)
        ev.setIntegerValueField(.tabletProximityEventEnterProximity, value: entering ? 1 : 0)
        ev.flags = .maskNonCoalesced
        eventSink.post(ev)
    }

    private enum PointPhase { case down, drag, up, hover }

    private func postTabletPoint(phase: PointPhase, x: Double?, y: Double?,
                                 pressure: Double, tiltX: Double, tiltY: Double,
                                 rotation: Double, cancelClick: Bool = false) {
        let p: CGPoint
        if let nx = x, let ny = y { p = screenPoint(nx: nx, ny: ny) }
        else { p = currentCursor() }

        let type: CGEventType
        switch phase {
        case .down:  type = .leftMouseDown
        case .drag:  type = .leftMouseDragged
        case .up:    type = .leftMouseUp
        case .hover: type = .mouseMoved
        }

        guard let ev = CGEvent(mouseEventSource: source, mouseType: type,
                               mouseCursorPosition: p, mouseButton: .left) else { return }
        ev.setIntegerValueField(.mouseEventDeltaX, value: 0)
        ev.setIntegerValueField(.mouseEventDeltaY, value: 0)
        ev.setIntegerValueField(.mouseEventSubtype, value: Int64(CGEventMouseSubtype.tabletPoint.rawValue))
        ev.setIntegerValueField(.tabletEventDeviceID, value: deviceID)
        // Wire pressure is untrusted: clamp before the Double→Int64
        // conversion, which traps on an out-of-range value and would take
        // the whole sender down.
        let boundedPressure = InputSanitizer.pressure(pressure)
        ev.setDoubleValueField(.mouseEventPressure, value: boundedPressure)
        ev.setIntegerValueField(.tabletEventPointPressure,
                                value: Int64((boundedPressure * 65535.0).rounded()))
        ev.setDoubleValueField(.tabletEventTiltX, value: tiltX)
        ev.setDoubleValueField(.tabletEventTiltY, value: tiltY)
        ev.setDoubleValueField(.tabletEventRotation, value: rotation)
        switch phase {
        case .down:
            ev.setIntegerValueField(.mouseEventClickState, value: Int64(beginPenClickSession(at: p)))
        case .up:
            let clickState = cancelClick ? 0 : finishPenClickSession(at: p)
            ev.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        case .drag, .hover:
            break
        }
        ev.flags = .maskNonCoalesced
        eventSink.post(ev)
    }

    private func penClickStateForMouseDown(at point: CGPoint) -> Int {
        let now = CFAbsoluteTimeGetCurrent()
        guard let last = penLastClick,
              now - last.upTime <= SystemClickMetrics.interval else {
            return 1
        }
        let dx = point.x - last.downLocation.x
        let dy = point.y - last.downLocation.y
        guard hypot(dx, dy) <= SystemClickMetrics.distance else { return 1 }
        return last.clickState + 1
    }

    private func beginPenClickSession(at point: CGPoint) -> Int {
        let state = penClickStateForMouseDown(at: point)
        penClickSession = PenClickSession(downLocation: point, clickState: state)
        return state
    }

    /// Returns click state for the matching pen mouse-up. Extends the multi-click
    /// chain only when down→up displacement is within the system threshold.
    private func finishPenClickSession(at upLocation: CGPoint) -> Int {
        guard let session = penClickSession else { return 1 }
        penClickSession = nil

        let dx = upLocation.x - session.downLocation.x
        let dy = upLocation.y - session.downLocation.y
        if hypot(dx, dy) <= SystemClickMetrics.distance {
            penLastClick = PenCompletedClick(
                upTime: CFAbsoluteTimeGetCurrent(),
                downLocation: session.downLocation,
                clickState: session.clickState
            )
        } else {
            penLastClick = nil
        }
        return session.clickState
    }

    /// UIKit altitude is radians from the surface (pi/2 = upright); CGEvent tilt
    /// is a unit vector in -1...1, so normalize rather than pass radians through
    /// (unnormalized, a flat pen reads 1.57 and apps that scale tilt by 90 report
    /// impossible angles).
    private func deriveTilt(azimuth: Double, altitude: Double) -> (Double, Double) {
        let azimuth = azimuth.isFinite ? azimuth : 0
        let altitude = altitude.isFinite ? altitude : .pi / 2
        let mag = min(max(0, Double.pi / 2 - altitude) / (Double.pi / 2), 1)
        return (sin(azimuth) * mag, cos(azimuth) * mag)
    }

    /// Global CG point for a normalized video coordinate on this injector's
    /// target display — the same mapping touch/pointer input uses.
    /// The Mac point under video point `x`/`y`. In Window mode it goes through
    /// the tile under it (nil over gaps and letterbox).
    func globalPoint(x: Double, y: Double) -> CGPoint? {
        let x = x.isFinite ? min(max(x, 0), 1) : 0
        let y = y.isFinite ? min(max(y, 0), 1) : 0
        if let mapper = inputLock.withLock({ targetMapper }) { return mapper.locate(x: x, y: y) }
        return InputCoordinateMapper.point(x: x, y: y, in: CGDisplayBounds(displayID))
    }

    private func screenPoint(nx: Double, ny: Double) -> CGPoint {
        if let mappedOverride { return mappedOverride }
        let nx = nx.isFinite ? min(max(nx, 0), 1) : 0
        let ny = ny.isFinite ? min(max(ny, 0), 1) : 0
        let bounds = CGDisplayBounds(displayID)
        return CGPoint(x: bounds.minX + nx * bounds.width,
                       y: bounds.minY + ny * bounds.height)
    }

    private func currentCursor() -> CGPoint {
        // A source-less query reads the Window Server's current pointer,
        // rather than the last location associated with our synthetic source.
        CGEvent(source: nil)?.location ?? .zero
    }
}
