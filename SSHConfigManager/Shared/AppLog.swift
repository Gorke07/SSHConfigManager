import Foundation
import os

/// One logging subsystem (spec §10). Only error kinds are public; details (paths, ssh stderr) are
/// private; passphrases, key contents and process arguments/environment are never passed here.
enum AppLog {
    enum Category: String {
        case save, connect, knownHosts, keys, backups
    }

    private static let subsystem = "tr.com.mess.SSHConfigManager"

    static func error(_ category: Category, _ error: any Error) {
        let (kind, detail) = describe(error)
        Logger(subsystem: subsystem, category: category.rawValue)
            .error("\(kind, privacy: .public): \(detail, privacy: .private)")
    }

    /// `Type.case` (public) and the full description (private).
    static func describe(_ error: any Error) -> (kind: String, detail: String) {
        let detail = String(describing: error)
        let caseName = detail.prefix { $0 != "(" }
        return ("\(type(of: error)).\(caseName)", detail)
    }
}
