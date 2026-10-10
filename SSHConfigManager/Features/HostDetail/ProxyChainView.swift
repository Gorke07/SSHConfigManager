import SSHConfigKit
import SwiftUI

/// `This Mac → bastion → host`, with a status per saved hop and a sequential chain test.
struct ProxyChainView: View {
    let model: AppModel
    let alias: String

    @State private var test = ProxyChainTest()

    private var cache: EffectiveConfigCache { model.effectiveConfig }

    private var nodes: [ProxyChainNode] {
        ProxyChainBuilder.nodes(
            for: alias,
            options: { cache.options(for: $0) },
            isSavedAlias: { model.savedAlias($0) })
    }

    var body: some View {
        let options = cache.options(for: alias)
        let command = options?.first("proxycommand")
        // ssh -G may print "proxycommand none" or omit it: both mean no ProxyCommand.
        let usesCommand = command.map { EffectiveConfigCache.asciiFolded($0) != "none" } ?? false
        let nodes = nodes
        Group {
            if usesCommand {
                Text(String(localized: "chain.proxyCommand"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if nodes.count > 1 {
                chain(nodes)
            }
        }
        .task(id: "\(alias)\u{0}\(cache.generation)") { await loadHops() }
    }

    private func chain(_ nodes: [ProxyChainNode]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "chain.title")).font(.subheadline.weight(.semibold))
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text(String(localized: "chain.thisMac"))
                        ForEach(nodes) { node in
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            nodeView(node)
                        }
                    }
                }
                Spacer(minLength: 0)
                Button(String(localized: "chain.test")) {
                    let current = nodes
                    Task { await test.run(nodes: current, app: model) }
                }
                .disabled(test.isRunning)
            }
        }
    }

    @ViewBuilder
    private func nodeView(_ node: ProxyChainNode) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: node.title).font(.body.monospaced())
            if node.isCycle {
                Text(String(localized: "chain.cycle")).foregroundStyle(.secondary)
            } else if let state = test.states[node.id], state == .testing {
                ProgressView().controlSize(.small)
            } else if test.states[node.id] == .skipped {
                Text(String(localized: "chain.skipped")).foregroundStyle(.secondary)
            } else if let hopAlias = node.alias {
                ConnectionStatusBadge(model: model.connectionTests, alias: hopAlias, showsTitle: false)
            }
        }
    }

    /// Loads ssh -G for every saved hop that is not loaded yet, until no new aliases appear.
    private func loadHops() async {
        for _ in 0..<ProxyChainBuilder.maxDepth {
            let pending = nodes.compactMap(\.alias).filter { cache.options(for: $0) == nil && cache.failure(for: $0) == nil }
            guard !pending.isEmpty else { return }
            for hop in pending {
                if Task.isCancelled { return }
                await cache.load(hop, using: model.commandBuilder)
            }
        }
    }
}
