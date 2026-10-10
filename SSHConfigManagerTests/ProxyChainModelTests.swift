import Foundation
import SSHConfigKit
import Testing
@testable import SSH_Config_Manager

@MainActor
struct ProxyChainModelTests {
    func options(_ map: [String: String]) -> (String) -> EffectiveOptions? {
        { alias in map[alias].map { EffectiveOptions(parsing: $0) } }
    }

    @Test func expandsSavedAliasesRecursively() {
        let nodes = ProxyChainBuilder.nodes(
            for: "db",
            options: options(["db": "hostname 10.0.0.5\nproxyjump bastion", "bastion": "hostname b.example.com\nproxyjump edge", "edge": "hostname e"]),
            isSavedAlias: { ["db", "bastion", "edge"].contains($0) ? $0 : nil })
        #expect(nodes.map(\.title) == ["edge", "bastion", "db"])
        #expect(nodes.map(\.alias) == ["edge", "bastion", "db"])
    }

    @Test func nonAliasHopsArePlainAndUntested() {
        let nodes = ProxyChainBuilder.nodes(for: "db", options: options(["db": "proxyjump admin@1.2.3.4:2200"]), isSavedAlias: { $0 == "db" ? $0 : nil })
        #expect(nodes.map(\.title) == ["admin@1.2.3.4:2200", "db"])
        #expect(nodes.first?.alias == nil)
    }

    @Test func multiHopListsKeepOrder() {
        let nodes = ProxyChainBuilder.nodes(
            for: "db",
            options: options(["db": "proxyjump a,b", "a": "hostname a", "b": "hostname b"]),
            isSavedAlias: { ["db", "a", "b"].contains($0) ? $0 : nil })
        #expect(nodes.map(\.title) == ["a", "b", "db"])
        #expect(nodes.map(\.alias) == ["a", nil, "db"])
    }

    @Test func laterHopsDoNotCountAsLoops() {
        let nodes = ProxyChainBuilder.nodes(
            for: "db",
            options: options(["db": "proxyjump a,b", "a": "proxyjump b"]),
            isSavedAlias: { ["db", "a", "b"].contains($0) ? $0 : nil })
        #expect(!nodes.contains { $0.isCycle })
    }

    @Test func onlyTheFirstHopOfAListExpands() {
        let nodes = ProxyChainBuilder.nodes(
            for: "db",
            options: options(["db": "proxyjump a,b", "a": "proxyjump edge", "b": "proxyjump other"]),
            isSavedAlias: { ["db", "a", "b", "edge", "other"].contains($0) ? $0 : nil })
        #expect(nodes.map(\.title) == ["edge", "a", "b", "db"])
    }

    @Test func cyclesAndDepthAreBounded() {
        let looped = ProxyChainBuilder.nodes(for: "a", options: options(["a": "proxyjump b", "b": "proxyjump a"]), isSavedAlias: { $0 })
        #expect(looped.contains { $0.isCycle })
        var deep: [String: String] = [:]
        for n in 0..<10 { deep["h\(n)"] = "proxyjump h\(n + 1)" }
        let bounded = ProxyChainBuilder.nodes(for: "h0", options: options(deep), isSavedAlias: { $0 })
        #expect(bounded.count <= ProxyChainBuilder.maxDepth + 1)
        let wide = ProxyChainBuilder.nodes(for: "t", options: options(["t": "proxyjump a,b,c,d,e,f,g,h"]), isSavedAlias: { $0 })
        #expect(wide.count <= ProxyChainBuilder.maxDepth + 1)
    }

    @Test func cycleCheckIsExact() {
        let nodes = ProxyChainBuilder.nodes(for: "A", options: options(["A": "proxyjump a"]), isSavedAlias: { $0 })
        #expect(!nodes.contains { $0.isCycle })
        let same = ProxyChainBuilder.nodes(for: "a", options: options(["a": "proxyjump a"]), isSavedAlias: { $0 })
        #expect(same.contains { $0.isCycle })
    }

    @Test func chainTestStopsAtTheFirstFailure() async throws {
        let tmp = try TempDir()
        let app = makeTestModel(tmp, config: "Host bastion\nHost db\n", runner: FixedRunner.invalid("Connection refused"))
        let nodes = [ProxyChainNode(id: 0, title: "bastion", alias: "bastion", isCycle: false),
                     ProxyChainNode(id: 1, title: "db", alias: "db", isCycle: false)]
        let test = ProxyChainTest()
        await test.run(nodes: nodes, app: app)
        #expect(test.states[0] == .done(.connectionRefused))
        #expect(test.states[1] == .skipped)
    }
}
