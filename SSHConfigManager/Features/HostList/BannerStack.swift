import SSHConfigKit
import SwiftUI

struct BannerStack: View {
    @Bindable var model: AppModel
    @Binding var showExternalDiff: Bool
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let banners = BannerBuilder.banners(for: model.store)
        if !banners.isEmpty {
            VStack(spacing: 0) {
                ForEach(banners) { banner in
                    row(for: banner)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func row(for banner: Banner) -> some View {
        switch banner {
        case .missingFile:
            BannerRow(icon: "doc.badge.plus", tint: .yellow, message: Messages.text(for: ConfigLoadState.missing) ?? "") {
                Button(String(localized: "banner.missing.create")) {
                    do { try model.store.createFile() } catch { model.errorMessage = Messages.text(for: error) }
                }
                Button(String(localized: "banner.missing.choose")) { openSettings() }
            }
        case .notUTF8:
            BannerRow(icon: "exclamationmark.triangle", tint: .red, message: Messages.text(for: ConfigLoadState.notUTF8) ?? "") {
                EmptyView()
            }
        case .unreadable(let detail):
            BannerRow(icon: "exclamationmark.triangle", tint: .red, message: Messages.text(for: ConfigLoadState.unreadable(detail)) ?? "") {
                Button(String(localized: "banner.missing.choose")) { openSettings() }
            }
        case .byteOrderMark:
            BannerRow(icon: "exclamationmark.triangle", tint: .orange, message: String(localized: "banner.bom")) {
                Button(String(localized: "banner.bom.remove")) {
                    do { try model.store.apply { $0.removeByteOrderMark() } } catch { model.errorMessage = Messages.text(for: error) }
                }
            }
        case .externalChange:
            BannerRow(icon: "arrow.triangle.2.circlepath", tint: .orange, message: Messages.text(for: ConfigStoreError.conflict)) {
                Button(String(localized: "banner.external.reload")) {
                    model.store.discardChanges()
                    model.resetEditor()
                }
                Button(String(localized: "banner.external.showDiff")) { showExternalDiff = true }
            }
        case .notWatching:
            BannerRow(icon: "eye.slash", tint: .secondary, message: String(localized: "banner.notWatching")) {
                EmptyView()
            }
        }
    }
}

private struct BannerRow<Actions: View>: View {
    let icon: String
    let tint: Color
    let message: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(message).frame(maxWidth: .infinity, alignment: .leading)
            actions()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12))
    }
}
