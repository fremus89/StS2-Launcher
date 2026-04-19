# StS2 Launcher

An Android launcher for Slay the Spire 2, built on a custom Godot 4.5.1 engine with .NET/Mono and Harmony runtime patching.

> **Disclaimer**: This is an unofficial community project. Slay the Spire 2 is developed and published by Mega Crit Games. A valid Steam account that owns Slay the Spire 2 is required. Game files are downloaded directly from Steam after authentication. No game assets are included in this repository.

## Features

- **Steam authentication**  
  Login via SteamKit2 with Steam Guard 2FA support.
- **Game file download**  
  Depot download directly from Steam, with update checking.
- **Cloud saves**  
  Full Steam cloud sync via SteamKit2's CCloud API, with timestamp-aware conflict resolution and non-blocking background uploads.
- **Mobile adaptation**  
  Touch input, UI scaling, layout adjustments, and app lifecycle handling via Harmony runtime patches.
- **LAN multiplayer**  
  UDP broadcast discovery and manual IP join.
- **Shader warmup**  
  Vulkan pipeline cache persistence and canvas ubershader support to eliminate first-encounter stutters.
- **Credential security**  
  Steam refresh tokens encrypted at rest via Android Keystore (AES-256-GCM, hardware-backed TEE).

## How It Works

At startup, `STS2Mobile.dll` is loaded via `coreclr_create_delegate` and applies [Harmony](https://github.com/pardeike/Harmony) patches to adapt the desktop game for mobile. The launcher intercepts `GameStartupWrapper()` to present a Steam login screen before the game starts.

- **Launcher-only mode**  
If no game files are present, the app loads a minimal `bootstrap.pck` and shows the launcher UI for Steam login and game download.  
- **Normal mode**  
With game files downloaded, all patches apply against `sts2.dll` and the game runs natively after authentication.

## Engine Patches

Custom patches to the Godot 4.5.1 engine source for Android-specific issues:

- **Vulkan pipeline cache persistence**  
Saves compiled pipelines when the app loses focus, preventing recompilation after Android kills the process.
- **Canvas ubershaders**  
Enable ubershader fallback for 2D rendering, eliminating first-encounter VFX stutters from blocking pipeline compilation.

## Project Structure

```
src/STS2Mobile/
  ModEntry.cs              # Entry point ([UnmanagedCallersOnly] Apply())
  PatchHelper.cs           # Shared patch utility + logging
  Patches/                 # Harmony patches (one file per concern)
  Launcher/                # Programmatic Godot UI (MVC)
  Steam/                   # SteamKit2 login, depot download, cloud saves
android/                   # Godot Android gradle project
  src/.../GodotApp.java    # Activity, assembly setup, Keystore encryption
  assets/bootstrap.pck     # Minimal PCK for launcher-only mode
src/stubs/                 # Native library stubs (Steam API, Sentry)
scripts/                   # Build and tooling scripts
```

## Prerequisites

**This is a WIP.** Some binaries cannot be redistributed and must be sourced manually before the build will succeed. Run `bash scripts/doctor.sh` at any time to see a checklist of what is missing, with a remediation hint per item.

### Host toolchain

- **.NET 9 SDK** (`STS2Mobile.csproj` targets `net9.0`)
- **csharpier** (`dotnet tool install -g csharpier`)
- **JDK 17** (matches `config.gradle` `javaVersion`)
- **Android SDK** with `ANDROID_HOME` set
- **Android NDK** at the exact version pinned in [`android/config.gradle`](android/config.gradle) (`ndkVersion`). Install with `sdkmanager "ndk;<version>"`.
- **Python 3** + **SCons** (only for `scripts/build-godot.sh`; a venv at `./venv` is auto-activated if present)
- **zip / unzip**

### External artifacts (not in this repo)

| Path | Source |
| --- | --- |
| `upstream/godot-export/.godot/mono/publish/arm64/sts2.dll` | Exported from the desktop build of *Slay the Spire 2*. Not redistributable. |
| `upstream/godot-export/.godot/mono/publish/arm64/GodotSharp.dll` | Same export. |
| `upstream/godot-export/.godot/mono/publish/arm64/0Harmony.dll` | The `.NET 9` build of [Harmony](https://github.com/pardeike/Harmony). |
| `vendor/godot/` | The project's custom Godot 4.5.1 fork (source). |
| `vendor/fmod-sdk/` | [FMOD Engine](https://www.fmod.com/download) — requires a free account; commercial license required for revenue. |
| `android/libs/release/arm64-v8a/libgodot_android.so` + `android/libs/release/godot-lib.template_release.aar` | Produced by `scripts/build-godot.sh` once `vendor/godot/` is populated. |
| `android/sts2.keystore` | Your release signing keystore. Generate one with `keytool -genkey -v -keystore android/sts2.keystore -keyalg RSA -keysize 2048 -validity 10000 -alias sts2`. |
| `release_keystore_password` + `release_keystore_alias` | Set in `~/.gradle/gradle.properties` or as environment variables. |

Licensing notes for the items above are in [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md). FMOD and Spine cannot be bundled here.

## Building

```bash
# Verify the environment first (optional; build.sh runs this automatically):
bash scripts/doctor.sh

# Full build:
bash scripts/build.sh            # bumps patch version
bash scripts/build.sh --no-bump  # keep current version
```

This runs the full pipeline:
1. `dotnet publish` the patcher (outputs `STS2Mobile.dll` + SteamKit2 dependencies)
2. Copies published DLLs to `android/assets/dotnet_bcl/`
3. Copies `libSystem.Security.Cryptography.Native.Android.so` to JNI libs (for TLS)
4. Bumps the version in `gradle.properties`
5. Builds the APK via `./gradlew assembleMonoRelease`

Output: `android/build/outputs/apk/mono/release/StS2Launcher-v<version>.apk`

### Installing

```bash
adb install -r android/build/outputs/apk/mono/release/StS2Launcher-v*.apk

# Fresh install (clear saved credentials + cached assemblies)
adb shell pm clear com.game.sts2launcher
```

### Other build tasks

```bash
# Regenerate bootstrap PCK (only if project.godot changes)
python3 scripts/make-bootstrap-pck.py

# Rebuild Godot engine (only if engine source changes)
bash scripts/build-godot.sh

# Rebuild native stubs (requires Android NDK at the version pinned in android/config.gradle)
bash src/stubs/build_stubs.sh
```

### Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `scripts/doctor.sh` flags `.NET SDK not found` | Install .NET 9 SDK from https://dotnet.microsoft.com/download. |
| `csproj` build errors about `sts2`, `GodotSharp`, or `0Harmony` unresolved | `upstream/godot-export/.godot/mono/publish/arm64/` is missing one or more DLLs. See the external artifacts table above. |
| `libSystem.Security.Cryptography.Native.Android.so not resolved` | Run `dotnet publish -c Release` in `src/STS2Mobile` first; the NuGet cache needs the `microsoft.netcore.app.runtime.mono.android-arm64` package. |
| `build_stubs.sh` reports `NDK compiler not found` | Install the exact NDK version pinned in `android/config.gradle` via `sdkmanager "ndk;<version>"`. |
| `build-godot.sh` reports `vendor/godot missing` | The custom Godot 4.5.1 fork is not yet published by upstream; it must be sourced separately. |
| Gradle signing failure on release build | `release_keystore_password` / `release_keystore_alias` not set in `~/.gradle/gradle.properties`, or `android/sts2.keystore` missing. |

## LAN Multiplayer

Both devices must be on the same local network. The mobile app discovers nearby games via UDP broadcast, or you can enter the PC's IP address manually.

On the PC, add `--fastmp` to the Steam launch options:
**Steam > Slay the Spire 2 > Properties > Launch Options** and enter `--fastmp`

This enables the fast multiplayer mode that the mobile client expects.

## Technical Notes

- Native library stubs (`src/stubs/`) provide no-op `.so` files for desktop-only libraries (Steamworks SDK, Sentry) so the linker is satisfied at runtime.
- The bootstrap PCK is a minimal `project.godot` wrapper that enables .NET module initialization without game files.
- The game's Sentry plugin has no `android.arm64` build, so it's disabled via PCK patching and Harmony patches.
- GodotSharp interop is manually bootstrapped in `ModEntry.cs` since the Godot SDK source generators aren't available.

## License

This project is licensed under the [MIT License](LICENSE). See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for third-party dependency licenses.

FMOD requires a commercial license if your project generates revenue. Spine Runtimes require a valid Spine Editor license. See the third-party licenses file for details.
