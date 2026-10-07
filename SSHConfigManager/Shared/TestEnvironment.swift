import Foundation

enum TestEnvironment {
    /// True when the app process hosts unit tests; the app then never touches the real ~/.ssh.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
