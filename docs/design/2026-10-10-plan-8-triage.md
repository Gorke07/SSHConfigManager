# Triage of old follow-up lists (Plans 1–5)

Checked against `main` at `af92acb` (2026-10-10). Read-only: no code was changed and the app was not launched.
Statuses: **FIXED**, **OPEN**, **MANUAL** (needs a real run, login or release), **OBSOLETE/WONTFIX**.
Sizes: S < 1 h, M = a few hours, L = a day or more. Paths are relative to the repo root. The kit path prefix `Packages/SSHConfigKit/Sources/SSHConfigKit/` is shortened to `Kit/`.

Totals: FIXED 34 · OPEN 78 · MANUAL 13 · OBSOLETE/WONTFIX 12 (137 rows).

---

## docs/design/2026-10-07-plan-1-followups.md

| id | item | status | evidence / location | proposed fix (OPEN) | size | risk notes |
|---|---|---|---|---|---|---|
| P1-1 | Selection kept by alias, not line id | FIXED | `SidebarItem.host(alias:occurrence:)` `SSHConfigManager/Features/HostList/SidebarModel.swift:7`; delete follow-up `AppModel.swift:354-361` | | | |
| P1-2a | Diff: strip trailing `\r` on CRLF | FIXED | `Shared/Text/DiffPresenter.swift:62` | | | |
| P1-2b | Diff: "No newline at end of file" note | FIXED | `DiffPresenter.swift:34-36`, `.noNewline` row in `DiffTextView.swift:57` | | | |
| P1-3 | `testAll` stops queueing on cancel | FIXED | `Kit/SSH/ConnectionTester.swift:96,100`; test `ConnectionTesterTests.swift:66` | | | |
| P1-4a | Tell the user when `isWatching == false` | FIXED | `.notWatching` banner `Features/HostList/BannerBuilder.swift:27`, `BannerStack.swift:67` | | | |
| P1-4b | Restart the watcher after `createFile()` / path change | FIXED | `Kit/Stores/ConfigStore.swift:141`; `switchConfig` builds a new store `AppModel.swift:~703` | | | |
| P1-5 | Public inits for preview types | FIXED | `HostEntry`/`MatchEntry` `Kit/Config/ConfigDocument+Read.swift:20,48`; `IncludedHost` `IncludeResolver.swift:7`; `DiffLine`/`DiffHunk` `LineDiff.swift:11,27` | | | |
| P1-6 | Launchers must reject config paths with control chars | OBSOLETE | Redesign: nothing user-supplied is typed into a shell any more. ssh runs from a private `/bin/sh` script with single-quoted args, and only a `[A-Za-z0-9/._-]` script path is typed (`Features/Connect/TerminalLaunching.swift:61-86`). Ghostty gets argv directly. `AppModel.connect` still refuses C0 chars (`AppModel.swift:~308`). | | | |
| P1-7 | Note the `ssh -G` side effects (Match exec, DNS) | FIXED | `save.sshNote` `Features/HostList/SaveSheet.swift:19` | | | |
| P1-8 | `apply` re-resolves Includes on every edit | FIXED | Re-resolved only when Include paths change `Kit/Stores/ConfigStore.swift:149-153` | | | |
| P1-9 | Unbounded LCS table | FIXED | `LineDiff.maxTableCells = 4_000_000` with a greedy fallback `Kit/Config/LineDiff.swift:43,64-73` | | | |
| P1-10 | Classifier substring-matches all stderr; `detail` can be a harmless "Warning:" line | OPEN | `Kit/SSH/ConnectionTester.swift:44` (`stderr.contains`), `:48-52` (`firstLine` only skips `@` rows) | Match rules only on lines that start with `ssh:` or known OpenSSH prefixes, and skip `Warning:` lines in `firstLine` | S | Relies on English messages (`LC_ALL=C` is already forced). Add fixtures for banners and warnings. |
| P1-11 | `~user/` Include paths not expanded | OPEN | `Kit/Config/IncludeResolver.swift:84-94` (only `~` and `~/`) | Expand `~name/` with `getpwnam`; leave it unresolved if the user is unknown | S | Rare case. `KeyUsage.resolve` also ignores `~user` on purpose (`KeyUsage.swift:5-6`). |
| P1-12 | Appending to a CRLF file with no final newline mixes line endings | OPEN | `Kit/Config/ConfigDocument+Edit.swift:156-159`: the old last line gets `\n` without `\r` | In `addHost` (and any other append path), when `usesCRLF && !hasTrailingNewline`, add `\r` to the last line before appending | S | Must not touch any other bytes (lossless round-trip tests). |
| P1-13 | Reordering repeated keys does not reorder the file | WONTFIX | The v1 spec has no reordering UI. `updateHost` pairs by key and value (`ConfigDocument+Edit.swift:83-97`). | | | Revisit only if a reorder UI is added. |
| P1-14a | Fingerprint not rechecked right before write | FIXED | `SafeFileWriter.write` checks the disk fingerprint right before backup and rename (`Kit/IO/SafeFileWriter.swift:29-34`). The remaining check→rename window is P3-2. | | | |
| P1-14b | Parent directory not fsynced after rename | OPEN | `Kit/IO/SafeFileWriter.swift:63` | After `rename`, `open(dir, O_RDONLY)` + `fsync` (ignore errors) | S | APFS usually survives without it. Keep it best-effort. |
| P1-15a | Cancel sends SIGTERM only | OPEN | `Kit/Process/ProcessRunner.swift:91-93` | On cancel, escalate to SIGKILL after 1 s, as the timeout path does (`:79-82`) | S | |
| P1-15b | Grandchildren of a killed process are orphaned | OPEN | `ProcessRunner.swift` (no process group) | Start the child in its own process group (`posix_spawn` with `POSIX_SPAWN_SETPGROUP`, or `setpgid` in a small wrapper) and `kill(-pgid, …)` | M | `Foundation.Process` cannot set a pgid; this needs `posix_spawn`, which is a bigger change. The hard deadline already prevents hangs. |
| P1-15c | On timeout, `exitCode` is the signal number | WONTFIX | Callers check `timedOut` first (`ConnectionTester.swift:29`, `KeyManager.swift:140`) | | | Add a doc comment at most. |
| P1-16 | `FileWatcher.deinit` deadlocks if the last ref is dropped inside `onChange` | WONTFIX | By design: the callback never references the watcher, and stores hop to the MainActor (`Kit/IO/FileWatcher.swift:61`, `ConfigStore.swift:303-305`, `KnownHostsStore.swift:115-117`) | | | Holds while all owners are MainActor. |
| P1-17a | `GatedRunner.waitUntilEntered()` has no time limit | OPEN | `Packages/SSHConfigKit/Tests/SSHConfigKitTests/Support/TestSupport.swift:121-123`; no `.timeLimit` anywhere in either test target | Add `.timeLimit(.minutes(1))` to the suites that use gated runners, or race the wait against a deadline | S | |
| P1-17b | "Some tests lack positive controls" | OBSOLETE | Not specific enough to act on (no tests named). Many tests were added or rewritten since then (plans 2–7). | | | Fold into normal reviews. |

## docs/design/2026-10-07-plan-2a-followups.md

| id | item | status | evidence / location | proposed fix (OPEN) | size | risk notes |
|---|---|---|---|---|---|---|
| 2A-1 | Quit guard and window opener wired at launch | FIXED | `AppDelegate.model` is created at init (`App/AppDelegate.swift:8`). Every scene, including the menu-bar label, registers the opener (`App/SSHConfigManagerApp.swift:11,21,25,29,33,40`). | | | |
| 2A-2a | Checker covers `.help`, `Window`, `MenuBarExtra`, `ContentUnavailableView`, `confirmationDialog`, `alert`, `ProgressView`, `Stepper`, NSAlert | FIXED | `scripts/check-localization.py:26-32` | | | |
| 2A-2b | Checker reports every violation per file | FIXED | `check-localization.py:71-72` (finditer with line numbers) | | | |
| 2A-2c | Checker catches duplicate catalog keys | OPEN | `check-localization.py:46` (`json.loads` silently keeps the last duplicate) | `json.loads(..., object_pairs_hook=...)` that records duplicate keys at every level | S | Add a case to `scripts/test_check_localization.py`. |
| 2A-3 | File pickers allow folders | FIXED | `allowedContentTypes: [.data]` `Features/Settings/SettingsView.swift:112`, `Features/HostList/HostEditorView.swift:101` | | | |
| 2A-4a | Backup-restore errors only show in the main-window alert | OPEN | `Features/Settings/BackupsView.swift:100-103` writes `backups.model.errorMessage`. `BackupsModel.errorMessage` (`BackupsModel.swift:15,53`) is set but never shown. | Show errors in the Backups window: an `.alert` bound to `BackupsModel.errorMessage`, with restore setting it | S | |
| 2A-4b | Banner action errors only in the main window | OBSOLETE | Banners only exist in the main window (`BannerStack`), so the error appears where the action was taken | | | |
| 2A-5 | Switching config offers only Discard/Cancel (spec §6.1: Save/Discard/Cancel) | OPEN | `Features/Settings/SettingsView.swift:121-129` | Add a "Save" button that runs the save flow (or opens the main window's Save sheet) and switches on success | M | Save can fail validation or conflict. Switch only after a successful save. |
| 2A-6 | Save does not pass `probeAlias` (spec §4.6) | OPEN | `Features/HostList/SaveFlowModel.swift:36,95` call `prepareSave()` and `save()` without it. `probeAlias` is never passed anywhere in the app. | Give `SaveFlowModel` the selected host's alias (from `AppModel.selection`) and pass it to both calls | S | Use the edited (new) alias, not the saved one. |
| 2A-7 | Restore from backup is disabled when the config file is missing | OPEN | `Features/Settings/BackupsView.swift:93` (`loadState != .loaded`) | Allow `.missing`: `store.createFile()` then apply the backup (Save writes it), or restore straight to disk with the writer | S | `createFile` creates an empty file. Make sure an aborted restore does not leave a surprising empty file. |
| 2A-8 | Add/Duplicate with pending form edits creates the host even if the confirmation is cancelled | OPEN | Host is applied before `requestSelect`: `App/HostCommandMenu.swift:16,23`, `Features/HostList/MainWindow.swift:35`, `SidebarView.swift:113`, `OnboardingView.swift:12` | Check `model.hasPendingFormEdits` first and ask, then add or duplicate in the confirm handler (e.g. a `pendingAction` enum in AppModel) | M | Four call sites. Centralize them in AppModel. |
| 2A-9 | `CFBundleDisplayName` not localized (menu name stays English; tr `app.title` is "SSH Config Yöneticisi") | OPEN | Committed `SSHConfigManager/Shared/Localization/InfoPlist.xcstrings` has no `CFBundleDisplayName`/`CFBundleName` entry | Add tr values for `CFBundleDisplayName` (and `CFBundleName`, if wanted) to InfoPlist.xcstrings | S | That file has uncommitted Xcode-extracted noise and the plan rule says never to stage it as-is. Stage it by hand (patch). Decide whether the tr bundle name should change at all (the Dock/Finder name changes). |
| 2A-10 | Repeated single-value directive (two `User`): only the first is shown and the first edit drops the rest | OPEN | `Features/HostList/HostEditorModel.swift:39` (`value(for:)` takes the first). The draft emits one directive, and `updateHost` deletes the unpaired extras (`Kit/Config/ConfigDocument+Edit.swift:96`). | Put the extra occurrences of field keys into "Other options" (they stay in the file) and warn that ssh ignores them | M | Interacts with 2A-11. Keep the round-trip lossless when nothing is edited. |
| 2A-11 | Typing a field key (e.g. `Port`) in "Other options" creates a duplicate directive | OPEN | `Kit/Config/HostDraftValidator.swift:89-125` has no check against the form's field keys | Add a `DraftIssue.duplicateFieldKey(key)` (blocking, or a warning that says ssh uses the first) for `HostEditorModel.fieldKeys` + IdentityFile in other options | S | Needs en+tr strings. |
| 2A-12a | Conflict view: an unreadable or non-UTF-8 disk file looks like "everything added" | OPEN | `Features/HostList/SaveFlowModel.swift:71,89` (`?? ""`); `SaveSheet.swift:36` | When `conflictDiskText == nil`, show an "unreadable/not UTF-8" note instead of the diff | S | |
| 2A-12b | The "unreadable" message ends with an empty detail | OPEN | `SaveFlowModel.swift:81-85` (`.unreadable("")`) | Keep the real read error (`error.localizedDescription`) and pass it on | S | |
| 2A-13 | `backupKind` does not resolve symlinks (a symlinked `~/.ssh/config` gets a hashed folder) | OPEN | `Shared/AppModel.swift:149-153` (only `standardizedFileURL`) | Compare `resolvingSymlinksInPath()` of both URLs before falling back to the hash | S | Existing backups in the hashed folder would vanish from the list. Migrate them or list both folders. |
| 2A-14a | Carry-over: `testAll` cancellation | FIXED | Same as P1-3 | | | |
| 2A-14b | Carry-over: control-char config path in launchers | OBSOLETE | Same as P1-6 | | | |
| 2A-15a | Diff row widths jump in the lazy stack on long lines | OPEN | `Shared/Text/DiffTextView.swift:34-39` (LazyVStack, rows sized one by one) | Compute the widest row once (monospaced width × max length) and give all rows that `minWidth` | S | |
| 2A-15b | `DiffPresenter.rows` recomputed on every draw | OPEN | `DiffTextView.swift:35`; `BackupsView.swift:39` also re-reads the backup file and re-diffs on every body pass (`BackupsModel.swift:59-62`) | Compute the rows in `init` or memoize them by `hunks`; cache the hunks per selected backup in `BackupsModel` | S | |
| 2A-15c | Banner icons not hidden from VoiceOver | OPEN | `Features/HostList/BannerStack.swift:83` | `.accessibilityHidden(true)` on the icon | S | |
| 2A-16 | Delete confirmation may target a shifted row after a silent reload | FIXED | `pendingDelete = nil` on every saved-state change (`AppModel.swift:~114`, commit 2b09401) | | | |
| 2A-17a | Test: occurrence stability under search | OPEN | `SSHConfigManagerTests/SidebarBuilderTests.swift:50-62` checks titles only | Assert `item == .host(alias:"web", occurrence: 1)` when the search hides occurrence 0 | S | The code is correct (`SidebarModel.swift:43-45`); only the test is missing. |
| 2A-17b | Test: no-op save | FIXED | `ConfigStoreTests.swift:283` | | | |
| 2A-17c | Test: `saveCancelled` | FIXED | `ConfigStoreTests.swift:252` | | | |
| 2A-17d | Test: backup file exists | FIXED | `ConfigStoreTests.swift:56-71` | | | |
| 2A-17e | Locale-dependent search assertions | OPEN | `Shared/FuzzyMatcher.swift:28,37` (`locale: .current`); `SidebarBuilderTests.swift:55`, `FuzzyMatcherTests.swift:28` depend on the host locale | Inject a locale (default `.current`) and pin `en_US_POSIX` and `tr_TR` in the tests | S | |
| 2A-18a | `scripts/test-app.sh` hard-codes `arch=arm64` | OPEN | `scripts/test-app.sh:12` | `arch=$(uname -m)` | S | |
| 2A-18b | `TEST_HOST` repeats the product name | OPEN | `project.yml` (`TEST_HOST: "$(BUILT_PRODUCTS_DIR)/SSH Config Manager.app/…"`) | Define one custom setting (e.g. `APP_PRODUCT_NAME`) and use it for `PRODUCT_NAME` and `TEST_HOST` | S | |
| 2A-19 | Manual checklist (Settings/Backups windows, dark mode, Turkish UI) | MANUAL | `docs/design/manual-test-checklist.md` | | | |

## docs/design/2026-10-07-plan-2b-followups.md

| id | item | status | evidence / location | proposed fix (OPEN) | size | risk notes |
|---|---|---|---|---|---|---|
| 2B-1 | Start in the menu bar at login | FIXED | `App/AppDelegate.swift:62,67-89` (97bb67d, 4ec8b30). A real login is still needed: P5-1. | | | |
| 2B-2 | Saved host list goes stale while an external change waits | FIXED | `Kit/Stores/ConfigStore.swift:239-276` (`refreshSavedView`, ce6f8da, 68c3c03) | | | |
| 2B-3 | Unsaved new host: Connect disabled with no explanation | FIXED | `connect.saveToConnect` `Features/Connect/ConnectionBar.swift:39-43` (ce9406b) | | | |
| 2B-4a | `.requiresApproval` hint | FIXED | `Features/Settings/SettingsView.swift:73-78` (30a64fc) | | | |
| 2B-4b | Login toggle refreshed when Settings opens | FIXED | `SettingsView.swift:107-108` | | | |
| 2B-5 | `ConnectionTestsModel.test` does not check the saved file itself | OPEN | `Features/Connect/ConnectionTestsModel.swift:31` | Route tests through `AppModel.test(alias:)`, which maps with `savedAlias` (as `connect` does), and make the model method internal to that path | S | Callers: `ConnectionBar.swift:80`, `SidebarView.swift:100`, menu. |
| 2B-6 | `record()` keeps the alias in `runAliases`, so a later single test's spinner can vanish when Test All ends | OPEN | `ConnectionTestsModel.swift:86-96` | `runAliases.remove(alias)` in `record` | S | Add a test. |
| 2B-7 | Control-char filter misses C1 and U+2028/2029 | OBSOLETE | Those are not separators for `/bin/sh` single quotes or for argv. Nothing is typed apart from a safe script path (see P1-6). | | | |
| 2B-8 | `NSAppleScript` and `open` block the main thread (including the first TCC prompt) | OPEN | `Features/Connect/TerminalLaunchers.swift:41` (`executeAndReturnError`), `:61` (`waitUntilExit`) | Run the AppleScript on a background thread or with `NSUserAppleScriptTask`/`osascript`; use a termination handler for `open`; make `launch` async | M | `TerminalLaunching` is `@MainActor` and synchronous, so the API change ripples into Connector, AppModel and the tests. |
| 2B-9a | Ghostty is checked by bundle id but opened by name | OPEN | `Features/Connect/TerminalLaunching.swift:57` (`-na Ghostty.app`) | `open -n -b com.mitchellh.ghostty --args …` | S | Check with Ghostty 1.2.x that `-b` and `--args` behave the same (MANUAL). |
| 2B-9b | Launcher error details partly unlocalized | OPEN | `TerminalLaunchers.swift:16,20,38,52,62` (`"AppleScript"`, `"unsafe script path"`, `"open \(status)"`) shown via `connect.failed %@` | Map known failures to catalog strings and keep only ssh/OS messages verbatim | S | en+tr strings. |
| 2B-10a | Multi-alias `Host` lines: only the first alias is connectable | WONTFIX | Spec §4.3 table: "Bağlanılabilir: İlk alias ile" (`2026-10-07-ssh-config-manager-design.md:160`) | | | |
| 2B-10b | Results kept case-sensitively | OBSOLETE | Intended now: ssh matches Host case-sensitively (plan 7, b56bf56) | | | |
| 2B-11a | Temp script left in `$TMPDIR` if AppleScript succeeds but the shell never runs it | OPEN | `TerminalLaunching.swift:90-111`, `TerminalLaunchers.swift:25-34` | At launch, delete `sshcm-*.sh` older than ~10 min from the script directory | S | Only delete our own name pattern, and only regular files owned by the user. |
| 2B-11b | `write` loop does not retry `EINTR` | OPEN | `TerminalLaunching.swift:101-104` | `if count < 0 && errno == EINTR { continue }` | S | |
| 2B-12 | Menu-bar window exclusion relies on `NSPanel` and the class name | OPEN | `App/AppDelegate.swift:93-96` | Also require `styleMask.contains(.titled)` and `level == .normal` | S | Check the Dock-icon behaviour by hand after the change. |
| 2B-13a | Sidebar context menu starts with a divider on non-connectable rows | OPEN | `Features/HostList/SidebarView.swift:80-83` | Emit the `Divider()` only when `connectableAlias(for:) != nil` | S | |
| 2B-13b | ConnectionBar Test not disabled during Test All | FIXED | `ConnectionBar.swift:82` (`running` contains every Test All alias) | | | |
| 2B-13c | Badge detail repeated in `.help` | OPEN | `ConnectionBar.swift:23` (help = title + detail) and `:58` (detail text) | Pass `showsDetailInHelp: false` from ConnectionBar (keep it for sidebar badges) | S | |
| 2B-14 | Shortcut recorder sits between the login toggle and its error/approval text | OPEN | `Features/Settings/SettingsView.swift:71-81` | Move the `KeyboardShortcuts.Recorder` below the approval and error rows | S | |
| 2B-15a | `NSApp.activate()` partly defeats `.nonactivatingPanel` | OPEN | `Features/QuickConnect/QuickConnectPanel.swift:55` | Drop `activate()` and rely on `makeKeyAndOrderFront` for the non-activating panel (keep activate only for opening other windows) | S | Text-field focus without activation must be checked by hand. |
| 2B-15b | Doc comment says "borderless" | OPEN | `QuickConnectPanel.swift:9` (the panel is `.titled` with a hidden title bar) | Fix the comment | S | |
| 2B-15c | Unused `model`/`openSettings` params | OBSOLETE | v1.1 redesign: `QuickConnectView` uses both (footer, `QuickConnectView.swift:88,95`) | | | |
| 2B-15d | `selectedEntry` recomputed per row | FIXED | Computed once per body `QuickConnectView.swift:17` | | | |
| 2B-16a | Checker also matches inside comments and string literals | OPEN | `scripts/check-localization.py:64-72` (regex on raw text) | Strip `//` and `/* */` comments before matching (keep offsets for line numbers) | S | Don't strip string contents. `LOCALIZED` needs them. |
| 2B-16b | `.accessibilityLabel`, `Link`, `NSMenuItem` not covered | OPEN | `check-localization.py:26-32` | Add `\.accessibilityLabel\(\s*"`, `\bLink\(\s*"`, `NSMenuItem\(title:\s*"` | S | Add unit cases. |
| 2B-17a | `testAll` cancel test can pass vacuously under load | OPEN | `Packages/SSHConfigKit/Tests/SSHConfigKitTests/ConnectionTesterTests.swift:66-80` (sleep 50 ms, then cancel) | Use a gated runner: wait for the first entries, then cancel, then assert no results and ≤4 calls | S | |
| 2B-17b | `singleTestCannotRemoveATestAllEntry` relies on a ~50 ms margin | OPEN | `SSHConfigManagerTests/ConnectionTestsModelTests.swift:79-89` | Gate the runner instead of sleeping | S | |
| 2B-17c | No test for the `.testing` style | OPEN | no `.testing` reference in `SSHConfigManagerTests` | Add a style test for `ConnectionStatusStyle.testing` (symbol, title) | S | |
| 2B-M1 | Manual: Terminal/iTerm2/Ghostty connect; temp script runs and self-deletes in fish/zsh/tcsh | MANUAL | checklist "Plan 2b" | | | |
| 2B-M2 | Manual: Automation denied → alert and "Open Privacy Settings" | MANUAL | checklist | | | |
| 2B-M3 | Manual: menu bar list, ↩/⌘↩, search reset on reopen | MANUAL | checklist | | | |
| 2B-M4 | Manual: ⌥⌘S panel and shortcut recorder | MANUAL | checklist | | | |
| 2B-M5 | Manual: Dock icon (Settings stays open; Settings from the menu bar) | MANUAL | checklist | | | |
| 2B-M6 | Manual: launch-at-login toggle | MANUAL | checklist | | | |

## docs/design/2026-10-08-plan-3-followups.md

| id | item | status | evidence / location | proposed fix (OPEN) | size | risk notes |
|---|---|---|---|---|---|---|
| P3-1 | Table may write back an old selection after a reload (setter tags it with the current revision) | MANUAL | Setter unchanged: `Features/KnownHosts/KnownHostsModel.swift:48-52`. Check by hand: `ssh-keygen -R` in another terminal while the window is open. | If it reproduces, accept a setter write only when it differs from the stored set *and* it is not a superset of the stale ids | | |
| P3-2 | Concurrent ssh append between the content check and `rename` is lost | WONTFIX | Parked by decision. `Kit/IO/SafeFileWriter.swift:29-63`. ssh asks again on the next connection. | | | Only an advisory lock or a re-read right before rename would shrink it, not close it. |
| P3-3 | Delete confirmation omits port and fingerprint (two hashed rows look identical) | OPEN | `KnownHostsModel.swift:93-101` | Add the port (when not 22) and a shortened fingerprint per line | S | |
| P3-4 | Delete button enabled when every selected row is hidden by search | OPEN | `Features/KnownHosts/KnownHostsWindow.swift:57` (`selection.isEmpty`) | Disable on "visible selected rows are empty" (same filter as `requestRemoveSelection`) | S | |
| P3-5a | `userknownhostsfile` split on spaces (false "ssh reads another file" note) | OPEN | `Kit/SSH/HostResolver.swift:78` | Treat the whole value as one path when it equals the managed path; otherwise split. Or check how `ssh -G -F <tmp>` prints quoted paths first. | S | Check ssh's `-G` quoting before relying on it. |
| P3-5b | Symlinks not resolved in the comparison | OPEN | `Features/KnownHosts/HostKeyRemoval.swift:88-93` (`standardizedFileURL` only) | Compare `resolvingSymlinksInPath()` on both sides; skip `%d`/`%u` tokens or expand `%d` to home | S | |
| P3-6 | Mixed hashed+plain entries show only "(hashed)" and plain names are not found by substring search | OPEN | `KnownHostsModel.swift:136-141` (hosts replaced by the label) and `:76` (hashed rows skipped) | Show the plain names plus a "+ hashed" marker; set `isHashed` only when every name is hashed, or search the plain names separately | S | |
| P3-7 | Cancelled `ssh -G` keeps running (up to 5 s) | OPEN | `requestHostKeyRemoval` runs in an unowned `Task` (`ConnectionBar.swift:63`, `SidebarView.swift:104`); `cancelHostKeyRemoval` only clears state (`HostKeyRemoval.swift:111-113`) | Keep the task in AppModel and cancel it in `cancelHostKeyRemoval`. `ProcessRunner` already terminates on cancel. | S | |
| P3-8a | `[host]:22` entry counts as a match for `host` (more lenient than `ssh-keygen -F`) | OPEN | `Kit/KnownHosts/HostMatcher.swift:44` normalizes the entry via `lookupName(host:port:)` | Compare the entry's literal form (`host` or `[host]:port` as written) with the lookup name | S | Changes which lines a delete removes. Add tests both ways. |
| P3-8b | `a:b:c` treated as IPv6 | OPEN | `HostMatcher.swift:24-31` | Require a valid IPv6 literal (`inet_pton(AF_INET6)`) for multi-colon queries | S | Search only. |
| P3-9a | Not-UTF-8 file is re-read on every directory event | OPEN | `Kit/Stores/KnownHostsStore.swift:106-110` drops `diskFingerprint`, so `fileDidChange` (`:100-104`) always reloads and bumps `revision` | Keep the fingerprint of the unreadable bytes in `reset` for `.notUTF8` | S | Same pattern in `ConfigStore.reset` (`ConfigStore.swift:287-298`). Fix both. |
| P3-9b | Watcher keeps watching the old directory after the symlink target moves | OPEN | `KnownHostsStore.swift:112-119`; also `ConfigStore.swift:300-307` | On each event, re-resolve the target directory and restart the watcher if it changed (also watch the link's own directory) | M | Applies to both stores. FSEvents restart costs little. |
| P3-10a | Confirmation title/message flashes stale text while closing | OPEN | `KnownHostsWindow.swift:60-67` (message built from `pendingSummary`, which empties when `pendingRemoval` is cleared) | Use `confirmationDialog(_:isPresented:presenting:)` with the pending rows | S | |
| P3-10b | ⌫ shortcut ignores load state | OPEN | `KnownHostsWindow.swift:47` → `requestRemoveSelection` (`KnownHostsModel.swift:83-90`) | Guard on `loadState == .loaded` in `requestRemoveSelection` | S | |
| P3-10c | ⚠ icon has no accessibility label | OPEN | `KnownHostsWindow.swift:25-26` (help only) | `.accessibilityLabel(String(localized: "knownHosts.unparsable.help"))` | S | |
| P3-11a | Test fixture with `@cert-authority` | FIXED | `SSHConfigManagerTests/KnownHostsModelTests.swift:14,36` | | | |
| P3-11b | Test gaps: restore conflict on an externally created file; restore refused for not-UTF-8; `KnownHostsStore.fileDidChange`; second `requestHostKeyRemoval`; result seeded before `dropResult`; Turkish-locale match | OPEN | None in `KnownHostsStoreTests.swift`, `HostKeyRemovalTests.swift`, `KnownHostsModelTests.swift` | Add the six tests | M | |
| P3-M | Manual checklist "Plan 3 — Known Hosts" | MANUAL | checklist | | | |

## docs/design/2026-10-08-plan-4-followups.md

| id | item | status | evidence / location | proposed fix (OPEN) | size | risk notes |
|---|---|---|---|---|---|---|
| P4-1 | Fallback notice lost when the upload sheet closes | FIXED | Window-level `notice` not cleared by sheets (`Features/Keys/KeysModel.swift:24-27,134-139`; a8a2a95) | | | |
| P4-2a | Created-but-not-assigned: close the form and show the message in the Keys window | FIXED | `KeysModel.swift:112-118` | | | |
| P4-2b | Creating again makes a second key | FIXED | Fresh suggested name (`KeysModelTests.swift:211`) | | | |
| P4-3a | Upload clears unrelated main-window alerts | FIXED | Saved and restored `KeysModel.swift:127-145` (b53deea) | | | |
| P4-3b | "Open Privacy Settings" missing in the Keys window | FIXED | `Features/Keys/KeysWindow.swift:117-118` | | | |
| P4-4 | "Form dirtied during create" test can loop forever | FIXED | 30 s deadline `SSHConfigManagerTests/KeysModelTests.swift:199-202` | | | Still runs real ssh-keygen and is timing-based. A fake runner would be better (see Tests group). |
| P4-5 | `.pub`-only overwrite race (ssh-keygen only asks about the private key) | OPEN | Check-then-run `Kit/Keys/KeyManager.swift:71-79` | Generate into a private temp dir, then `link(2)` both files into place (fails if they exist), then unlink the temp files | M | Keep the 0600 mode and the comment. Tiny window. Low priority. |
| P4-6 | `AskPass.make` leaves the directory behind if `setAttributes` throws | OPEN | `Kit/Process/AskPass.swift:28` | `do { try … } catch { askPass.remove(); throw error }` | S | |
| P4-7 | Encrypted key with a nil passphrase reports "wrong passphrase" | OPEN | `KeyManager.swift:94,101` (nil → "" → asked → wrong) | When `passphrase == nil && askPass.wasAsked`, throw a new `.passphraseRequired`; the UI then prompts | S | New error case, so Messages and xcstrings change too. |
| P4-8 | `TestAgent` does not throw if the socket never appears | OPEN | `Packages/SSHConfigKit/Tests/SSHConfigKitTests/Support/TestAgent.swift:19-21` | Throw after the loop if the socket is still missing (and terminate the process) | S | |
| P4-9 | Host form key menu only refreshes while the list is empty | OPEN | `Features/HostList/HostEditorView.swift:66` | Refresh on menu appear (throttled) or on `didBecomeActive` | S | `refresh` runs ssh-keygen per key. Throttle it. |
| P4-10 | IdentityFile duplicate check uses string equality (`~/…` vs absolute) | OPEN | `Shared/AppModel.swift:660` | Compare `KeyUsage.resolve` + `canonicalPath` of the existing values against the new URL | S | |
| P4-11a | PEM `Proc-Type` check is only a substring test for `ENCRYPTED` | OPEN | `Kit/Keys/KeyFileInspector.swift:72` | Parse `Proc-Type: 4,ENCRYPTED` exactly (split on `,`) | S | |
| P4-11b | `PublicKeyInfo` does not validate the type | OPEN | `KeyFileInspector.swift:21-22` | Check that the base64 blob's leading string equals `parts[0]` (and/or a known-type prefix list) | S | Certificates and `sk-` types must still parse. |
| P4-11c | Repeated spaces in a comment collapse to one | OPEN | `KeyFileInspector.swift:20,24` | Take the comment as the raw remainder after the second field | S | |
| P4-12a | Unreadable private key shown as public-only | OPEN | `Kit/Keys/KeyScanner.swift:76-79` (silent return), then `:99` lists the `.pub` alone | Record unreadable private keys (e.g. `encryption: .unknown`, `privateURL` set, `unreadable: true`) and skip the public-only path for them | M | `SSHKey` model change, which reaches the UI columns. |
| P4-12b | Scan does synchronous file I/O in an async context | OPEN | `KeyScanner.swift:41` (`discover` runs inline) | Run `discover` in a detached task (or on a nonisolated executor) | S | |
| P4-13a | `-F` and `..` path resolution is lexical | OPEN | `Kit/SSH/SSHCommandBuilder.swift:14-18`, `KeyUsage.canonicalPath` `Kit/Keys/KeyUsage.swift:19-21`, `AppModel.keyDirectories` | When both files exist, compare `URLResourceKey.fileResourceIdentifierKey` (or `stat` dev+ino) | S | |
| P4-13b | APFS case-insensitivity ignored in comparisons | OPEN | same places | Covered by the inode comparison in P4-13a | S | |
| P4-M | Manual: `--apple-use-keychain` agent add; Ghostty keeps the ssh-copy-id window open | MANUAL | checklist "Plan 4 — Anahtarlar" | | | |

## docs/design/2026-10-08-plan-5-followups.md

| id | item | status | evidence / location | proposed fix (OPEN) | size | risk notes |
|---|---|---|---|---|---|---|
| P5-1 | Login launch detection (`kAEOpenApplication` + `keyAELaunchedAsLogInItem`) on macOS 26 with `SMAppService` | MANUAL | `App/AppDelegate.swift:62`, `App/LaunchContext.swift`; guard `:67-89` | If the window can stay open (never key, or key after 3 s): close main windows on the next run-loop turn and once more after a short delay, without waiting for key | | Needs a real login. |
| P5-2 | Signed and notarized release paths never run | MANUAL | `scripts/build-release.sh:44-80`; `docs/design/release.md` | | | First real release is a trial run. |
| P5-3 | When notarization is rejected, the script only prints the `notarytool log` command | OPEN | `scripts/build-release.sh:70-73` | If `id` is non-empty, run `xcrun notarytool log "$id" --keychain-profile …` (don't fail on its own error), then exit 1 | S | Can only be checked with a real Developer ID (MANUAL). |
| P5-4 | The login guard closes a main window the user opens within 3 s | OPEN | `App/AppDelegate.swift:71-81` | Disarm `loginLaunchGuard` when `openMainWindow` is called by the user (menu bar, Dock reopen, panel) | S | Must not disarm on SwiftUI's own automatic window restore. |
| P5-5a | Host add errors not logged | OPEN | `App/HostCommandMenu.swift:16,24`, `Features/HostList/MainWindow.swift:36`, `OnboardingView.swift:13`, `SidebarView.swift:115` | `AppLog.error(.edit, error)` in each catch (or centralize in an AppModel helper; see 2A-8) | S | |
| P5-5b | Settings file import errors not logged | OPEN | `Features/Settings/SettingsView.swift:114` (`.failure` dropped silently) | Log and show `invalidMessage` / `knownHostsInvalid` on `.failure` | S | |
| P5-6a | `createdButNotAssigned` read only by tests | OPEN | `Features/Keys/KeysModel.swift:32,89,114` | Remove it (the sheet closes now) and assert on `notice` in the test | S | |
| P5-6b | Outdated test name | OPEN | `SSHConfigManagerTests/KeysModelTests.swift:189` (`…KeepsTheSheetConsistent`) | Rename, e.g. `createdButNotAssignedClosesWithAWindowNotice` | S | |
| P5-7 | `isUnsavedHost` tests miss rename, letter case and `.included` | OPEN | `SSHConfigManagerTests/AppModelTests.swift:335-354` | Add: a renamed saved host is unsaved; a `Web`/`web` case variant is unsaved (exact identity); `.included` items are never unsaved | S | |
| P5-M | Manual checklist "Plan 5" and the release checklist | MANUAL | `docs/design/manual-test-checklist.md`, `docs/design/release.md` | | | |

---

## Proposed grouping

Every OPEN item is in exactly one task (78 in total).

1. **Kit I/O and process** (8): P1-10 classifier, P1-11 `~user` Include, P1-12 CRLF append, P1-14b dir fsync, P1-15a SIGKILL on cancel, P1-15b process group, P3-9a not-UTF-8 re-read (both stores), P3-9b watcher follows a moved symlink target (both stores). *M–L. P1-15b is the risky one: `posix_spawn` instead of `Process`. It can be split off.*
2. **Editor, form and save flow** (10): 2A-4a backup errors in the Backups window, 2A-5 Save/Discard/Cancel when switching config, 2A-6 `probeAlias`, 2A-7 restore with a missing file, 2A-8 Add/Duplicate after confirmation, 2A-10 repeated single-value directives, 2A-11 field key in Other options, 2A-12a/2A-12b conflict view for unreadable disk text, 2A-13 symlink-aware `backupKind` (with backup migration). *M. Do 2A-10 and 2A-11 together.*
3. **Diff and UI polish / accessibility** (7): 2A-15a row widths, 2A-15b memoized rows and backup hunks, 2A-15c banner icons hidden from VoiceOver, 2B-13a context-menu divider, 2B-13c badge help duplication, 2B-14 recorder placement, 2B-15b panel doc comment. *S, low risk.*
4. **Connect, launchers and tests model** (10): 2B-5 saved-file guard in tests, 2B-6 `runAliases` cleanup, 2B-8 non-blocking AppleScript/`open` (async launcher API), 2B-9a Ghostty by bundle id, 2B-9b localized launcher errors, 2B-11a stale script sweep, 2B-11b EINTR, 2B-12 Dock window filter, 2B-15a panel activation, P5-4 login guard vs a user-opened window. *M. 2B-8 changes the `TerminalLaunching` protocol. 2B-9a, 2B-15a and P5-4 need manual checks.*
5. **Known hosts** (11): P3-3 confirmation details, P3-4 Delete enabled state, P3-5a/P3-5b UserKnownHostsFile parsing and symlinks, P3-6 mixed hashed/plain rows, P3-7 cancel `ssh -G`, P3-8a literal `[host]:22` matching, P3-8b IPv6 query check, P3-10a dialog `presenting:`, P3-10b ⌫ load guard, P3-10c ⚠ label. *M. P3-8a changes which lines get deleted, so it needs careful tests.*
6. **Keys** (13): P4-5 race-free generate, P4-6 AskPass cleanup, P4-7 passphrase-required error, P4-9 key menu refresh, P4-10 canonical IdentityFile duplicate check, P4-11a/P4-11b/P4-11c key parsing, P4-12a unreadable private keys, P4-12b off-actor scan, P4-13a/P4-13b inode-based path identity, P5-6a remove `createdButNotAssigned`. *M. P4-12a changes the `SSHKey` model.*
7. **Localization checker, release script, logging, build** (9): 2A-2c duplicate catalog keys, 2B-16a ignore comments, 2B-16b more APIs, 2A-9 localized bundle name (InfoPlist.xcstrings hand-staged), P5-3 run `notarytool log`, P5-5a/P5-5b missing error logs, 2A-18a `uname -m`, 2A-18b single product-name setting. *S. 2A-9 needs a decision on the tr bundle name.*
8. **Tests** (10): P1-17a time limits, 2A-17a occurrence-under-search test, 2A-17e pinned locale for search, 2B-17a/2B-17b gated runners instead of sleeps, 2B-17c `.testing` style, P3-11b the six known_hosts tests, P4-8 TestAgent throws, P5-6b test rename, P5-7 `isUnsavedHost` cases. *S–M, no product risk. Also consider replacing the real ssh-keygen in the P4-4 test with a fake runner.*
