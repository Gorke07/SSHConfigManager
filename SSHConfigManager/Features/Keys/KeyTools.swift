import AppKit
import SSHConfigKit

/// The key operations' side effects, injected so tests never touch the user's agent, keychain,
/// pasteboard or Trash.
@MainActor
struct KeyTools {
    var scanner: KeyScanner
    var manager: KeyManager
    /// `ssh-add --apple-use-keychain` (spec §8.3); false in tests.
    var useKeychain: Bool
    var recycle: @MainActor ([URL]) async throws -> Void
    var copyToPasteboard: @MainActor (String) -> Void

    static var live: KeyTools {
        KeyTools(
            scanner: KeyScanner(),
            manager: KeyManager(),
            useKeychain: true,
            recycle: { urls in _ = try await NSWorkspace.shared.recycle(urls) },
            copyToPasteboard: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            })
    }
}
