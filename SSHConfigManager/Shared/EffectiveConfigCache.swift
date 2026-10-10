import Foundation
import Observation
import SSHConfigKit

/// `ssh -G` results per alias (spec v1.1 §5–6): at most two at once, one run per alias,
/// cleared whenever the saved file changes.
@MainActor
@Observable
final class EffectiveConfigCache {
    static let maxConcurrent = 2

    private(set) var results: [String: EffectiveOptions] = [:]
    private(set) var failures: [String: String] = [:]
    @ObservationIgnored private let runner: any ProcessRunning
    @ObservationIgnored private var inFlight: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var running = 0
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var generation = 0

    init(runner: any ProcessRunning) {
        self.runner = runner
    }

    static func key(_ alias: String) -> String {
        String(String.UnicodeScalarView(alias.unicodeScalars.map { (65...90).contains($0.value) ? Unicode.Scalar($0.value + 32)! : $0 }))
    }

    func options(for alias: String) -> EffectiveOptions? { results[Self.key(alias)] }
    func failure(for alias: String) -> String? { failures[Self.key(alias)] }

    func load(_ alias: String, using builder: SSHCommandBuilder) async {
        let key = Self.key(alias)
        if results[key] != nil || failures[key] != nil { return }
        if let task = inFlight[key] { await task.value; return }
        let currentGeneration = generation
        let task = Task { [runner] in
            await self.acquire()
            defer { self.release() }
            let outcome: Result<ProcessResult, any Error>
            do {
                outcome = .success(try await runner.run(URL(filePath: "/usr/bin/ssh"),
                                                        arguments: builder.sshArguments(options: ["-G"], alias: alias),
                                                        environment: [:], timeout: .seconds(5)))
            } catch {
                outcome = .failure(error)
            }
            guard currentGeneration == self.generation else { return }
            switch outcome {
            case .success(let result) where result.exitCode == 0 && !result.timedOut:
                self.results[key] = EffectiveOptions(parsing: result.stdout)
            case .success(let result):
                self.failures[key] = result.timedOut ? "timed out" : ConnectionClassifier.firstLine(result.stderr)
            case .failure(let error):
                self.failures[key] = error.localizedDescription
            }
        }
        inFlight[key] = task
        await task.value
        if inFlight[key] == task { inFlight[key] = nil }
    }

    func clear() {
        generation += 1
        results = [:]
        failures = [:]
        inFlight = [:]
    }

    private func acquire() async {
        if running < Self.maxConcurrent { running += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { running -= 1 } else { waiters.removeFirst().resume() }
    }
}
