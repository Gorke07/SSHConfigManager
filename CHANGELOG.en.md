# Changelog

Notable changes to this project are recorded here; this is the English edition of [CHANGELOG.md](CHANGELOG.md) (Turkish), and the two list the same changes. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [0.3.0] - 2026-10-12

### New features

- **Automatic updates:** The app finds new versions itself with [Sparkle](https://sparkle-project.org), shows their release notes and installs them in one click. An update is installed only after its EdDSA and Developer ID signatures check out.
  - **Check for Updates…** is in the app menu and in Settings → General → Updates.
  - The same section has the automatic check and automatic download and install options, and shows the installed version.
  - Permission for automatic checks is asked on the second launch; the app then checks once a day.
- **About window:** The third-party licenses now include Sparkle's.

## [0.2.0] - 2026-10-12

### New features

- **Appearance:** Settings → General → Appearance chooses between **System**, **Light** and **Dark**. The choice applies before the first window draws, so a dark choice no longer flashes light at launch. The menu bar window, the quick connect panel, sheets and alerts follow it too.
- **Softer dark theme:** In dark mode, windows use a light graphite black with a slightly cool tint (`#212226`) instead of the standard dark gray. Forms, lists and tables stand out against it. Light mode is unchanged.
- **Show in Dock:** With this option in Settings → General turned off, the app runs in the menu bar only, and the Dock icon stays hidden even while a window is open. The option applies at once.
- **Settings button in the toolbar:** The main window's toolbar has a gear Settings button next to the Keys button (hint: ⌘,).
- **Passphrase-less key hint:** A private key without a passphrase is now marked only in the editor's **Identity Files** section, with an orange open lock on its row; hovering over it explains why. The warning is gone from the sidebar and the detail header, so every host that uses the key is no longer flagged with an orange triangle.

### Interface improvements

- **Redesigned Settings window:** The window is wider (640 pt) and split into **General**, **Files** and **Backups** tabs. Each tab is as tall as its content; no scroll bar appears.
- **Liquid Glass:**
  - The Test, Connect and favorite buttons in the connection bar use the glass style.
  - The connection status is shown in a glass capsule tinted with the result's color.
  - Warning banners are floating, tinted glass cards.
  - The quick connect panel opened with the shortcut has a Spotlight-like glass background.
  - The first-run screen sits in a glass card.
- **Menu bar hover:** The actions at the bottom of the menu bar window are highlighted in the accent color on hover, like native menu items. Host rows get a subtle hover background too.
- **File banners:** The **Choose…** button in the banner for a missing or unreadable config opens Settings straight on the **Files** tab.
- **Main window size:** The minimum height went from 480 pt to 560 pt; with Effective settings expanded, the content fits even in the smallest window.

### Performance

Measured on large files (2,000 Host blocks, a 50,000-line known_hosts, 200 keys).

- **Host lookups are cached:** `ConfigDocument` computes the host list and the alias index once per document version. Before, every sidebar row and every editor commit rescanned the whole file. With a status filter on, the sidebar used to freeze for 2-4 seconds; it no longer does.
- **Less linting:**
  - Host names defined by Include files come from a cache instead of being reread from disk on every keystroke.
  - The block an Include directive belongs to is found with a binary search.
  - When the key list refreshes, lint runs again only if a key file actually changed.
- **known_hosts loads in the background:**
  - The file no longer blocks the main thread at launch or on every external change.
  - An older read never overwrites a newer one.
  - ASCII lines are parsed at the byte level; about 2.5 times faster on large files.
- **Known Hosts window:** Rows are built once per file version and filtered once per query. The 230-400 ms delay on every search and selection is gone.
- **Quick connect:** The list is computed once per key or arrow key press instead of three times. Host basics stay cached until the saved file, favorites or recent connections change.

### Bug fixes

#### Data integrity

- **Accumulating comment garbage:** Typing ` #` inside a value in the editor appended the previous comment to the end of the config line on every keystroke. Values with an unquoted `#` that would start a comment now show a warning that blocks saving, and the old comment is no longer added again when a value changes.
- **Saving unconfirmed changes:** While the Save sheet was open, a change made from another window (assigning a key, restoring a backup, a new host) could be written to the file without the user seeing it. If the document changed, Save now shows the new diff again.
- **Overwrite after a conflict:** After a conflict, "Overwrite" could silently discard a newer external change that reached the disk while validation was running. It now overwrites only the disk version the user reviewed.
- **Symlink without a target:** If `~/.ssh/config` was a symlink whose target did not exist yet (e.g. dotfiles), "Create File" and a forced overwrite turned the symlink into a regular file. The symlink is now kept and its target file is created; if the target folder is missing, a clear error is shown.
- **Quoted Host pattern:** A pattern with a space such as `Host "my host"` was split into two patterns, `Host my host`, when another field in the block was edited. Its quotes are now kept.
- **CRLF files:** Deleting the last host from a CRLF file without a trailing line break left the file ending in a lone `\r`. Fixed.

#### Editing and saving

- **Config that could not be saved:** With a host selected that is not a valid ssh target, such as `Host a,b`, `Host -jump` or `Host web$1`, the file could not be saved at all. Validation now falls back to a neutral probe host; errors in the file are still reported.
- **Port given as a service name:** Valid service names such as `Port ssh` are now accepted. Before, every edit to such a host was blocked.

#### Interface

- **Blank window:** Expanding Effective settings made the sidebar and detail content disappear completely, leaving a white window. The list now scrolls within a bounded height, and the split view no longer overflows the window.
- **Stale form:** If the config changed outside the app while the main window was closed (menu bar only), the form showed the old values when the window reopened. The form now updates on reload.
- **Restoring a backup:** Even after confirming that the form would be discarded, an unapplied group name could be added to the restored document. Fixed.
- **Key sheets:**
  - A key operation that finished late could close another sheet opened after it. Each sheet now closes only itself.
  - Cancel is disabled while `ssh-keygen` or `ssh-add` runs, because these operations cannot be cancelled.

### Known limitations

- Hosts that come from an Include inside a `Host` block (a conditional Include) are listed as connectable, although ssh reads them only for names that match that block.

## [0.1.0] - 2026-10-10

First release.

- **Quick connect:** The ⌥⌘S panel and the menu bar, with smart search, favorites, recent connections and a connection preview. Supports Terminal, iTerm2 and Ghostty.
- **Safe editing:** Lossless editing, a diff preview before saving, `ssh -G` validation, automatic backups and atomic writes.
- **Understanding the config:** Effective settings and where they come from, the ProxyJump chain, warning badges and a connection test.
- **Known Hosts:** Search that covers hashed entries; deletes the same lines as `ssh-keygen -R`.
- **Keys:** Listing, creating, adding to the agent, uploading to a server, changing the passphrase and moving to the Trash.
- **Groups:** Host groups with `# group:` comments.
- English and Turkish interface.

[0.3.0]: https://github.com/messcenter/SSHConfigManager/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/messcenter/SSHConfigManager/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/messcenter/SSHConfigManager/releases/tag/v0.1.0
