import XCTest

final class RouteArbitrationTests: XCTestCase {
    func testNoExistingOwnerProceeds() {
        XCTAssertEqual(RouteArbitration.decide(ownerTier: nil, targetTier: RoutePriority.tier(.lan)), .proceed)
    }

    func testDiscoveryNeverMigratesToAnotherRoute() {
        for (owner, target) in [
            (ConnectionRoute.remote, ConnectionRoute.lan),
            (.lan, .usb),
            (.usb, .lan),
        ] {
            XCTAssertEqual(
                RouteArbitration.decide(ownerTier: RoutePriority.tier(owner), targetTier: RoutePriority.tier(target)),
                .ignore)
        }
    }

    func testExplicitSelectionMigratesInEitherDirection() {
        for (owner, target) in [
            (ConnectionRoute.usb, ConnectionRoute.lan),
            (.lan, .usb),
            (.remote, .lan),
        ] {
            XCTAssertEqual(
                RouteArbitration.decide(ownerTier: RoutePriority.tier(owner), targetTier: RoutePriority.tier(target),
                                        explicitRouteSelection: true),
                .migrate)
        }
    }

    func testSameTierDoesNotBounceEvenForExplicitSelection() {
        XCTAssertEqual(
            RouteArbitration.decide(ownerTier: RoutePriority.tier(.lan), targetTier: RoutePriority.tier(.awdl),
                                    explicitRouteSelection: true),
            .ignore)
    }

    func testDelayedRemoteRequestAfterWiFiSelectionIsIgnored() {
        XCTAssertEqual(
            RouteArbitration.decide(ownerTier: RoutePriority.tier(.lan), targetTier: RoutePriority.tier(.remote)),
            .ignore)
    }
}
