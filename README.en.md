<p align="center">
  <img src="docs/assets/icon.svg" width="128" height="128" alt="SSH Config Manager icon">
</p>

<h1 align="center">SSH Config Manager</h1>

<p align="center">
  A native macOS app that manages your <code>~/.ssh/config</code> and connects you to servers in two keystrokes.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26%2B-111?logo=apple&logoColor=white" alt="macOS 26+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/SwiftUI-native-0A84FF" alt="SwiftUI">
  <img src="https://img.shields.io/badge/language-English%20%7C%20T%C3%BCrk%C3%A7e-4ade80" alt="English | Türkçe">
</p>

<p align="center">
  <b>English</b> · <a href="README.md">Türkçe</a>
</p>

---

The config file is the app's single source of truth. The app keeps no host information anywhere else. If you open the file and save it without changing anything, it stays identical byte for byte. When you edit a host, only its lines change; comments, indentation, and `Include` and `Match` blocks are kept exactly as they were.

## Features

### Quick connect

- **Global shortcut ⌥⌘S:** Opens a search panel from anywhere. Press ↩ without typing to connect to the host you used last.
- **Menu bar:** The same search and connect screen is in the menu bar. If you like, the app starts in the menu bar only at login.
- **Smart search:** Typing `prd web` puts `prod-web-01` first. Search matches the alias fuzzily, and HostName, User and group name as plain text.
- **Favorites and recent connections:** They lead the list while the search is empty.
- **Connection preview:** The selected host shows a `user@hostname:port · via bastion` line.
- **Terminal choice:** Terminal, iTerm2 or Ghostty. Connections open in the terminal you choose.

| Shortcut | Panel / menu bar |
|---|---|
| ↩ | Connect |
| ⌘↩ | Test the connection |
| ⌥↩ | Copy the `ssh` command |
| ⌘S | Add to / remove from favorites |

### Safe editing

- **Lossless editing:** Only the lines you change are changed in the file. If a setting is written more than once, none of them is lost.
- **Diff preview:** Before saving, you see exactly what will change in the file.
- **Validation:** Every save is checked with `ssh -G`. The app never writes a file ssh cannot read.
- **Backups and atomic writes:** A timestamped backup is taken before every save. Backups can be compared and restored from Settings.
- **External change tracking:** If the file changes in another editor, the app notices and does not overwrite your edits.
- **Groups:** You can group hosts with `# group:` comments. ssh reads these lines as comments and ignores them.

### Understanding the config

- **Effective settings:** Shows a host's settings as resolved by `ssh -G`, and where each one comes from: this block, `Host *`, another pattern, an Include file or the ssh default.
- **ProxyJump chain:** Shown as `This Mac → bastion → prod-db`, and the chain can be tested end to end.
- **Warning badges:** Flags a missing `IdentityFile`, an alias defined twice, and aliases that differ only in case.
- **Connection test:** Results are sorted into clear categories: connection refused, timeout, authentication failure, host key changed.

### Known Hosts

- Lists `known_hosts` entries. Search works on hashed entries too.
- Deleting removes exactly the lines `ssh-keygen -R` would remove, and nothing more.
- When a host key changes, you can remove the old entry in one step.

### Keys

- Lists the keys in `~/.ssh` with their type, fingerprint, passphrase status and the hosts that use them.
- **Creating:** Generates a new key and, if you like, assigns it to a host. It never overwrites an existing key.
- **Other actions:** Adding a key to the agent, uploading it to a server (`ssh-copy-id`), changing its passphrase and moving it to the Trash.

## Installation

Download the latest `SSH-Config-Manager-<version>.dmg` from the [Releases](https://github.com/messcenter/SSHConfigManager/releases/latest) page, open it and drag **SSH Config Manager** to the Applications folder. The app is signed with a Developer ID and notarized by Apple, so it opens without a Gatekeeper warning.

The app finds and installs new versions itself ([Sparkle](https://sparkle-project.org)). On the second launch it asks for permission to check automatically; this option and automatic downloads can be changed in **Settings → General → Updates**. **Check for Updates…** is in the app menu and in the same section. Automatic updates arrived in 0.3.0; if you use an older version, update by hand once.

On the first connection, macOS asks for permission for the app to control your terminal. Connecting needs this permission. You can change it later in **System Settings → Privacy & Security → Automation**.

## Building from source

**Requirements:** macOS 26, Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and `python3`.

```bash
git clone https://github.com/messcenter/SSHConfigManager.git
cd SSHConfigManager
xcodegen generate
open SSHConfigManager.xcodeproj
```

The Xcode project is generated from `project.yml` and is not in the repository. To change project settings, edit `project.yml` and run `xcodegen generate` again.

### Tests

```bash
# SSHConfigKit package: parser, known_hosts, keys, process management
xcrun swift test --package-path Packages/SSHConfigKit

# App: localization check and app tests
bash scripts/test-app.sh
```

The tests never touch your real `~/.ssh` directory, ssh-agent, keychain or `UserDefaults`, and never connect to a server. Everything they need is set up in temporary directories with fake processes.

### Making a release

```bash
SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" \
TEAM_ID=<TEAMID> NOTARY_PROFILE=sshcm-notary \
scripts/build-release.sh
```

This builds a signed and notarized `build/SSH-Config-Manager-<version>.dmg`, adds the new version to `appcast.xml` (the Sparkle update feed) with its English and Turkish notes from `CHANGELOG.en.md` and `CHANGELOG.md`, and prints the publishing commands. Without `SIGN_IDENTITY`, it builds an ad-hoc signed copy for trying out on this Mac only. See [docs/design/release.md](docs/design/release.md) (Turkish) for details and the pre-release checklist.

## Project layout

```
SSHConfigManager/
├── project.yml                 XcodeGen spec (version, signing, Info.plist)
├── SSHConfigManager/           SwiftUI app
│   ├── App/                    App, menus, menu bar, updates
│   ├── Features/               HostList, HostDetail, QuickConnect, Connect,
│   │                           KnownHosts, Keys, Settings
│   └── Shared/                 AppModel, settings, localization (String Catalog)
├── Packages/SSHConfigKit/      UI-independent Swift package with no dependencies
│   └── Sources/SSHConfigKit/
│       ├── Config/             Lossless parser, editing, validation, diff
│       ├── Resolve/            Effective settings and their sources, warnings
│       ├── KnownHosts/         known_hosts model, ssh-keygen compatible matching
│       ├── Keys/               Key scanning and management
│       ├── IO/                 Atomic writes, backups, file watching
│       ├── Process/            ProcessRunner with process group handling
│       ├── SSH/                ssh -G, connection test, command building
│       └── Stores/             @Observable state
├── SSHConfigManagerTests/      App tests
├── scripts/                    Tests, localization check, release
└── docs/design/                Design documents, plans, manual test checklist
```

The app's external dependencies are the [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT) and [Sparkle](https://github.com/sparkle-project/Sparkle) (MIT) packages. The `SSHConfigKit` package has no external dependencies at all.

## Privacy and permissions

- The app runs outside the sandbox, because it needs access to `~/.ssh`, has to run `ssh`/`ssh-keygen` and controls terminals with Apple Events.
- It sends no data anywhere. Settings, favorites and recent connections are kept only in `UserDefaults` on this Mac.
- Its only network request is the update check: the app reads `appcast.xml` on GitHub and, if there is a new version, downloads the DMG from GitHub Releases. No system information is sent. An update is installed only after its EdDSA signature and Developer ID signature check out.
- The only app-specific addition to the config file is the optional `# group:` comment lines.

## Localization

The interface is in English (the source language) and Turkish. The app follows the macOS language setting. All text is in `Localizable.xcstrings`. `scripts/check-localization.py` catches missing translations and unlocalized text before the build.

## Documents

Apart from the changelog, the documents are in Turkish.

| Document | Contents |
|---|---|
| [Changelog](CHANGELOG.en.md) | Changes in each version (English) |
| [Design document](docs/design/2026-10-07-ssh-config-manager-design.md) | Goals, architecture, safe editing rules |
| [Interface improvements v1.1](docs/design/2026-10-09-ui-improvements-design.md) | Quick connect, effective settings, groups |
| [Manual test checklist](docs/design/manual-test-checklist.md) | Checks to do by hand before a release |
| [Making a release](docs/design/release.md) | Signing, notarization, `.dmg`, updates |
