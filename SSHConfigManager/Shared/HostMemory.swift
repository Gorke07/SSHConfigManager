import Foundation
import Observation

/// Recently connected and favorite aliases of one config file, kept in UserDefaults
/// (spec v1.1 §2), by exact alias (ssh matches Host patterns case-sensitively). Nothing is written to the config file.
@MainActor
@Observable
final class HostMemory {
    static let maxRecents = 5
    static let maxFavorites = 50

    private(set) var favorites: [String]
    private(set) var recents: [String]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
        let stored = defaults.dictionary(forKey: key)
        favorites = stored?["favorites"] as? [String] ?? []
        recents = stored?["recents"] as? [String] ?? []
    }

    func isFavorite(_ alias: String) -> Bool {
        favorites.contains(alias)
    }

    func toggleFavorite(_ alias: String) {
        if isFavorite(alias) {
            favorites.removeAll { $0 == alias }
        } else if favorites.count < Self.maxFavorites {
            favorites.append(alias)
        }
        save()
    }

    func recordConnection(_ alias: String) {
        recents.removeAll { $0 == alias }
        recents.insert(alias, at: 0)
        recents = Array(recents.prefix(Self.maxRecents))
        save()
    }

    private func save() {
        defaults.set(["favorites": favorites, "recents": recents], forKey: key)
    }
}
