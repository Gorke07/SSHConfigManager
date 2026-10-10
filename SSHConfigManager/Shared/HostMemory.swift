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
        let favoritesResult = Self.normalized(stored?["favorites"], cap: Self.maxFavorites)
        let recentsResult = Self.normalized(stored?["recents"], cap: Self.maxRecents)
        favorites = favoritesResult.values
        recents = recentsResult.values
        // Rewrite only when stored junk was dropped; a missing key or a fresh install writes nothing.
        let notADictionary = stored == nil && defaults.object(forKey: key) != nil
        if notADictionary || favoritesResult.dropped || recentsResult.dropped {
            save()
        }
    }

    /// Strings only, non-empty, exact duplicates removed (first wins), capped; anything else is dropped.
    /// `dropped` is true when a stored value was present but something in it was discarded. A missing value is not a drop.
    private static func normalized(_ raw: Any?, cap: Int) -> (values: [String], dropped: Bool) {
        guard let raw else { return ([], false) }
        guard let array = raw as? [Any] else { return ([], true) }
        var seen = Set<String>()
        var result: [String] = []
        var dropped = false
        for element in array {
            guard result.count < cap, let alias = element as? String, !alias.isEmpty, seen.insert(alias).inserted else {
                dropped = true
                continue
            }
            result.append(alias)
        }
        return (result, dropped)
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
