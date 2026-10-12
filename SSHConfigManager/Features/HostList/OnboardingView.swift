import SwiftUI

/// Shown instead of the empty-selection placeholder when the config has no hosts at all.
struct OnboardingView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GlassEffectContainer {
            steps
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "onboarding.title")).font(.title2.bold())
            step(1, title: String(localized: "onboarding.addHost")) {
                model.addHost()
            }
            step(2, title: String(localized: "onboarding.createKey")) {
                model.keys.pendingNewKey = true
                openWindow(id: "keys")
            }
            step(3, title: String(localized: "onboarding.uploadKey")) { openWindow(id: "keys") }
        }
        .padding(32)
        .glassEffect(in: .rect(cornerRadius: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func step(_ number: Int, title: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: String(number))
                .font(.headline)
                .frame(width: 28, height: 28)
                .glassEffect(in: .circle)
                .accessibilityHidden(true)
            Button(title, action: action)
                .buttonStyle(.glass)
        }
    }
}
