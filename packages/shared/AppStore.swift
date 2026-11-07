// Update destinations for Mac and Android receivers. Unknown or malformed
// links always fall back to the project page.

import Foundation

enum AppStore {
    static var projectURL: URL { ProjectLinks.gitHub }

    /// Accept only an HTTPS link offered by the authenticated peer.
    static func resolveReceiverUpdateURL(_ offered: String?) -> URL {
        guard let offered, let url = URL(string: offered),
              url.scheme?.lowercased() == "https", url.host?.isEmpty == false else {
            return androidReceiverUpdateURL
        }
        return url
    }

    // MARK: - Android (Google Play)

    /// Android's application ID once its Google Play listing is public, or
    /// nil until then. Until it is set, an Android receiver told to update is
    /// sent to the project page rather than to a listing that doesn't exist.
    static let androidPlayPackage: String? = nil

    /// Where an out-of-date Android receiver is sent: the Play listing when
    /// there is one, otherwise the project page.
    static var androidReceiverUpdateURL: URL { androidUpdateDestination(package: androidPlayPackage) }

    static func androidListingURL(package: String?) -> URL? {
        guard let package, isAndroidPackage(package) else { return nil }
        return URL(string: "https://play.google.com/store/apps/details?id=\(package)")
    }

    static func androidUpdateDestination(package: String?) -> URL {
        androidListingURL(package: package) ?? projectURL
    }

    /// Java-package shape: two or more dot-separated segments, each a letter
    /// followed by letters, digits or underscores. Nothing else can be
    /// pasted into the listing URL.
    private static func isAndroidPackage(_ package: String) -> Bool {
        let segments = package.split(separator: ".", omittingEmptySubsequences: false)
        return segments.count >= 2 && segments.allSatisfy { segment in
            guard let first = segment.first, first.isASCII, first.isLetter else { return false }
            return segment.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
        }
    }
}

/// Which supported app a receiver runs, from its `hello.device`.
enum ReceiverUpdatePlatform: String, Equatable {
    case unknown
    case mac
    case android

    init(receiverKind kind: String) {
        if kind == "Mac" {
            self = .mac
        } else if kind.hasPrefix("Android") {
            self = .android
        } else {
            self = .unknown
        }
    }

    var storeURL: URL {
        switch self {
        case .unknown, .mac: AppStore.projectURL
        case .android: AppStore.androidReceiverUpdateURL
        }
    }

    static func updateRequiredMessage(receiverKind kind: String) -> [String: Any] {
        let platform = ReceiverUpdatePlatform(receiverKind: kind)
        let message: String
        switch platform {
        case .mac:
            message = "The MeowDisplay Receiver app on that Mac is too old for this Mac. Update it from the MeowDisplay GitHub page to reconnect."
        case .android, .unknown:
            message = "This \(kind) app is too old for this Mac. Update MeowDisplay on it to reconnect."
        }
        return [
            "type": WireMessage.updateRequired,
            "target": platform.rawValue,
            "store": platform.storeURL.absoluteString,
            "message": message,
        ]
    }
}
