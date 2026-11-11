import CoreGraphics
import XCTest

final class InputInjectorDirectTouchTests: XCTestCase {
    private final class Sink: SyntheticEventSink, @unchecked Sendable {
        private(set) var events: [CGEvent] = []
        func post(_ event: CGEvent) { events.append(event) }
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: InputPolicy.defaultsKey)
        LoginSessionConsole.shared.set(onConsole: true)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: InputPolicy.defaultsKey)
        LoginSessionConsole.shared.set(onConsole: true)
        super.tearDown()
    }

    func testDirectTouchClickNeverPostsAVisibleCursorMove() {
        let grant = SessionInputGrantBox()
        grant.set(true)
        let sink = Sink()
        let injector = InputInjector(displayID: CGMainDisplayID(), sessionInputGrant: grant, eventSink: sink)

        injector.handlePointerMove(x: 0.25, y: 0.5)
        XCTAssertTrue(sink.events.isEmpty, "absolute hover only records the touch target")
        injector.handlePointerDown(button: .left, clickCount: 1)
        injector.handlePointerUp(button: .left, clickCount: 1)

        XCTAssertEqual(sink.events.map(\.type), [.leftMouseDown, .leftMouseUp])
        let expected = InputCoordinateMapper.point(x: 0.25, y: 0.5, in: CGDisplayBounds(CGMainDisplayID()))
        XCTAssertEqual(sink.events.map(\.location), [expected, expected])
        XCTAssertFalse(sink.events.contains { $0.type == .mouseMoved }, "no warp and no after-the-fact restore")
    }

    func testDirectTouchScrollTargetDoesNotMoveTheVisibleCursor() {
        let grant = SessionInputGrantBox()
        grant.set(true)
        let sink = Sink()
        let injector = InputInjector(displayID: CGMainDisplayID(), sessionInputGrant: grant, eventSink: sink)

        injector.handleTouch(phase: "moved", x: 0.6, y: 0.4)

        XCTAssertTrue(sink.events.isEmpty)
    }

    func testHostileScrollAndPencilNumbersNeverTrap() {
        let grant = SessionInputGrantBox()
        grant.set(true)
        let sink = Sink()
        let injector = InputInjector(displayID: CGMainDisplayID(), sessionInputGrant: grant, eventSink: sink)

        // Values that used to reach `Int(1e308)` / `Int64(pressure * 65535)`.
        injector.handleScroll(dx: 1e308, dy: 1e308)
        injector.handlePointerMoveRelative(dx: 1e308, dy: 1e308)
        injector.handlePencil(phase: "down", x: 1e308, y: -1e308, pressure: 1e308,
                              azimuth: 1e308, altitude: -1e308, rotation: 1e308)
        injector.handlePointerDown(button: .left, clickCount: Int.max)
        injector.handlePointerUp(button: .left, clickCount: Int.max)

        XCTAssertTrue(sink.events.allSatisfy {
            $0.location.x.isFinite && $0.location.y.isFinite
        }, "every posted event must carry a finite location")
        XCTAssertTrue(sink.events.allSatisfy {
            let pressure = $0.getDoubleValueField(.mouseEventPressure)
            return pressure.isFinite && (0...1).contains(pressure)
        }, "tablet pressure must be finite and inside 0...1")
        XCTAssertTrue(sink.events.allSatisfy {
            $0.getIntegerValueField(.mouseEventClickState) <= 3
        }, "click state is clamped to a triple click")
    }

    func testOnlyNativeMenuItemsUseAccessibilityPressRouting() {
        XCTAssertTrue(DirectTouchMenuRouting.isMenuRole(kAXMenuBarItemRole as String))
        XCTAssertTrue(DirectTouchMenuRouting.isMenuRole(kAXMenuItemRole as String))
        XCTAssertTrue(DirectTouchMenuRouting.isMenuRole(kAXMenuBarRole as String))
        XCTAssertFalse(DirectTouchMenuRouting.isMenuRole(kAXButtonRole as String))
        XCTAssertFalse(DirectTouchMenuRouting.isMenuRole(kAXTextFieldRole as String))
        XCTAssertFalse(DirectTouchMenuRouting.isMenuRole(nil))
    }

    func testMenuRoutingUsesShowMenuWhenPressIsUnsupported() {
        XCTAssertEqual(DirectTouchMenuRouting.preferredAction([kAXShowMenuAction as String]), kAXShowMenuAction as String)
        XCTAssertEqual(DirectTouchMenuRouting.preferredAction([kAXShowMenuAction as String, kAXPressAction as String]), kAXShowMenuAction as String)
        XCTAssertNil(DirectTouchMenuRouting.preferredAction([]))
        XCTAssertNil(DirectTouchMenuRouting.preferredAction(["AXOpen"]))
    }

    /// A native menu opened by an accessibility action stays in a tracking session that
    /// per-PID events cannot end: Finder ignored every later tap until it was restarted.
    /// Only a successful AXPress on a leaf command both performs and closes.
    func testOnlyALeafPressEndsNativeMenuTracking() {
        XCTAssertFalse(DirectTouchMenuRouting.leavesMenuTracking(
            action: kAXPressAction as String, succeeded: true, hasSubmenu: false))
        XCTAssertTrue(DirectTouchMenuRouting.leavesMenuTracking(
            action: kAXShowMenuAction as String, succeeded: true, hasSubmenu: false),
            "opening a menu never performs the item")
        XCTAssertTrue(DirectTouchMenuRouting.leavesMenuTracking(
            action: kAXPressAction as String, succeeded: true, hasSubmenu: true),
            "a submenu parent opens a tracking session")
        XCTAssertTrue(DirectTouchMenuRouting.leavesMenuTracking(
            action: kAXPressAction as String, succeeded: false, hasSubmenu: false),
            "a failed press leaves the menu up")
    }

    /// Window Server menu tracking never sees the per-PID events Direct Touch posts, so an
    /// open menu/panel is dismissed with Escape before a tap elsewhere can act.
    func testATapOutsideAnOpenMenuDismissesItFirst() {
        let menu = CGRect(x: 6, y: 34, width: 231, height: 305)
        let open = [DirectTouchMenuRouting.OpenOverlay(pid: 652, frame: menu, layer: 101, isMenu: true)]

        XCTAssertFalse(DirectTouchMenuRouting.shouldDismissOverlay(at: CGPoint(x: 20, y: 40), targetPID: 652, overlays: open),
                       "a tap chooses from the menu")
        XCTAssertTrue(DirectTouchMenuRouting.shouldDismissOverlay(at: CGPoint(x: 600, y: 400), targetPID: 39743, overlays: open),
                      "a tap elsewhere dismisses it")
        XCTAssertTrue(DirectTouchMenuRouting.shouldDismissOverlay(at: CGPoint(x: 600, y: 400), targetPID: 652, overlays: open),
                      "even in the app that owns it")
        XCTAssertFalse(DirectTouchMenuRouting.shouldDismissOverlay(at: CGPoint(x: 600, y: 400), targetPID: nil, overlays: []),
                       "no menu, nothing to do")
    }

    /// The Window Server can report a native menu's one window in another display's
    /// coordinate space (menu-bar layout scales with display width) even though the menu is
    /// drawn on the touched display. A tap on the visible copy must choose from it, not
    /// dismiss it.
    func testAMenuIsRecognizedOnTheDisplayThatShowsItsCopy() {
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let secondary = CGRect(x: -1280, y: 76, width: 1280, height: 800)
        let menu = CGRect(x: 132, y: 34, width: 181, height: 283)
        let onTheCopy = CGPoint(x: -1120, y: 300)

        XCTAssertFalse(menu.contains(onTheCopy), "the reported window is on the other display")
        XCTAssertTrue(DirectTouchMenuRouting.menuContains(menu, point: onTheCopy,
                                                          pointDisplay: secondary, frameDisplay: main))
        XCTAssertFalse(DirectTouchMenuRouting.menuContains(
            menu, point: CGPoint(x: -1280, y: 700), pointDisplay: secondary, frameDisplay: main))
    }

    /// Control Center's panel is a full-screen window, so frame containment cannot tell it
    /// apart from the app behind it: the touched app's PID does.
    func testATapOnControlCenterPanelsOwnControlsDoesNotDismissIt() {
        let panel = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let open = [DirectTouchMenuRouting.OpenOverlay(pid: 719, frame: panel, layer: 21, isMenu: false)]

        XCTAssertFalse(DirectTouchMenuRouting.shouldDismissOverlay(at: CGPoint(x: 700, y: 160), targetPID: 719, overlays: open))
        XCTAssertTrue(DirectTouchMenuRouting.shouldDismissOverlay(at: CGPoint(x: 700, y: 160), targetPID: 39743, overlays: open))
        XCTAssertTrue(DirectTouchMenuRouting.shouldDismissOverlay(at: CGPoint(x: 700, y: 160), targetPID: nil, overlays: open))
    }

    func testStatusItemLookupScalesSecondaryDisplayWidthWithoutMovingCursor() {
        let secondary = CGRect(x: -1280, y: 76, width: 1280, height: 800)
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let point = DirectTouchMenuRouting.statusItemPoint(
            at: CGPoint(x: -408.5, y: 89.5), displayFrame: secondary, referenceFrame: main)
        XCTAssertEqual(point?.x ?? 0, 1029.459375, accuracy: 0.001)
        XCTAssertEqual(point?.y ?? 0, 13.5, accuracy: 0.001)
        XCTAssertNil(DirectTouchMenuRouting.statusItemPoint(
            at: .zero, displayFrame: .zero, referenceFrame: main))
    }

    func testStatusItemLookupUsesTheItemsOwnReferenceDisplay() {
        let secondary = CGRect(x: -1280, y: 76, width: 1280, height: 800)
        let external = CGRect(x: -243, y: -1080, width: 1920, height: 1080)
        let point = DirectTouchMenuRouting.statusItemPoint(
            at: CGPoint(x: -506, y: 89.5),
            displayFrame: secondary,
            referenceFrame: external)
        XCTAssertEqual(point?.x ?? 0, 918, accuracy: 0.001)
        XCTAssertEqual(point?.y ?? 0, -1066.5, accuracy: 0.001)
    }

    func testHostedStatusItemTargetingRejectsAppsAndTallPanels() {
        let hosted = DirectTouchStatusItemTargeting.Candidate(
            pid: 649,
            bundleIdentifier: "com.apple.controlcenter",
            frame: CGRect(x: -760, y: 76, width: 34, height: 30),
            layer: 25,
            alpha: 1,
            windowID: 26302)
        let otherApp = DirectTouchStatusItemTargeting.Candidate(
            pid: 33375,
            bundleIdentifier: "com.ccswitch.desktop",
            frame: hosted.frame,
            layer: 25,
            alpha: 1,
            windowID: 999)
        let tallPanel = DirectTouchStatusItemTargeting.Candidate(
            pid: 649,
            bundleIdentifier: "com.apple.controlcenter",
            frame: CGRect(x: -919, y: 106, width: 660, height: 758),
            layer: 25,
            alpha: 1,
            windowID: 1000)

        let target = DirectTouchStatusItemTargeting.target(
            at: CGPoint(x: -743, y: 89.5),
            candidates: [otherApp, tallPanel, hosted],
            ownPID: 27562)
        XCTAssertEqual(target?.windowID, 26302)
    }

    func testDirectTouchWindowFallbackUsesFrontmostWindowAtTouchPoint() {
        let windows = [
            DirectTouchWindowTargeting.Candidate(pid: 100, frame: CGRect(x: 0, y: 0, width: 800, height: 600), layer: 0, alpha: 1),
            DirectTouchWindowTargeting.Candidate(pid: 200, frame: CGRect(x: 0, y: 0, width: 800, height: 600), layer: 0, alpha: 1),
        ]
        XCTAssertEqual(DirectTouchWindowTargeting.targetPID(at: CGPoint(x: 300, y: 200), candidates: windows, ownPID: 999), 100)
        XCTAssertEqual(DirectTouchWindowTargeting.targetPID(at: CGPoint(x: 900, y: 200), candidates: windows, ownPID: 999), nil)
    }

    func testDirectTouchWindowFallbackRejectsOverlaysTransparencyAndOwnApp() {
        let windows = [
            DirectTouchWindowTargeting.Candidate(pid: 100, frame: CGRect(x: 0, y: 0, width: 800, height: 600), layer: 25, alpha: 1),
            DirectTouchWindowTargeting.Candidate(pid: 101, frame: CGRect(x: 0, y: 0, width: 800, height: 600), layer: 0, alpha: 0),
            DirectTouchWindowTargeting.Candidate(pid: 999, frame: CGRect(x: 0, y: 0, width: 800, height: 600), layer: 0, alpha: 1),
            DirectTouchWindowTargeting.Candidate(pid: 200, frame: CGRect(x: 0, y: 0, width: 800, height: 600), layer: 0, alpha: 1),
        ]
        XCTAssertEqual(DirectTouchWindowTargeting.targetPID(at: CGPoint(x: 300, y: 200), candidates: windows, ownPID: 999), 200)
    }

    func testDirectTouchWindowFallbackUsesVisibleWindowBounds() {
        let window = DirectTouchWindowTargeting.Candidate(pid: 100, frame: CGRect(x: 100, y: 100, width: 200, height: 150), layer: 0, alpha: 0.5)
        XCTAssertEqual(DirectTouchWindowTargeting.targetPID(at: CGPoint(x: 100, y: 100), candidates: [window], ownPID: 999), 100)
        XCTAssertNil(DirectTouchWindowTargeting.targetPID(at: CGPoint(x: 300, y: 250), candidates: [window], ownPID: 999))
    }

    func testTrackpadClickDoesNotInventAReturnMove() {
        let grant = SessionInputGrantBox()
        grant.set(true)
        let sink = Sink()
        let injector = InputInjector(displayID: CGMainDisplayID(), sessionInputGrant: grant, eventSink: sink)

        injector.handlePointerMoveRelative(dx: 12, dy: 8)
        injector.handlePointerDown(button: .left, clickCount: 1)
        injector.handlePointerUp(button: .left, clickCount: 1)

        XCTAssertEqual(sink.events.map(\.type), [.mouseMoved, .leftMouseDown, .leftMouseUp])
    }
}
