import Foundation
import os

/// One logging subsystem (spec §10). Only error kinds are public; details (paths, ssh stderr) are
/// private; passphrases, key contents and process arguments/environment are never passed here.
enum AppLog {
    enum Category: String {
        case save, connect, knownHosts, keys, backups, settings
    }

    private static let subsystem = Bundle.main.bundleIdentifier ?? "tr.com.mess.SSHConfigManager"

    static func error(_ category: Category, _ error: any Error) {
        let (kind, detail) = describe(error)
        Logger(subsystem: subsystem, category: category.rawValue)
            .error("\(kind, privacy: .public): \(detail, privacy: .private)")
    }

    /// A refusal caused by the user's own decision (not a failure): same public/private split, `.info` level.
    static func info(_ category: Category, _ error: any Error) {
        let (kind, detail) = describe(error)
        Logger(subsystem: subsystem, category: category.rawValue)
            .info("\(kind, privacy: .public): \(detail, privacy: .private)")
    }

    /// Public kind and private detail. The kind never contains an error payload: enums give `Type.case`,
    /// anything else gives type, domain and code (NSError bridging), never the user info.
    static func describe(_ error: any Error) -> (kind: String, detail: String) {
        let detail = String(describing: error)
        let type = "\(type(of: error))"
        let mirror = Mirror(reflecting: error)
        if mirror.displayStyle == .enum {
            if let label = mirror.children.first?.label {
                return ("\(type).\(label)", detail)
            }
            if !detail.isEmpty, detail.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) {
                return ("\(type).\(detail)", detail)
            }
            return (type, detail)
        }
        let ns = error as NSError
        return ("\(type)(domain: \(ns.domain), code: \(ns.code))", detail)
    }
}
