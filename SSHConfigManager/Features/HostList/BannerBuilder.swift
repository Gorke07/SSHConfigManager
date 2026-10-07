import SSHConfigKit

enum Banner: Hashable, Identifiable, Sendable {
    case missingFile
    case notUTF8
    case unreadable(String)
    case byteOrderMark
    case externalChange
    case notWatching

    var id: Self { self }
}

@MainActor
enum BannerBuilder {
    /// Most important first: load problems, then BOM, then external changes, then watcher status.
    static func banners(for store: ConfigStore) -> [Banner] {
        var banners: [Banner] = []
        switch store.loadState {
        case .missing: banners.append(.missingFile)
        case .notUTF8: banners.append(.notUTF8)
        case .unreadable(let detail): banners.append(.unreadable(detail))
        case .loaded:
            if store.document.hasByteOrderMark { banners.append(.byteOrderMark) }
        }
        if store.externalChangePending { banners.append(.externalChange) }
        if !store.isWatching { banners.append(.notWatching) }
        return banners
    }
}
