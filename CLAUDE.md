# Hand-off for Claude Code (and Codex review)

A short brief so the next session can pick up cold. Pair this with `README.md` (what the project is), `CONTRIBUTING.md` (how to develop), `SECURITY.md` (policy), `CHANGELOG.md` (what's in each version), and `docs/self-hosted-runner.md` (CI/CD runner setup).

## Project one-liner

Unofficial Android launcher for *Slay the Spire 2* that loads `sts2.dll` inside a custom Godot 4.5.1 engine and applies Harmony runtime patches to adapt the desktop game for mobile. Authenticates to Steam via SteamKit2, downloads depot files, syncs Steam Cloud saves, supports LAN multiplayer. Alpha.

## Current state (as of this hand-off)

- **Latest on `main`**: `bb6c190` — v0.2.0 work (build reproducibility).
- **Open PR**: [#2](https://github.com/fremus89/StS2-Launcher/pull/2) on branch `claude/evaluate-forked-repo-2VF0j`, head `f452232`. Stacks v0.3 (security + robustness) and v0.4 (automation) together. **All 4 CI checks green.**
- **Ready to merge.** After merge: see the `After merge` section below.

## Shipped in this PR

| Release | Focus | Key commits |
| --- | --- | --- |
| 0.3.0 | Keystore StrongBox fallback, LAN `SO_REUSEADDR` removed, always-on cloud conflict backup, patch failures surfaced in launcher UI, `SECURITY.md`, xunit bootstrapped with `SaveProgressComparer` tests. | `6d6c11b`, `9cd7b53`, `c1880eb`, `16d37d0` |
| 0.4.0 | Self-hosted runner workflow + runbook, tag-triggered draft releases, Renovate with scoped auto-merge, `BeaconMessage` extracted + tested, `UserDataRootResolver` injection point. | `df2976c`, `e1c14c7`, `10bedd5`, `5fbd0be`, `f452232` |

Full notes in `CHANGELOG.md`.

## What the next session should do

### Operational (not code)

1. **Review the PR** with Codex or manually, then merge to `main`.
2. **Provision the self-hosted Linux runner** per `docs/self-hosted-runner.md`. Dedicated user, `/opt/sts2/` layout, keystore chmod 600. Set `SIGNING_KEYSTORE_PASSWORD` and `SIGNING_KEYSTORE_ALIAS` as GHA repo secrets.
3. **Install the Renovate GitHub App** (https://github.com/apps/renovate) and approve its onboarding PR; `renovate.json` is already configured.
4. **Cut `v0.4.0` tag** on the merge commit. `apk-build.yml` assembles and signs the APK on the runner; `release.yml` drafts a GitHub Release with the CHANGELOG 0.4.0 section and the APK + SHA-256 attached. Maintainer clicks Publish.

### Code — v0.5 candidates (ordered by leverage)

1. **`CloudSyncCoordinator` partial-class split.** Move `ManualPushAllAsync` / `ManualPullAllAsync` / `GetSaveFilePaths` / `ReInjectSaveManager` into `CloudSyncCoordinator.Operations.cs`; keep `PushFileAsync` / `PullFileAsync` / `AutoSyncFileAsync` / `BackupConflictInternal` / `IsCorrupt` / `SaveProgressComparer`-caller in `CloudSyncCoordinator.Core.cs`. Unlocks ~15 in-memory tests for the real data-loss paths using hand-rolled `ISaveStore` / `ICloudSaveStore` fakes. Deferred from v0.4 because the stub surface otherwise balloons to include `GodotFileIo`, `SteamKit2CloudSaveStore`, three `*SaveManager` statics, and `UserDataPathProvider`.
2. **LAN HMAC authentication.** Beacon payloads are still unauthenticated (documented in `SECURITY.md` as a known limitation — the single High-severity item from the original review). Shared-secret HMAC-SHA256 signing, derived from an Android-Keystore-backed secret. Mutual verify at join.
3. **Surface Keystore security level in the launcher UI.** `GodotApp.java` already logs `SOFTWARE` / `TEE` / `STRONGBOX` at startup; bridge that to the launcher log panel so the user sees their actual threat model.
4. **CodeQL + secret scanning.** Free GitHub features, one checkbox each. Non-trivial findings go to SECURITY.md triage.

## Repo realities (don't waste time on these)

- **You cannot build the APK on a fresh clone.** `build.sh` needs proprietary artifacts (`sts2.dll`, `GodotSharp.dll`, `0Harmony.dll` from the desktop game export; custom Godot 4.5.1 fork; FMOD SDK; Spine runtimes). `scripts/doctor.sh` lists everything missing with actionable remediation. The self-hosted runner is the only place a full build happens in CI.
- **You cannot test the Harmony patches** without the game DLL. Tests cover pure-C# logic only (currently: `SaveProgressComparer`, `BeaconMessage`). CI runs `dotnet test` on every PR.
- **Legal grey zone.** Desktop-game-on-Android via engine fork + runtime patching. `README.md` and `SECURITY.md` carry the disclaimers; no game assets are committed. Don't add any. Don't add FMOD/Spine either — they're intentionally gitignored (`.gitignore` excludes `vendor/` and `upstream/`).
- **CI does not compile the main `STS2Mobile.csproj`** — it references `sts2.dll` via `HintPath` into `upstream/`, which isn't present on hosted runners. CI runs `csharpier --check` (lexing only, no compile) + `dotnet test` on `STS2Mobile.Tests` (uses linked sources + inline stubs).

## Quick-start commands for a new Claude session

```bash
# See what's missing to build locally
bash scripts/doctor.sh

# Run the pure-C# test suite (needs .NET 9 SDK)
dotnet test src/STS2Mobile.Tests/STS2Mobile.Tests.csproj

# Format C# code before committing
csharpier format src/STS2Mobile

# Sanity-check the shell scripts
shellcheck scripts/*.sh src/stubs/*.sh

# Check for >100-char lines in main sources (csharpier default limit;
# string literals over the limit are OK, lambdas/expressions are not)
awk 'length > 100 {print FILENAME":"NR":"length}' src/STS2Mobile/**/*.cs
```

## Branch / tag convention

- `main` is the release trunk.
- Feature branches use `<author>/<short-description>`. For agents: `claude/<task>` is fine.
- Version tags: `v0.X.Y`. Triggers `apk-build.yml` (on self-hosted) and `release.yml` (draft release on hosted).
- `android/gradle.properties`'s `export_version_name` must match the tag minus its `v` prefix — `release.yml` enforces this.

## Codex review — where to look closely

- **`src/STS2Mobile/Steam/CloudSyncCoordinator.cs`** — the always-on `BackupConflictInternal` writes to `user://sts2_conflict_backups/`. Verify the path traversal sanitization (chars collapsed to `_`) and ring-buffer trim (last 10 per filename) are correct.
- **`android/src/com/game/sts2launcher/GodotApp.java`** — StrongBox request path + fallback. The fallback catches `StrongBoxUnavailableException` and retries without `setIsStrongBoxBacked(true)`; I inlined the `KeyProperties.SECURITY_LEVEL_*` constants as literals because they were added in API 31 and min SDK is 24. Verify the `securityLevelName` mapping stays correct if Android adds more levels.
- **`.github/workflows/release.yml`** — polls the `apk-build` workflow for up to 35 minutes to find the matching tag run. Verify the `workflow_runs` matcher (`head_branch === tag` OR `head_sha === sha`) covers all real-world cases.
- **`.github/workflows/apk-build.yml`** — writes signing secrets to `~/.gradle/gradle.properties` scoped to the job home, cleans up in an `always()` step. Verify the cleanup actually fires on early-termination.
- **`renovate.json`** — auto-merge rules for dev-deps. Verify the allowlist isn't too broad; nothing that affects the shipping APK should auto-merge.

## Plan archive

The conversation where v0.2 → v0.4 were planned lives at `~/.claude/plans/toasty-wondering-sparkle.md` on the prior machine (not in the repo). The final v0.4 plan is the authoritative description of what was intended; anywhere this hand-off conflicts with what was actually shipped, trust `CHANGELOG.md` and the PR diff.
