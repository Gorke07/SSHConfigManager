import Foundation
import Observation
import SSHConfigKit

struct ProxyChainNode: Identifiable, Equatable {
    let id: Int
    let title: String
    /// A host of the saved file (testable), or nil for a plain host name.
    let alias: String?
    let isCycle: Bool
}

enum ProxyChainBuilder {
    static let maxDepth = 5

    /// Nodes from the first hop to the target (the target is last). A `ProxyJump a,b` list connects to
    /// a, then b, then the target, so every hop is shown in order; only the first hop's own ProxyJump
    /// is followed (later hops are reached through the earlier ones). The list is capped at
    /// `maxDepth + 1` nodes.
    static func nodes(for alias: String, options: (String) -> EffectiveOptions?, isSavedAlias: (String) -> String?) -> [ProxyChainNode] {
        typealias Entry = (title: String, alias: String?, isCycle: Bool)
        var chain: [Entry] = [(alias, isSavedAlias(alias), false)]
        var visited: Set<String> = [EffectiveConfigCache.key(alias)]
        var current = alias
        while true {
            let hops = options(current)?.jumpHops ?? []
            let budget = maxDepth + 1 - chain.count
            guard !hops.isEmpty, budget > 0 else { break }
            var entries: [Entry] = []
            var next: String?
            var cycle = false
            for (index, hop) in hops.prefix(budget).enumerated() {
                let title = [hop.user.map { $0 + "@" }, hop.host, hop.port.map { ":\($0)" }].compactMap { $0 }.joined()
                guard let saved = isSavedAlias(hop.host), hop.user == nil, hop.port == nil else {
                    entries.append((title, nil, false))
                    continue
                }
                let isCycle = !visited.insert(EffectiveConfigCache.key(saved)).inserted
                entries.append((saved, saved, isCycle))
                if index == 0 { cycle = isCycle; next = isCycle ? nil : saved }
            }
            chain.insert(contentsOf: entries, at: 0)
            guard let next, !cycle else { break }
            current = next
        }
        return chain.enumerated().map { ProxyChainNode(id: $0.offset, title: $0.element.title, alias: $0.element.alias, isCycle: $0.element.isCycle) }
    }
}

enum ChainNodeState: Equatable {
    case pending, testing, done(ConnectionStatus), skipped
}

/// Tests the chain's saved hosts from the first hop; after a failure the rest are skipped.
@MainActor
@Observable
final class ProxyChainTest {
    private(set) var states: [Int: ChainNodeState] = [:]
    private(set) var isRunning = false

    func run(nodes: [ProxyChainNode], app: AppModel) async {
        isRunning = true
        defer { isRunning = false }
        states = [:]
        var failed = false
        for node in nodes {
            guard let alias = node.alias, !node.isCycle else { continue }
            if failed { states[node.id] = .skipped; continue }
            states[node.id] = .testing
            await app.connectionTests.test(alias, using: app.commandBuilder)
            let status = app.connectionTests.results[alias]?.status ?? .other
            states[node.id] = .done(status)
            if status != .reachable { failed = true }
        }
    }
}
