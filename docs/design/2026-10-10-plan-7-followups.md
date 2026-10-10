# Plan 7 — Plan 6 follow-ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Close every item in `docs/design/2026-10-09-plan-6-followups.md` that can be done without launching the app.

**Architecture:** Small, local fixes in SSHConfigKit (resolver, parsing, key reading) and the app (alias identity, memory, search, effective settings, detail/sidebar). No new subsystems.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Swift Testing, String Catalog (en+tr).

**Spec:** `docs/design/2026-10-09-ui-improvements-design.md` (v1.1), main spec `docs/design/2026-10-07-ssh-config-manager-design.md`. The follow-ups doc is the list of work.

## Global Constraints

- macOS 26.0; Swift 6, `SWIFT_STRICT_CONCURRENCY = complete`. No new dependencies.
- Lossless editing: `render(parse(x)) == x`; only the bytes a feature owns change.
- Package: no locale-sensitive case APIs (`LocaleSafetyTests`).
- **ssh Host matching is case-sensitive (verified 2026-10-10 with `ssh -G -F <tmp>`: `Host Web` + `Host web` → `ssh -G Web` gets Web's user, `ssh -G web` gets web's, `ssh -G WEB` matches neither).** Alias identity in the app is therefore exact string equality. Only the duplicate-alias *lint* keeps ASCII case folding, as a deliberate "likely mistake" warning (spec §8).
- Every user-visible string `String(localized:)` + `Localizable.xcstrings` (en + tr, `translated`, `extractionState: manual`); aliases, paths, ssh values `Text(verbatim:)`. Checker: no property-path interpolation; numbers as `String` via `%@`.
- **Tests never touch real `~/.ssh`, `~/Library`, `UserDefaults.standard`, ssh-agent, keychain, pasteboard, Trash; never run real ssh against hosts.** `ssh -G -F <temp file>` is allowed only for verifying semantics during development, never in tests.
- **The user works inside Ghostty:** never quit/kill/close terminals or their windows; no synthetic keystrokes; only your own processes, by PID; never answer permission prompts; never launch the app.
- Commits: no `Co-Authored-By`, no Claude/Anthropic mention, no "Generated with". Never stage `SSHConfigManager/Shared/Localization/InfoPlist.xcstrings`.
- Package tests `xcrun swift test --package-path Packages/SSHConfigKit`; app `bash scripts/test-app.sh` (runs `-quiet`; rc 0 = pass).

## Review Focus

1. Case-variant hosts (`Host Web` / `Host web`): Connect, Test, preview, effective settings, favorites, recents and quick connect all act on the exact alias.
2. Stored favorites/recents written by v1.1 (possibly case-variant duplicates, junk types) load without crashing and are normalized.
3. A config whose first line is an `Include` (OrbStack/Colima style) gets correct duplicate wording and correct sources.
4. Deleting an earlier occurrence of an alias keeps the selection on the same block.
5. An IdentityFile that points at a FIFO or directory never blocks or crashes the lint.

---

### Task 1: SSHConfigKit fixes — SendEnv tokens, included targets, ports, safe key reads

**Files:** `Packages/SSHConfigKit/Sources/SSHConfigKit/Resolve/ConfigResolver.swift`, `Resolve/EffectiveOptions.swift`, `Keys/KeyFileInspector.swift`, tests in `Packages/SSHConfigKit/Tests/SSHConfigKitTests/` (existing resolver/options/inspector test files).

**Produces:** `ConfigResolver.resolve(alias:document:targetHeader:targetFile:includes:)` — new `targetFile: URL? = nil` (standardized file URL of the block's file; nil = root document). Existing call sites keep compiling.

Requirements:
1. **SendEnv tokens.** A `SendEnv` line's value is split on whitespace (respecting the package's existing argument tokenizer if there is one — check `ConfigDocument`/directive helpers; quotes as ssh does) and each token is a separate value. A `-PATTERN` token removes earlier accumulated entries. **Verify the removal rule with real ssh first** (temp config, `ssh -G -F`): e.g. `SendEnv LANG LC_ALL LC_CTYPE X` then `SendEnv -LC_*` — record which entries survive (whether removal is by wildcard match of the entry against the pattern) and implement exactly that. Tests: multi-token line; removal by wildcard; removal of a token from a multi-token line; the old meaningless `-PATTERN` test replaced by one that fails if removal is a no-op.
2. **Included target block.** When `targetFile` is non-nil, a Host block inside the included file with that standardized URL and `index == targetHeader` gets `.thisBlock`; root blocks are never `.thisBlock` then. Test with an included document.
3. **Match inside a skipped Include.** An Include in an inactive block is skipped entirely (ssh opens it with NEVERMATCH). Add a test pinning that a `Match` inside such a skipped include neither sets `hasMatchBlocks` nor contributes values.
4. **Port parsing.** `JumpHop` port (both forms) accepts only 1–5 ASCII digits with value 1…65535; `+22`, `-1`, `0`, `65536`, ` 22`, `٢٢` are rejected (hop dropped, as today for invalid ports). Tests.
5. **Safe key reads.** `KeyFileInspector.readHead(of:)` opens only regular files: check the file type first (`FileManager.attributesOfItem` `.type == .typeRegular`, or `URLResourceValues.isRegularFile`, following symlinks) and throw a descriptive error otherwise. Test with a FIFO created via `mkfifo` in a temp dir (call `Darwin.mkfifo`) and a directory — both must throw promptly, not block.

Commit: `fix(kit): SendEnv tokens, included target blocks, strict ports, regular-file key reads`

### Task 2: Exact alias identity in the app

**Files:** `SSHConfigManager/Shared/AppModel.swift` (`savedHosts`, `savedAlias`, `savedConnectableHosts` comment), `Shared/HostMemory.swift`, `Shared/EffectiveConfigCache.swift`, `Features/QuickConnect/QuickConnectModel.swift`, `Features/HostDetail/ProxyChainModel.swift`, any other app-side ASCII/Unicode folding of aliases (grep `lowercased()`, `HostMemory.same`, `EffectiveConfigCache.key`); tests in `SSHConfigManagerTests/`; spec note.

Requirements:
1. `savedAlias(_:)` and the saved-hosts index use exact aliases. `Host Web` + `Host web` are two connectable hosts; the first block of an exact duplicate (`Host web` twice) still wins.
2. `HostMemory.same` becomes exact equality (rename if clearer, update callers). `EffectiveConfigCache.key` becomes identity (or is removed and callers use the alias). Quick connect dedupe and ProxyChain cycle detection use exact aliases.
3. HostLint duplicate counting stays ASCII-case-folded (deliberate warning, spec §8) — do not change it.
4. Tests: in one config `Host Web\n  User upper\nHost web\n  User lower\n`: both appear in `savedConnectableHosts` and quick connect; `savedAlias("WEB") == nil`; favoriting `web` does not favorite `Web`; recents keep both; the ssh -G cache keeps separate results for `Web` and `web` (FixedRunner per-alias or a recording runner); ProxyChain `a → A` is not a cycle.
5. Update the comment "case-insensitive, like ssh" and spec v1.1 wherever it still claims ssh alias matching is case-insensitive (§2 recents/favorites, §6 cache) — keep §8's lint rule.

Commit: `fix: exact, case-sensitive alias identity like ssh`

### Task 3: Favorites and recents robustness

**Files:** `SSHConfigManager/Shared/HostMemory.swift`, `Shared/AppModel.swift` (`toggleFavorite`), `Shared/Messages.swift` or wherever the error text lives, `Localizable.xcstrings`, `SSHConfigManagerTests/HostMemoryTests.swift`, `AppModelTests.swift`.

Requirements:
1. **Normalize on load:** non-dictionary data, non-array values and non-string/empty elements are dropped; duplicates (exact) removed keeping the first; favorites capped at `maxFavorites`, recents at `maxRecents`. Saving after load is not required unless something was dropped (then save the normalized form).
2. **Cap behaviour:** `toggleFavorite(_:existing:)` takes the set of aliases in the current config; before refusing at the cap it prunes favorites that are not in `existing`. If still at the cap it returns `false` and AppModel sets `errorMessage` to `favorite.limit %@` (en "You can keep up to %@ favorites. Remove one first.", tr "En fazla %@ favori tutabilirsin. Önce birini çıkar.") with the number as a String. Removing always succeeds.
3. **Recording:** confirm against spec v1.1 §2 which outcomes record a recent connection (`.launched`, `.fellBack`; key upload via `uploadKey` should NOT count as a connection unless the spec says so) and test each outcome: launched records, fellBack records, failure does not, uploadKey follows the spec.
4. **Tests:** limit with stale favorites pruned; limit with all present → false + message; corrupt stored data of several shapes; duplicate stored entries; recents keep the typed alias spelling exactly.

Commit: `fix: normalized host memory and a visible favorites limit`

### Task 4: Search scoring and a stable performance test

**Files:** `SSHConfigManager/Shared/FuzzyMatcher.swift`, `SSHConfigManagerTests/FuzzyMatcherTests.swift`.

Requirements:
1. **Scattered floor:** scattered alias matches score strictly above the other-fields tier: `300 − min(gaps, 199)` (min 101). Test: an alias with a scattered match over >200 gaps still ranks above a match found only in HostName.
2. **Multi-word scoring:** keep the sum of per-word scores (every word must match; all candidates of one query have the same word count, so sums compare like-for-like). Add a comment stating this and a test that `prod web` ranks an alias matching both words in the alias above one matching `web` only via HostName.
3. **Performance test:** replace the 500 ms wall-clock assertion with a deterministic bound — count search steps (an internal step counter the memoized search increments, exposed for tests) and assert it stays polynomial (e.g. ≤ alias.count × query.count × small constant) on the pathological input; if a timing check is kept, make it generous (≥ 5 s) and only as a hang guard.

Commit: `fix: search tiers never overlap and a deterministic performance test`

### Task 5: Effective settings accuracy, chain skipped state, cache tests, Include refresh

**Files:** `Features/HostDetail/EffectiveSettingsModel.swift`, `EffectiveSettingsView.swift`, `ProxyChainModel.swift`, `ProxyChainView.swift`, `Shared/AppModel.swift` (`resolvedConfig`), `Shared/EffectiveConfigCache.swift` tests, `App/AppDelegate.swift` (activation hook), `Packages/SSHConfigKit/Sources/SSHConfigKit/Stores/ConfigStore.swift` (include refresh), tests.

Consumes Task 1 (`targetFile:`).

Requirements:
1. **Normalized values:** when the resolver's first value differs from ssh -G's and `hasMatchBlocks == false`, the row's source is the resolver's source (ssh normalized the value, e.g. `ServerAliveInterval 1m` → `60`, `%h` tokens, case). `.uncertain` only when Match blocks exist. Update `mismatchesWithAMatchBlockAreUncertain` siblings; add a test for the no-Match case.
2. **Included hosts:** `resolvedConfig(forSavedAlias:)` passes the included host's standardized file URL and header line as `targetFile`/`targetHeader` when the saved alias's first block lives in an Include file (use `store.savedIncludedHosts`/`IncludedHost` file+line; check field names). Test: an included host's own `User` shows `.thisBlock`.
3. **Chain skipped state:** after a failure, every later node — including plain (non-alias) hops — shows `.skipped`. Plain hops before any failure show no state. Test.
4. **Include refresh:** edits to an Include file alone must refresh `includedHosts`/`savedIncludedHosts` and the effective-settings sources. Add `ConfigStore.refreshIncludes()` (re-reads include files for both the working and saved document; no change to the root file or dirty state) and call it from the app on `NSApplication.didBecomeActiveNotification`; when the included hosts actually changed, AppModel treats it like a saved-state change for caches (`effectiveConfig.clear()`, connection tests of included aliases may stay). Key the view's resolved computation so it recomputes after the refresh (e.g. include a refresh counter or the included-hosts value in the `.task(id:)`). Package test for `refreshIncludes()` with a temp include file edited on disk.
5. **Cache tests:** `peak == 2` with a gated runner (three loads, at most two concurrent, assert the observed peak is exactly 2); `clear()` then reloading the same alias runs ssh again and stores the new result; `switchConfig` clears `effectiveConfig` (results empty, generation bumped).

Commit: `fix: accurate effective-setting sources, chain skipped state and Include refresh`

### Task 6: Detail, sidebar and delete polish

**Files:** `Features/HostList/DetailView.swift`, `SidebarView.swift`, `MainWindow.swift`, `Features/HostList/StatusSummaryView.swift`, `Shared/AppModel.swift`, `Features/Connect/ConnectionTestsModel.swift` (doc comment), tests.

Requirements:
1. **Unapplied group text counts as a pending edit:** move the group field's draft into model state (AppModel or the editor model) so `hasPendingFormEdits` (or the existing pending-edit check used before switching hosts) is true while the trimmed draft differs from the saved group; switching hosts then shows the same confirmation the form gets, and "discard" resets the draft. After a disk reload the draft resets to the document's group. Test at the model level.
2. **Detail lint memoized:** `lintIssues(for:)` reuses one computed map while `store.document` and `store.includedHosts` are unchanged (cache keyed by equality of those values or a cheap revision you add to ConfigStore); the sidebar uses the same cache. Test that two calls with no change perform one key read (inject a counting encryption/fileExists closure or test via the memo).
3. **Selection after delete:** deleting occurrence k of an alias moves a selection of `.host(alias, m)` with m > k to `.host(alias, m − 1)`; other selections unchanged; deleting the selected item clears it as today. Test.
4. **Duplicate wording per Include:** replace the "any Include before the block" rule: for each Include directive above a root block, take the hosts of the files that directive resolves to (`store.includeResolver.includedDocuments(for:)`), and count it only if the directive is top-level or inside a Host block whose patterns match the alias (reuse the package's case-sensitive `wildcardMatch`/HostMatcher; folding for the comparison of plain names stays as HostLint does). Tests: top-of-file Include defining the alias → "later"; top-of-file Include not defining it but a later Include defining it → "first"; Include nested in a non-matching Host block → ignored.
5. **Toolbar:** `StatusSummaryView` adds no toolbar content when there are no results (no empty `HStack`/item).
6. **Doc comment:** move the misplaced `connectionTests` doc comment onto the declaration it describes.

Commit: `fix: pending group drafts, memoized lint, stable selection after delete, per-Include duplicate wording`

### After all tasks

Update `docs/design/2026-10-09-plan-6-followups.md`: mark closed items (or remove them) and keep only the manual QA list and anything a task explicitly could not do.
