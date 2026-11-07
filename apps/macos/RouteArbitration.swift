import Foundation

/// Stable ordering for discovered candidates. Route choice itself belongs to
/// the user; these tiers never authorize an automatic transport migration.
enum RoutePriority {
    static func tier(_ route: ConnectionRoute) -> Int {
        switch route {
        case .usb: return 0
        case .lan, .awdl: return 1
        case .remote: return 2
        }
    }
}

/// One logical peer owns exactly one long-lived session. Discovery and
/// receiver-originated requests never replace its transport. Only the Mac's
/// explicit USB/Wi-Fi/Remote menu may migrate an existing session.
enum RouteArbitrationDecision: Equatable {
    case proceed
    case migrate
    case ignore
}

enum RouteArbitration {
    static func decide(
        ownerTier: Int?,
        targetTier: Int,
        explicitRouteSelection: Bool = false
    ) -> RouteArbitrationDecision {
        guard let ownerTier else { return .proceed }
        if explicitRouteSelection && targetTier != ownerTier { return .migrate }
        return .ignore
    }
}
