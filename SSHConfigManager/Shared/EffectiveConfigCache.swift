import Foundation
import Observation
import SSHConfigKit

/// `ssh -G` results per exact alias (spec v1.1 §5–6): at most two at once, one run per alias,
/// cleared whenever the saved file changes.
@MainActor
@Observable
final class EffectiveConfigCache {
    static let maxConcurrent = 2

    private(set) var results: [String: EffectiveOptions] = [:]
    private(set) var failures: [String: String] = [:]
    /// Bumped by `clear()`, so views can reload what an external change dropped.
    private(set) var generation = 0
    @ObservationIgnored private let runner: any ProcessRunning
    @ObservationIgnored private var inFlight: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var running = 0
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    init(runner: any ProcessRunning) {
        self.runner = runner
    }

    func options(for alias: String) -> EffectiveOptions? { results[alias] }
    func failure(for alias: String) -> String? { failures[alias] }

    func load(_ alias: String, using builder: SSHCommandBuilder) async {
        let key = alias
        if results[key] != nil || failures[key] != nil { return }
        if let task = inFlight[key] { await task.value; return }
        let currentGeneration = generation
        let task = Task { [runner] in
            await self.acquire()
            defer { self.release() }
            guard currentGeneration == self.generation else { return }
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
                let line = ConnectionClassifier.firstLine(result.stderr)
                let code = String(result.exitCode)
                self.failures[key] = result.timedOut
                    ? String(localized: "effective.error.timeout")
                    : (line.isEmpty ? String(localized: "effective.error.exit \(code)") : line)
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
