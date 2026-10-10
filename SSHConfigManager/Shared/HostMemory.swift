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
        let rawFavorites = stored?["favorites"]
        let rawRecents = stored?["recents"]
        favorites = Self.normalized(rawFavorites, cap: Self.maxFavorites)
        recents = Self.normalized(rawRecents, cap: Self.maxRecents)
        // Rewrite only when something was dropped from what was stored.
        if stored != nil, (rawFavorites as? [String]) != favorites || (rawRecents as? [String]) != recents {
            save()
        }
    }

    /// Strings only, non-empty, exact duplicates removed (first wins), capped; anything else is dropped.
    private static func normalized(_ raw: Any?, cap: Int) -> [String] {
        guard let array = raw as? [Any] else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for element in array {
            guard let alias = element as? String, !alias.isEmpty, seen.insert(alias).inserted else { continue }
            result.append(alias)
            if result.count == cap { break }
        }
        return result
    }

    func isFavorite(_ alias: String) -> Bool {
        favorites.contains(alias)
    }

    /// Removing always works. Adding at the cap first prunes favorites that are not in `existing`;
    /// returns false when the list is still full.
    @discardableResult
    func toggleFavorite(_ alias: String, existing: Set<String>) -> Bool {
        if isFavorite(alias) {
            favorites.removeAll { $0 == alias }
            save()
            return true
        }
        if favorites.count >= Self.maxFavorites {
            favorites.removeAll { !existing.contains($0) }
            guard favorites.count < Self.maxFavorites else { save(); return false }
        }
        favorites.append(alias)
        save()
        return true
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
