# Changelog

All notable changes to StS2-Launcher are recorded here. The project follows semantic versioning loosely while pre-1.0.

## 0.4.0

### Automation

- **Self-hosted runner for full APK builds.** New `.github/workflows/apk-build.yml` runs on every push to `main`, every `v*.*.*` tag, and on manual `workflow_dispatch`. It symlinks proprietary artifacts (`sts2.dll`, custom Godot fork, FMOD, signing keystore) from a runner-local `/opt/sts2/` tree into the workspace, runs `scripts/doctor.sh` and `scripts/build.sh --no-bump`, uploads the signed APK with a SHA-256 checksum, and cleans up the scoped `~/.gradle/gradle.properties` on exit. Runner setup — system user, toolchains, directory layout, signing-secret rotation — documented end-to-end in [`docs/self-hosted-runner.md`](docs/self-hosted-runner.md).
- **Tag-triggered GitHub Release drafting.** New `.github/workflows/release.yml` on `v*.*.*` tags verifies the tag matches `android/gradle.properties`, extracts the matching `## X.Y.Z` section from `CHANGELOG.md`, polls for the corresponding `apk-build` run to finish, then creates a **draft** release with the APK + checksum attached for manual publish.
- **Renovate with scoped auto-merge.** New `renovate.json` opens dependency PRs weekly (Monday mornings UTC). Patch + minor bumps for `xunit`, `xunit.runner.visualstudio`, `Microsoft.NET.Test.Sdk`, and GitHub Actions auto-merge after CI; `SteamKit2` and other production .NET deps, gradle plugins, and the wrapper always go through human review. `android/config.gradle` (NDK / SDK / build-tools) is Renovate-ignored.

### Testability

- **`BeaconMessage.TryParse` extracted** from `LanMultiplayerPatcher` into `src/STS2Mobile/Patches/BeaconMessage.cs`. Pure record-struct, no socket dependency. Nine new xunit tests cover valid parse, wrong prefix, missing fields, empty hostname, non-numeric / out-of-range port, null / empty bytes, and forward-compat extra fields.
- **`CloudSyncCoordinator.UserDataRootResolver` injection point** added so the always-on conflict backup (`BackupConflictInternal`) can be pointed at a temp dir in tests without Godot running. Production default still calls `ProjectSettings.GlobalizePath("user://")`.

### Known deferrals

- Full `CloudSyncCoordinator` conflict-path coverage requires splitting the class (partial-files) to isolate the many `sts2.dll` / Godot references in its Manual push / pull code from the pure conflict logic. Scoped for 0.5 so 0.4 ships the infra milestone without a speculative refactor.

### Developer experience

- `CONTRIBUTING.md` documents the linked-source test pattern, the release cadence, and the Renovate auto-merge policy.

## 0.3.0

### Security

- **Steam Keystore keys now request StrongBox on API 28+** with a safe fallback to the default TEE, then software. The realized security level is logged at every key retrieval so the `README` "hardware-backed" claim is verifiable on any device. (`android/src/com/game/sts2launcher/GodotApp.java`)
- **LAN discovery socket no longer enables `SO_REUSEADDR`.** A malicious app on the same device can no longer silently share the beacon port and hijack host announcements. Conflicting binds now fail loudly. (`src/STS2Mobile/Patches/LanMultiplayerPatcher.cs`)
- **Always-on conflict backup for cloud save overwrites.** Every destructive write in `CloudSyncCoordinator` now preserves the losing side in the app's private storage (`user://sts2_conflict_backups/`) *before* overwriting, independent of the user-facing `Local backups` toggle and `MANAGE_EXTERNAL_STORAGE`. Kept as a ring of the last 10 entries per filename so disk usage stays bounded. (`src/STS2Mobile/Steam/CloudSyncCoordinator.cs`)
- **New `SECURITY.md`** — private disclosure policy, scope, and documented known limitations (unauthenticated LAN multiplayer, best-effort Keystore hardware backing, broad external-storage permission).

### Robustness

- **Patch failures now surface in the launcher UI**, not just `logcat`. `PatchHelper` retains a 200-message ring buffer that the launcher controller replays on startup, and the UI filter now shows any `FAILED …` log entry alongside existing `[Cloud] …` messages. Silent Harmony skips during `ModEntry.Apply()` are finally visible to the user. (`src/STS2Mobile/PatchHelper.cs`, `src/STS2Mobile/Launcher/LauncherController.cs`)

### Developer experience

- **Unit tests for pure C# logic.** New `src/STS2Mobile.Tests/` xunit project. First coverage target is `SaveProgressComparer` (11 tests spanning `progress.save` cascade tiebreakers, `current_run.save` floor counting, and malformed-JSON fallback). The test project links source files via `<Compile Include>` rather than project-referencing `STS2Mobile.csproj`, so tests compile without `sts2.dll` / `GodotSharp.dll` / `0Harmony.dll`.
- **CI runs the tests.** New `tests` job in `.github/workflows/build-check.yml` executes `dotnet test` on every PR and push to `main`.

## 0.2.0

- Build reproducibility overhaul — see commits under the Tier 1–3 PRs.
- `scripts/doctor.sh` preflight with actionable checklist output.
- Fail-fast copies in `scripts/build.sh`; dynamic resolution of the .NET Android mono runtime `.so` path.
- NDK version, .NET TFM treated as single-source-of-truth (`android/config.gradle`, `STS2Mobile.csproj`).
- `CONTRIBUTING.md`, `.github/workflows/build-check.yml` (csharpier / shellcheck / native stubs).
- Launcher self-update checker, `--no-bump` build flag.

## 0.1.0

- Initial release.
