import XCTest

/// ExtendPad has no update service of its own yet. Pin the safe fallback:
/// neither Mac app starts Sparkle or carries an upstream feed/signing key.
/// A future updater must add an ExtendPad-owned feed and a new EdDSA key,
/// then replace these tests with signed-update configuration checks.
final class SparkleConfigurationTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let meowDisplayPublicEDKey = "M9Je3RXE9GYGv7ZvVmJj2xK2FrpSR/rQvbuZFfYORcU="

    private struct MacApp {
        let target: String
        let infoPlist: String
        let delegate: String
    }

    private static let apps = [
        MacApp(target: "OpenSidecarMac", infoPlist: "apps/macos/Info.plist",
               delegate: "apps/macos/OpenSidecarMacApp.swift"),
        MacApp(target: "OpenSidecarMacReceiver", infoPlist: "apps/macos-receiver/Info.plist",
               delegate: "apps/macos-receiver/OpenSidecarMacReceiverApp.swift"),
    ]

    private static let upstreamPublicEDKeys = [
        meowDisplayPublicEDKey,
        "rYxlIePmwzi2bRo/qIsuY2TqTnQ34li2gQhJpGBiumw=",
    ]
    private static let upstreamFeedHosts = [
        "meowdisplay.app", "opendisplay.app", "peetzweg.github.io",
    ]
    private static let sparkleKeys = [
        "SUFeedURL", "SUPublicEDKey", "SUVerifyUpdateBeforeExtraction",
        "SURequireSignedFeed", "SUEnableAutomaticChecks", "SUAutomaticallyUpdate",
    ]

    func testProjectDoesNotConfigureAnUpstreamFeedOrKey() throws {
        for app in Self.apps {
            let info = try Self.infoProperties(ofTarget: app.target)
            for key in Self.sparkleKeys {
                XCTAssertNil(info[key], "\(app.target) must not configure \(key)")
            }
        }
    }

    func testGeneratedInfoPlistsDoNotConfigureSparkle() throws {
        for app in Self.apps {
            let url = Self.repoRoot.appendingPathComponent(app.infoPlist)
            let data = try Data(contentsOf: url)
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            for key in Self.sparkleKeys {
                XCTAssertNil(plist[key], "\(app.infoPlist) must not configure \(key)")
            }
        }
    }

    func testBothApplicationsLeaveTheUpdaterStopped() throws {
        for app in Self.apps {
            let source = try String(contentsOf: Self.repoRoot.appendingPathComponent(app.delegate),
                                    encoding: .utf8)
            XCTAssertTrue(source.contains("let updater: SPUStandardUpdaterController? = nil"), app.delegate)
            XCTAssertFalse(source.contains("startingUpdater: true"), app.delegate)
        }
    }

    func testNothingPointsAtUpstreamUpdates() throws {
        var sources = [try String(contentsOf: Self.repoRoot.appendingPathComponent("project.yml"),
                                  encoding: .utf8)]
        for app in Self.apps {
            sources.append(try String(contentsOf: Self.repoRoot.appendingPathComponent(app.infoPlist),
                                      encoding: .utf8))
        }
        for source in sources {
            for key in Self.upstreamPublicEDKeys {
                XCTAssertFalse(source.contains(key), "upstream update signing key")
            }
            for host in Self.upstreamFeedHosts {
                XCTAssertFalse(source.contains("https://\(host)/"), host)
            }
        }
    }

    /// `key: value` pairs directly under a target's `info.properties`.
    private static func infoProperties(ofTarget name: String) throws -> [String: String] {
        let spec = try String(contentsOf: repoRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        let lines = spec.components(separatedBy: "\n")
        let targets = try XCTUnwrap(lines.firstIndex(of: "targets:"))
        let start = try XCTUnwrap(lines[targets...].firstIndex(of: "  \(name):"), "\(name) not found")
        let properties = try XCTUnwrap(
            lines[start...].firstIndex(of: "      properties:"), "\(name) has no info properties")
        var result: [String: String] = [:]
        for line in lines[(properties + 1)...] {
            let content = line.trimmingCharacters(in: .whitespaces)
            if content.isEmpty || content.hasPrefix("#") { continue }
            // The block ends at the first key indented less than a property.
            guard line.prefix(while: { $0 == " " }).count >= 8 else { break }
            guard let colon = content.firstIndex(of: ":") else { continue }
            let key = String(content[..<colon])
            let value = content[content.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result
    }
}
