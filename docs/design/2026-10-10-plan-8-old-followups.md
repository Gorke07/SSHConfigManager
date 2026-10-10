# Plan 8 — Plans 1–5 follow-ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Close every OPEN item from the follow-up lists of Plans 1–5.

**Source of work:** `docs/design/2026-10-10-plan-8-triage.md`. This is a triage of all 137 items against `main` at af92acb, with each item marked FIXED, OPEN, MANUAL or OBSOLETE. Each OPEN row gives the location, the proposed fix, the size and the risk. Every task below lists its row ids. The implementer reads exactly those rows. The row's proposed fix is the default; the implementer may choose a better fix that gives the same outcome and explains it.

**Specs:** `docs/design/2026-10-07-ssh-config-manager-design.md` (main) and `docs/design/2026-10-09-ui-improvements-design.md` (v1.1).

## Global Constraints

- macOS 26.0; Swift 6, `SWIFT_STRICT_CONCURRENCY = complete`. No new dependencies.
- Lossless editing: `render(parse(x)) == x`; only the bytes a feature owns change.
- Package: no locale-sensitive case APIs (`LocaleSafetyTests`). ssh Host matching is case-sensitive and alias identity is exact (Plan 7).
- Every user-visible string uses `String(localized:)` plus `Localizable.xcstrings` (en + tr, `translated`, `extractionState: manual`). Aliases, paths and ssh values use `Text(verbatim:)`. The checker forbids property-path interpolation and requires numbers to be passed as `String` via `%@`.
- **Tests never touch the real `~/.ssh`, `~/Library`, `UserDefaults.standard`, ssh-agent, keychain, pasteboard or Trash, and never run real ssh against hosts.** The existing pattern of a test agent on a `/tmp/sshcm.XXXXXXXX` socket, killed by PID, stays as it is. `ssh -G -F <temp file>` and `ssh-keygen` on temp files are allowed only where existing tests already use them; prefer fake runners.
- **The user works inside Ghostty.**
  - Never quit, kill or close terminals or their windows.
  - No synthetic keystrokes.
  - Terminate only your own processes, by explicit PID, never with pkill/killall patterns.
  - Never answer permission prompts.
  - Never launch the app.
- Commits: no `Co-Authored-By`, no Claude/Anthropic mention, no "Generated with". Never stage `SSHConfigManager/Shared/Localization/InfoPlist.xcstrings`.
- Package tests: `xcrun swift test --package-path Packages/SSHConfigKit`. App tests: `bash scripts/test-app.sh` (runs `-quiet`; rc 0 = pass).

## Scope decisions

- **2A-9 (localized bundle name) is deferred to the user.** It needs a product decision (should the Dock/Finder name change in Turkish?). It also lives in `InfoPlist.xcstrings`, which holds the user's own uncommitted change.
- MANUAL and OBSOLETE rows are not implemented. The final follow-ups doc lists the MANUAL ones.
- Items marked risky in the triage (P1-15b process groups, 2B-8 async launchers, P3-8a matching, P4-12a key model) are implemented with tests that pin the old safe behaviour where it must not change.

## Review Focus

1. Cancelling a connection test or ssh -G kills ssh's whole process tree, and never kills anything outside it.
2. Launching Terminal/iTerm2/Ghostty no longer blocks the UI, and the outcome (`launched`/`fellBack`/`failed`) is reported exactly as before.
3. A known_hosts delete removes exactly the lines `ssh-keygen -R` would remove, no more.
4. The editor never loses a directive: repeated single-value directives and form keys typed into "Other options" are preserved.
5. Backups for a symlinked `~/.ssh/config` keep working, and existing backups are still found after the `backupKind` change.

---

### Task 1: Localization checker, release script, logging, build

Rows: 2A-2c, 2B-16a, 2B-16b, P5-3, P5-5a, P5-5b, 2A-18a, 2A-18b (2A-9 deferred).

The checker changes come first so later tasks are checked by the stricter checker. Fix every violation the stricter checker finds in existing code within this task. Add Python unit tests in `scripts/test_check_localization.py` for each new rule.

Commit: `chore: stricter localization checker, notarytool log, missing error logs, build script fixes`

### Task 2: Kit I/O and process

Rows: P1-10, P1-11, P1-12, P1-14b, P1-15a, P1-15b, P3-9a, P3-9b.

- P1-15b: ProcessRunner starts the child in its own process group (`posix_spawn` with `POSIX_SPAWN_SETPGROUP`). Cancel and timeout send SIGTERM to the group, then SIGKILL after a grace period (P1-15a).
  - Keep the `ProcessRunning` protocol and its results unchanged: stdout, stderr, exitCode and timedOut semantics. On timeout or signal, record exitCode as today.
  - Test with a shell script that spawns a sleeping grandchild that writes its PID to a temp file. After cancel, that PID must be gone. Tests kill nothing else.
- P1-10: classify on ssh's own stderr lines (prefixed `ssh:` or the known OpenSSH message forms), not on a substring anywhere in the output.

Commit(s): `fix(kit): process groups and SIGKILL escalation, safer classification, Include and file edge cases`

### Task 3: Editor, form and save flow

Rows: 2A-4a, 2A-5, 2A-6, 2A-7, 2A-8, 2A-10, 2A-11, 2A-12a, 2A-12b, 2A-13.

- 2A-10 and 2A-11 go together. Repeated single-value directives and form keys typed in "Other options" must never be dropped or duplicated on save. Show the extra values in "Other options", read-only or editable, as the row suggests.
- 2A-13: migrate existing backups or keep finding them; add a test.

Commit(s): `fix: editor keeps repeated directives, config switch Save/Discard/Cancel, restore and conflict edge cases`

### Task 4: Diff and UI polish, accessibility

Rows: 2A-15a, 2A-15b, 2A-15c, 2B-13a, 2B-13c, 2B-14, 2B-15b.

Commit: `fix: diff rendering, accessibility and small UI polish`

### Task 5: Connect, launchers and the tests model

Rows: 2B-5, 2B-6, 2B-8, 2B-9a, 2B-9b, 2B-11a, 2B-11b, 2B-12, 2B-15a, P5-4.

- 2B-8: make `TerminalLaunching.launch` async. Run the AppleScript off the main thread, and wait for `open` with a termination handler. Update Connector, AppModel, the call sites (quick connect, Host menu, ConnectionBar, onboarding) and the tests. Keep `Connector.Outcome` and the fallback logic unchanged. The user-facing behaviour must be identical apart from not blocking.
- Rows needing a manual check (2B-9a, 2B-15a, P5-4) also get a line in `docs/design/manual-test-checklist.md`.

Commit(s): `fix: non-blocking launchers, Ghostty by bundle id, launcher robustness and test-run bookkeeping`

### Task 6: Known hosts

Rows: P3-3, P3-4, P3-5a, P3-5b, P3-6, P3-7, P3-8a, P3-8b, P3-10a, P3-10b, P3-10c.

- P3-8a: verify against real `ssh-keygen -F` / `-R` on a temp known_hosts file, which is allowed. Record what it matches for `host` and for `[host]:22`, and match exactly that. Add tests both ways.

Commit(s): `fix: known_hosts matching like ssh-keygen, clearer deletes, UserKnownHostsFile parsing`

### Task 7: Keys

Rows: P4-5, P4-6, P4-7, P4-9, P4-10, P4-11a, P4-11b, P4-11c, P4-12a, P4-12b, P4-13a, P4-13b, P5-6a.

Commit(s): `fix: key scanning, parsing and path identity edge cases`

### Task 8: Tests

Rows: P1-17a, 2A-17a, 2A-17e, 2B-17a, 2B-17b, 2B-17c, P3-11b, P4-8, P5-6b, P5-7. Also replace the real ssh-keygen in the P4-4 "form dirtied during generation" test with a deterministic fake runner if it is still real.

Commit: `test: time limits, gated runners, and the missing coverage from Plans 1–5`

### After all tasks

Update each of the six old follow-up docs with a header line pointing to Plan 8 and the triage. Then replace their contents with only what remains: the MANUAL items and 2A-9. Alternatively, consolidate the remaining items into `docs/design/2026-10-09-plan-6-followups.md`; pick one and say which.
