import XCTest

final class AppStoreTests: XCTestCase {
    /// Upstream OpenDisplay's listing ID, spelled as a number so its digits
    /// never appear as text in the repository (see the scan below).
    private static let upstreamID = String(6_780_264_891)

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func testAndroidHasNoPlayLinkUntilItsListingExists() {
        XCTAssertNil(AppStore.androidPlayPackage, "set only once the Google Play listing is public")
        XCTAssertEqual(AppStore.androidReceiverUpdateURL, AppStore.projectURL)
        XCTAssertNil(AppStore.androidListingURL(package: nil))
    }

    func testAndroidListingIsLinkedOnceConfigured() {
        let package = "com.raisecaterror.meowdisplay.android"
        XCTAssertEqual(AppStore.androidListingURL(package: package)?.absoluteString,
                       "https://play.google.com/store/apps/details?id=\(package)")
        XCTAssertEqual(AppStore.androidUpdateDestination(package: package),
                       AppStore.androidListingURL(package: package))
    }

    func testOnlyAWellFormedPackageBecomesAListingLink() {
        for package in ["", "meowdisplay", "com..meowdisplay", ".com.meowdisplay", "com.meowdisplay.",
                        "com.1meowdisplay", "com.meow display", "com.meowdisplay&hl=en", "com.meowdisplay/x",
                        "com.méowdisplay"] {
            XCTAssertNil(AppStore.androidListingURL(package: package), package)
            XCTAssertEqual(AppStore.androidUpdateDestination(package: package), AppStore.projectURL, package)
        }
    }

    func testUpdateRequiredNamesSupportedPlatforms() {
        XCTAssertEqual(ReceiverUpdatePlatform(receiverKind: "Mac"), .mac)
        XCTAssertEqual(ReceiverUpdatePlatform(receiverKind: "Android"), .android)
        XCTAssertEqual(ReceiverUpdatePlatform(receiverKind: "Android tablet"), .android)
        for kind in ["iPhone", "iPad", "", "Vision"] {
            XCTAssertEqual(ReceiverUpdatePlatform(receiverKind: kind), .unknown, kind)
        }

        let android = ReceiverUpdatePlatform.updateRequiredMessage(receiverKind: "Android")
        XCTAssertEqual(android["type"] as? String, WireMessage.updateRequired)
        XCTAssertEqual(android["target"] as? String, "android")
        XCTAssertEqual(android["store"] as? String, AppStore.androidReceiverUpdateURL.absoluteString)

        let mac = ReceiverUpdatePlatform.updateRequiredMessage(receiverKind: "Mac")
        XCTAssertEqual(mac["target"] as? String, "mac")
        XCTAssertEqual(mac["store"] as? String, AppStore.projectURL.absoluteString)

        for message in [android, mac] {
            let data = try? JSONSerialization.data(withJSONObject: message)
            XCTAssertNotNil(data)
            XCTAssertLessThan(data?.count ?? .max, 32_768)
            XCTAssertEqual(data?.first, UInt8(ascii: "{"))
        }
    }

    func testUpdateLinkRequiresHTTPS() {
        let https = URL(string: "https://github.com/raiseCatError/meowdisplay/releases/latest")
        XCTAssertEqual(AppStore.resolveReceiverUpdateURL(https?.absoluteString), https)
        for link in [nil, "", "javascript:alert(1)", "tel:123", "file:///etc/hosts", "https://", "not a url"] {
            XCTAssertEqual(AppStore.resolveReceiverUpdateURL(link), AppStore.projectURL,
                           link ?? "nil")
        }
    }

    /// The upstream listing ID must not survive anywhere it could be emitted
    /// or copied from: app code, plists, string catalogs, project/CI and
    /// fastlane config, the website, or the project docs.
    func testUpstreamListingIDAppearsNowhereInTheRepository() throws {
        let manager = FileManager.default
        let root = Self.repoRoot
        let textExtensions: Set<String> = ["swift", "h", "m", "plist", "xcstrings", "xcprivacy", "entitlements",
                                           "yml", "yaml", "json", "md", "html", "ts", "tsx", "js", "mjs", "css",
                                           "txt", "rb", "sh", ""]
        let untracked: Set<String> = ["CLAUDE.md", "PROJECT_BRIEF.md", "ICON_WORKFLOW.md"]
        var files = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") && !untracked.contains($0.lastPathComponent) }
        for directory in ["packages/shared", "apps/macos", "apps/macos-receiver", "apps/android",
                          "src", "public", "tools", "fastlane", ".github"] {
            let enumerator = try XCTUnwrap(manager.enumerator(at: root.appendingPathComponent(directory),
                                                              includingPropertiesForKeys: nil), directory)
            while let url = enumerator.nextObject() as? URL { files.append(url) }
        }
        var scanned = 0
        var offenders: [String] = []
        for url in files where textExtensions.contains(url.pathExtension) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scanned += 1
            if text.contains(Self.upstreamID) {
                offenders.append(String(url.path.dropFirst(root.path.count)))
            }
        }
        XCTAssertTrue(files.contains { $0.lastPathComponent == "AppStore.swift" })
        XCTAssertGreaterThan(scanned, 100, "the scan should cover the repository's sources")
        XCTAssertEqual(offenders, [])
    }
}
