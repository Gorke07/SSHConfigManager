import Combine
import Observation
import Sparkle

/// Sparkle updates: reads the appcast at SUFeedURL and installs EdDSA-signed releases.
/// The automatic-check settings live in Sparkle's own user defaults, so they are read and written straight
/// through `SPUUpdater` and never mirrored in AppSettings.
@MainActor
@Observable
final class AppUpdater {
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: AnyCancellable?

    /// False while a check or an update session is in progress.
    private(set) var canCheckForUpdates = false
    /// Mirrors Sparkle's own defaults so SwiftUI redraws when a setting changes (Sparkle also changes them
    /// itself, e.g. from the permission prompt shown on the second launch).
    private(set) var automaticallyChecksForUpdates = false
    private(set) var automaticallyDownloadsUpdates = false

    /// The test host never starts the updater, so tests can never reach the network or show an update prompt.
    init(starting: Bool = !TestEnvironment.isRunningTests) {
        controller = SPUStandardUpdaterController(startingUpdater: starting, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in MainActor.assumeIsolated { self?.canCheckForUpdates = value } }
        refreshSettings()
    }

    /// "0.3.0 (3)": the marketing version and the build number Sparkle compares against the appcast.
    static var currentVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ value: Bool) {
        controller.updater.automaticallyChecksForUpdates = value
        refreshSettings()
    }

    func setAutomaticallyDownloadsUpdates(_ value: Bool) {
        controller.updater.automaticallyDownloadsUpdates = value
        refreshSettings()
    }

    /// Call when Settings appears: Sparkle may have changed its defaults since.
    func refreshSettings() {
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates
    }
}
