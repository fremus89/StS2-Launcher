# Contributing to StS2-Launcher

Thanks for your interest. This is an unofficial community project; please review the legal posture in [`README.md`](README.md) before getting involved.

## Quick start

```bash
git clone https://github.com/fremus89/StS2-Launcher.git
cd StS2-Launcher

# Check what you still need to install / source
bash scripts/doctor.sh

# Once doctor reports zero failures:
bash scripts/build.sh
```

`scripts/doctor.sh` runs first inside `scripts/build.sh` and aborts the build if any prerequisite is missing. Run it on its own at any time to see a checklist of what's left.

## Sourcing the unredistributable bits

Some artifacts cannot be committed to this repository. The doctor script tells you exactly which ones are missing and where they go; the table below is the same information in one place:

| Artifact | Path | Source |
| --- | --- | --- |
| `sts2.dll`, `GodotSharp.dll`, `0Harmony.dll` | `upstream/godot-export/.godot/mono/publish/arm64/` | Export of the desktop game (`.godot/mono/publish/arm64/`). Owning the game on Steam is required. |
| Custom Godot 4.5.1 source | `vendor/godot/` | Project's Godot fork; clone separately. |
| FMOD Engine | `vendor/fmod-sdk/` | https://www.fmod.com/download (free account; commercial license required for revenue). |
| Godot Android libs | `android/libs/release/arm64-v8a/libgodot_android.so` + `android/libs/release/godot-lib.template_release.aar` | Built from `vendor/godot/` via `scripts/build-godot.sh`. |
| `sts2.keystore` | `android/sts2.keystore` | Generated locally; never commit. |
| Signing credentials | `~/.gradle/gradle.properties` | `release_keystore_password=...` and `release_keystore_alias=...`. |

## Single-source-of-truth versions

To avoid version drift, only edit the canonical location:

| Concern | Canonical file | Consumed by |
| --- | --- | --- |
| Android NDK | `android/config.gradle` (`ndkVersion`) | `src/stubs/build_stubs.sh`, `scripts/doctor.sh`, `scripts/build-godot.sh` |
| .NET TFM | `src/STS2Mobile/STS2Mobile.csproj` (`<TargetFramework>`) | `scripts/doctor.sh` (parsed at runtime) |
| Min/target SDK, build tools, Kotlin, AGP | `android/config.gradle` | gradle build |
| App version | `android/gradle.properties` (`export_version_*`) | bumped automatically by `scripts/build.sh` (use `--no-bump` to skip) |

If you change any version above, no other file should need to change.

## Code style

C# is auto-formatted with [`csharpier`](https://csharpier.com/). Install once with:

```bash
dotnet tool install -g csharpier
```

`scripts/build.sh` runs it as the first step; CI verifies via `csharpier --check`. Run it manually with:

```bash
csharpier format src/STS2Mobile
```

Shell scripts should pass `shellcheck`. CI runs it on `scripts/*.sh` and `src/stubs/*.sh`.

## Tests

Pure-C# logic lives in `src/STS2Mobile.Tests/` (xunit). The test project uses `<Compile Include>` to link specific sources from `src/STS2Mobile/` rather than taking a `<ProjectReference>`, so it compiles without `sts2.dll`, `GodotSharp.dll`, or `0Harmony.dll`. To cover a new source file:

1. Add `<Compile Include="..\STS2Mobile\<path>\<file>.cs" Link="Linked/<file>.cs" />` in `STS2Mobile.Tests.csproj`.
2. If the production file references sts2/Godot types the test doesn't exercise, either stub them inline (see `PatchHelperStub.cs` for the pattern) or refactor the production file to isolate the testable surface (e.g. `BeaconMessage` was extracted from `LanMultiplayerPatcher.cs`).
3. Run locally with `dotnet test src/STS2Mobile.Tests/STS2Mobile.Tests.csproj`.

CI runs the same command on every PR.

## Pull requests

- Branch off `main`.
- Keep changes focused; one concern per PR.
- Describe the user-visible effect in the PR body.
- CI must be green before review (formatting, shellcheck, unit tests, native stubs build).
- Every push to `main` and every `v*.*.*` tag triggers `apk-build.yml` on the self-hosted runner; the signed APK appears as a run artifact for smoke-checking.
- Tags cut a **draft** GitHub Release via `release.yml` — the maintainer reviews and publishes.

## Releases

Cutting `v0.3.1`:
1. Bump `export_version_name` and `export_version_code` in `android/gradle.properties` on a PR, update `CHANGELOG.md` with a new `## 0.3.1` section, merge.
2. Tag the merge commit: `git tag v0.3.1 && git push origin v0.3.1`.
3. `apk-build.yml` builds and signs the APK on the self-hosted runner; `release.yml` drafts the GitHub Release with the CHANGELOG 0.3.1 section as body and the APK + SHA-256 attached. Both run in parallel; the release workflow polls the APK build's run and attaches once it completes.
4. Open the draft in the Releases tab, review, click **Publish**.

## Infrastructure

- **Self-hosted runner** — setup, artifact layout, signing key management, operational runbook all in [`docs/self-hosted-runner.md`](docs/self-hosted-runner.md). One Linux host; `sts2` label.
- **Renovate** — weekly dependency PRs (Monday mornings UTC). Patch + minor bumps for `xunit*`, `Microsoft.NET.Test.Sdk`, and GitHub Actions auto-merge after CI green. Production .NET deps (`SteamKit2`, `protobuf-net`, etc.) and gradle plugins always go through human review. NDK / SDK / build-tools versions in `android/config.gradle` are Renovate-ignored — bumping them requires a full APK re-verification that Renovate cannot do on its own.

## Reporting issues

Include the doctor output (`bash scripts/doctor.sh`), the failing command and its output, your OS, and the relevant tool versions (`dotnet --version`, `java -version`, NDK version).
