import Foundation
import Observation

/// Recently connected and favorite aliases of one config file, kept in UserDefaults
/// (spec v1.1 §2). Nothing is written to the config file.
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
        favorites.contains { Self.same($0, alias) }
    }

    func toggleFavorite(_ alias: String) {
        if isFavorite(alias) {
            favorites.removeAll { Self.same($0, alias) }
        } else if favorites.count < Self.maxFavorites {
            favorites.append(alias)
        }
        save()
    }

    func recordConnection(_ alias: String) {
        recents.removeAll { Self.same($0, alias) }
        recents.insert(alias, at: 0)
        recents = Array(recents.prefix(Self.maxRecents))
        save()
    }

    /// ssh matches host names ASCII case-insensitively.
    static func same(_ a: String, _ b: String) -> Bool {
        a.utf8.count == b.utf8.count && zip(a.unicodeScalars, b.unicodeScalars).allSatisfy { x, y in
            lower(x) == lower(y)
        }
    }

    private static func lower(_ scalar: Unicode.Scalar) -> UInt32 {
        (65...90).contains(scalar.value) ? scalar.value + 32 : scalar.value
    }

    private func save() {
        defaults.set(["favorites": favorites, "recents": recents], forKey: key)
    }
}
