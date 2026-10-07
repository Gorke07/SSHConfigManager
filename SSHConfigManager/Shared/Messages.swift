import Foundation
import SSHConfigKit

/// Turns the package's typed results into localized, user-facing text.
enum Messages {
    static func text(for issue: DraftIssue) -> String {
        switch issue {
        case .controlCharacter(let field): String(localized: "issue.controlCharacter \(field)")
        case .emptyAlias: String(localized: "issue.emptyAlias")
        case .aliasHasWhitespace: String(localized: "issue.aliasHasWhitespace")
        case .duplicateAlias(let alias): String(localized: "issue.duplicateAlias \(alias)")
        case .invalidPort(let port): String(localized: "issue.invalidPort \(port)")
        case .invalidDirectiveKey(let key): String(localized: "issue.invalidDirectiveKey \(key)")
        case .forbiddenDirectiveKey(let key): String(localized: "issue.forbiddenDirectiveKey \(key)")
        case .emptyDirectiveValue(let key): String(localized: "issue.emptyDirectiveValue \(key)")
        case .identityFileMissing(let path): String(localized: "issue.identityFileMissing \(path)")
        }
    }

    static func text(for error: ConfigEditError) -> String {
        switch error {
        case .hostNotFound: String(localized: "edit.hostNotFound")
        case .controlCharacter: String(localized: "edit.controlCharacter")
        case .invalidDirectiveKey(let key): text(for: DraftIssue.invalidDirectiveKey(key))
        case .forbiddenDirectiveKey(let key): text(for: DraftIssue.forbiddenDirectiveKey(key))
        case .invalidAlias(let alias): String(localized: "edit.invalidAlias \(alias)")
        }
    }

    static func text(for error: ConfigStoreError) -> String {
        switch error {
        case .notEditable: String(localized: "store.notEditable")
        case .conflict, .writeFailed(.conflict): String(localized: "store.conflict")
        case .validationFailed(let message): String(localized: "store.validationFailed \(message)")
        case .validationTimedOut: String(localized: "store.validationTimedOut")
        case .writeFailed(.backupFailed(let detail)): String(localized: "store.backupFailed \(detail)")
        case .writeFailed(.writeFailed(let detail)): String(localized: "store.writeFailed \(detail)")
        case .saveCancelled: String(localized: "store.saveCancelled")
        case .saveInProgress: String(localized: "store.saveInProgress")
        case .validatorUnavailable(let detail): String(localized: "store.validatorUnavailable \(detail)")
        }
    }

    static func text(for error: KnownHostsStoreError) -> String {
        switch error {
        case .notEditable: String(localized: "knownHosts.notEditable")
        case .staleSelection: String(localized: "knownHosts.staleSelection")
        case .conflict, .writeFailed(.conflict): String(localized: "knownHosts.conflict")
        case .writeFailed(.backupFailed(let detail)): String(localized: "store.backupFailed \(detail)")
        case .writeFailed(.writeFailed(let detail)): String(localized: "store.writeFailed \(detail)")
        }
    }

    /// known_hosts load states: a missing file is normal (ssh creates it), not an error.
    static func knownHostsLoadText(for state: ConfigLoadState) -> String? {
        switch state {
        case .loaded: nil
        case .missing: String(localized: "knownHosts.missing")
        case .notUTF8: String(localized: "knownHosts.notUTF8")
        case .unreadable(let detail): String(localized: "knownHosts.unreadable \(detail)")
        }
    }

    static func text(for state: ConfigLoadState) -> String? {
        switch state {
        case .loaded: nil
        case .missing: String(localized: "load.missing")
        case .notUTF8: String(localized: "load.notUTF8")
        case .unreadable(let detail): String(localized: "load.unreadable \(detail)")
        }
    }

    static func text(for outcome: ValidationOutcome) -> String {
        switch outcome {
        case .valid: String(localized: "validation.valid")
        case .invalid(let message): text(for: ConfigStoreError.validationFailed(message))
        case .timedOut: text(for: ConfigStoreError.validationTimedOut)
        case .validatorUnavailable(let detail): text(for: ConfigStoreError.validatorUnavailable(detail))
        }
    }

    static func text(for error: HostResolverError) -> String {
        switch error {
        case .failed(let detail): String(localized: "hostKeyRemoval.resolveFailed \(detail)")
        case .timedOut: String(localized: "hostKeyRemoval.resolveTimedOut")
        case .unparsable: String(localized: "hostKeyRemoval.resolveUnparsable")
        }
    }

    static func text(for error: any Error) -> String {
        if let error = error as? ConfigStoreError { return text(for: error) }
        if let error = error as? ConfigEditError { return text(for: error) }
        if let error = error as? KnownHostsStoreError { return text(for: error) }
        if let error = error as? HostResolverError { return text(for: error) }
        let detail = error.localizedDescription
        return String(localized: "error.generic \(detail)")
    }
}
