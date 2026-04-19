# Security policy

This is an unofficial community launcher. Security issues are taken seriously even though the project is small. Thank you for taking the time to report them.

## Reporting a vulnerability

Please do **not** open a public GitHub issue. Report privately via one of:

- GitHub's private vulnerability disclosure for this repository ("Security" tab → "Report a vulnerability").
- Email the maintainer listed in `README.md` / commit history.

Include:

- A short description of the issue and its impact.
- Repro steps, affected file paths and line numbers, or a minimal PoC.
- App version (`android/gradle.properties` → `export_version_name`) and device details if relevant.

You can expect an acknowledgement within 7 days and a first-response triage within 14 days. Once a fix is ready, we'll coordinate disclosure timing with you.

## Scope

In scope:

- The mobile launcher itself (`src/STS2Mobile/`, `android/`).
- The Harmony patches that ship with the launcher (`src/STS2Mobile/Patches/`).
- The build scripts that ship artifacts (`scripts/`, `src/stubs/`).
- Stored credentials (Steam refresh tokens, Android Keystore usage).
- LAN multiplayer beacon and join behavior added by this project.

Out of scope (please report upstream where applicable):

- Vulnerabilities in the desktop game binary (`sts2.dll`) or its original Godot runtime — report to Mega Crit.
- Vulnerabilities in SteamKit2, Godot, FMOD, Spine, or other upstream dependencies — report to those projects.
- Issues that require physical access to an unlocked, already-compromised device.
- Denial of LAN multiplayer by a peer on the same Wi-Fi (the feature has no authentication today; see the "Known limitations" section below).

## Known limitations

These are documented gaps rather than undisclosed vulnerabilities. Fixes are tracked in the issue tracker.

- **LAN multiplayer is unauthenticated.** Any peer on the same network can impersonate a host beacon. A mitigation (signed beacons with a shared secret) is planned.
- **Android Keystore hardware backing is best-effort.** The launcher requests StrongBox but falls back to the default TEE and then to software storage depending on device capabilities. A warning is surfaced to the log when hardware backing is unavailable.
- **`MANAGE_EXTERNAL_STORAGE` is requested** so that save backups, mods, and diagnostic exports can live in a user-visible folder. We have no plans to scope this down unless Android adds an equivalent user-visible scoped directory.

## Credits

Reports received under this policy will be credited in the release notes at the reporter's discretion.
