import SSHConfigKit
import SwiftUI

/// New key form (spec §8.3). Passphrases live only in this view's state and are cleared on close.
struct NewKeySheet: View {
    let keys: KeysModel
    let assignableAliases: [String]
    let close: () -> Void
    @State private var type: SSHKeyType = .ed25519
    @State private var fileName = ""
    @State private var comment = ""
    @State private var passphrase = ""
    @State private var passphraseRepeat = ""
    @State private var alias = ""

    var body: some View {
        Form {
            Picker(String(localized: "keys.form.type"), selection: $type) {
                Text(verbatim: "ed25519").tag(SSHKeyType.ed25519)
                Text(verbatim: "rsa 4096").tag(SSHKeyType.rsa)
            }
            TextField(String(localized: "keys.form.fileName"), text: $fileName)
            TextField(String(localized: "keys.form.comment"), text: $comment)
            SecureField(String(localized: "keys.form.passphrase"), text: $passphrase)
            SecureField(String(localized: "keys.form.passphraseRepeat"), text: $passphraseRepeat)
            if passphrase != passphraseRepeat {
                Text(String(localized: "keys.form.passphraseMismatch")).font(.footnote).foregroundStyle(.red)
            } else if !KeyManager.isValidPassphrase(passphrase) {
                Text(Messages.text(for: KeyManager.passphraseError(passphrase))).font(.footnote).foregroundStyle(.red)
            }
            Picker(String(localized: "keys.form.assign"), selection: $alias) {
                Text(String(localized: "keys.form.assignNone")).tag("")
                ForEach(assignableAliases, id: \.self) { Text(verbatim: $0).tag($0) }
            }
            if let message = keys.errorMessage {
                Text(verbatim: message).font(.footnote).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(String(localized: "action.cancel"), role: .cancel) { finish() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "keys.form.create")) {
                    Task {
                        if await keys.generate(type: type, fileName: fileName, comment: comment,
                                               passphrase: passphrase, assignTo: alias.isEmpty ? nil : alias) {
                            finish()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(keys.isWorking || passphrase != passphraseRepeat || !KeyManager.isValidPassphrase(passphrase))
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear {
            keys.errorMessage = nil
            fileName = keys.suggestedFileName(for: type)
            comment = keys.defaultComment
        }
        .onChange(of: type) { old, new in
            // Only replace a name that is still the previous suggestion; a typed name is the user's.
            if fileName == keys.suggestedFileName(for: old) { fileName = keys.suggestedFileName(for: new) }
        }
        .onDisappear { keys.errorMessage = nil }
    }

    private func finish() {
        passphrase = ""
        passphraseRepeat = ""
        close()
    }
}

struct AddToAgentSheet: View {
    let keys: KeysModel
    let row: KeyRow
    let close: () -> Void
    @State private var passphrase = ""

    var body: some View {
        Form {
            Text(verbatim: row.displayPath).font(.headline)
            SecureField(String(localized: "keys.form.passphrase"), text: $passphrase)
            if let message = keys.errorMessage { Text(verbatim: message).font(.footnote).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(String(localized: "action.cancel"), role: .cancel) { finish() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "keys.form.add")) {
                    Task { if await keys.addToAgent(row, passphrase: passphrase) { finish() } }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(keys.isWorking)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear { keys.errorMessage = nil }
        .onDisappear { keys.errorMessage = nil }
    }

    private func finish() {
        passphrase = ""
        close()
    }
}

struct ChangePassphraseSheet: View {
    let keys: KeysModel
    let row: KeyRow
    let close: () -> Void
    @State private var old = ""
    @State private var new = ""
    @State private var newRepeat = ""

    var body: some View {
        Form {
            Text(verbatim: row.displayPath).font(.headline)
            if row.key.encryption != .unencrypted {
                SecureField(String(localized: "keys.form.oldPassphrase"), text: $old)
            }
            SecureField(String(localized: "keys.form.newPassphrase"), text: $new)
            SecureField(String(localized: "keys.form.passphraseRepeat"), text: $newRepeat)
            if new != newRepeat {
                Text(String(localized: "keys.form.passphraseMismatch")).font(.footnote).foregroundStyle(.red)
            } else if !KeyManager.isValidPassphrase(new) {
                Text(Messages.text(for: KeyManager.passphraseError(new))).font(.footnote).foregroundStyle(.red)
            }
            if let message = keys.errorMessage { Text(verbatim: message).font(.footnote).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(String(localized: "action.cancel"), role: .cancel) { finish() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "keys.form.change")) {
                    Task { if await keys.changePassphrase(row, old: old, new: new) { finish() } }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(keys.isWorking || new != newRepeat || !KeyManager.isValidPassphrase(new))
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear { keys.errorMessage = nil }
        .onDisappear { keys.errorMessage = nil }
    }

    private func finish() {
        old = ""
        new = ""
        newRepeat = ""
        close()
    }
}

struct UploadKeySheet: View {
    let app: AppModel
    let row: KeyRow
    let close: () -> Void
    @State private var alias: String

    init(app: AppModel, row: KeyRow, close: @escaping () -> Void) {
        self.app = app
        self.row = row
        self.close = close
        _alias = State(initialValue: app.connectableAliases.first ?? "")
    }

    var body: some View {
        Form {
            Text(verbatim: row.displayPath).font(.headline)
            if app.connectableAliases.isEmpty {
                Text(String(localized: "keys.upload.noHosts")).font(.footnote).foregroundStyle(.secondary)
            } else {
                Picker(String(localized: "keys.form.host"), selection: $alias) {
                    ForEach(app.connectableAliases, id: \.self) { Text(verbatim: $0).tag($0) }
                }
            }
            Text(String(localized: "keys.form.uploadNote")).font(.footnote).foregroundStyle(.secondary)
            if row.key.publicURL == nil {
                Text(String(localized: "keys.upload.noPublicKey")).font(.footnote).foregroundStyle(.red)
            }
            if !row.key.hasPrivateKey {
                Text(String(localized: "keys.upload.needsPrivateKey")).font(.footnote).foregroundStyle(.red)
            }
            if let message = app.keys.errorMessage { Text(verbatim: message).font(.footnote).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(String(localized: "action.cancel"), role: .cancel) { close() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "keys.upload")) {
                    // Launched, fell back or Automation denied: close; the window shows the notice.
                    Task {
                        switch await app.keys.upload(row, alias: alias) {
                        case .launched?, .fellBack?, .failed(.automationDenied)?: close()
                        case .failed?, nil: break   // the error shows inline (nil: a launch is already running)
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(alias.isEmpty || row.key.publicURL == nil || !row.key.hasPrivateKey)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear { app.keys.errorMessage = nil }
        .onDisappear { app.keys.errorMessage = nil }
    }
}
