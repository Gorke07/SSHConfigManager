/// Launches the chosen terminal; falls back to Terminal when it is missing or fails,
/// but never hides a permission problem (the user must grant Automation access).
@MainActor
struct Connector {
    enum Outcome: Equatable {
        case launched(TerminalChoice)
        case fellBack(from: TerminalChoice)
        case failed(LaunchError)
    }

    let choice: TerminalChoice
    let isInstalled: (TerminalChoice) -> Bool
    let makeLauncher: (TerminalChoice) -> any TerminalLaunching

    func connect(_ request: LaunchRequest) async -> Outcome {
        if choice != .terminal && !isInstalled(choice) {
            return await fallBack(request)
        }
        do {
            try await makeLauncher(choice).launch(request)
            return .launched(choice)
        } catch LaunchError.automationDenied {
            return .failed(.automationDenied)
        } catch {
            if choice == .terminal { return .failed(error as? LaunchError ?? .failed(error.localizedDescription)) }
            return await fallBack(request)
        }
    }

    private func fallBack(_ request: LaunchRequest) async -> Outcome {
        do {
            try await makeLauncher(.terminal).launch(request)
            return .fellBack(from: choice)
        } catch {
            return .failed(error as? LaunchError ?? .failed(error.localizedDescription))
        }
    }
}
