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

## Pull requests

- Branch off `main`.
- Keep changes focused; one concern per PR.
- Describe the user-visible effect in the PR body.
- CI must be green before review (formatting, shellcheck, native stubs build).
- The full APK build cannot run in CI because it needs proprietary artifacts; verify locally with `bash scripts/build.sh` and mention any APK testing you did.

## Reporting issues

Include the doctor output (`bash scripts/doctor.sh`), the failing command and its output, your OS, and the relevant tool versions (`dotnet --version`, `java -version`, NDK version).
