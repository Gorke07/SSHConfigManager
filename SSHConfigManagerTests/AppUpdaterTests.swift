import Foundation
import Testing
@testable import SSH_Config_Manager

@MainActor
struct AppUpdaterTests {
    /// The test host is the app, so Bundle.main carries the shipped Info.plist.
    @Test func infoPlistPointsSparkleAtAnHTTPSFeedWithAnEdDSAKey() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let feed = try #require((info["SUFeedURL"] as? String).flatMap(URL.init(string:)))
        #expect(feed.scheme == "https")
        #expect(feed.lastPathComponent == "appcast.xml")
        let key = try #require(info["SUPublicEDKey"] as? String)
        #expect(Data(base64Encoded: key)?.count == 32)   // an ed25519 public key
    }

    @Test func buildNumberIsAnIntegerSparkleCanCompare() throws {
        let build = try #require(Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
        #expect(Int(build) != nil)
        #expect(AppUpdater.currentVersion.hasSuffix("(\(build))"))
    }

    @Test func updaterIsNotStartedInTheTestHost() {
        // Started updaters may show Sparkle's permission prompt or reach the network.
        #expect(!AppUpdater().canCheckForUpdates)
    }
}
