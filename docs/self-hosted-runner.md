# Self-hosted GitHub Actions runner for APK builds

Full APK assembly cannot run on GitHub-hosted runners because `sts2.dll`, the custom Godot fork, and FMOD are not redistributable. This document describes provisioning a single self-hosted Linux (Ubuntu/Debian) runner that handles the APK build and signing on your own hardware, without publishing any proprietary artifact.

The runner exposes a single label — `sts2` — that the workflows in this repository target via `runs-on: [self-hosted, linux, sts2]`.

## Host requirements

- Ubuntu 22.04+ or Debian 12+ (64-bit x86_64).
- 20 GB free disk; 4 GB RAM minimum (8 GB recommended for concurrent Gradle runs).
- Outbound HTTPS to `github.com`, `api.github.com`, `objects.githubusercontent.com` (runner handshake + artifact upload).
- A machine you trust: the runner executes workflow code, which effectively means anyone who can push to `main` can run arbitrary commands on it. For a single-maintainer repo this is acceptable; for a multi-contributor repo require branch protection + review on the workflows that target this runner.

## One-time setup

### 1. Create a dedicated user

```bash
sudo useradd -m -s /bin/bash gha-runner
sudo -u gha-runner mkdir -p /home/gha-runner/runner
```

No `sudo`, no `docker` group, no shell for any other workload. The runner user owns only its own home directory and `/opt/sts2/` (below).

### 2. Install system toolchain

```bash
sudo apt update
sudo apt install -y \
  openjdk-17-jdk \
  python3 python3-pip \
  zip unzip \
  shellcheck \
  git curl wget
```

Install .NET 9 SDK via Microsoft's apt repo or the `dotnet-install.sh` script as the `gha-runner` user:

```bash
sudo -u gha-runner bash -c '
  cd ~
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh
  chmod +x dotnet-install.sh
  ./dotnet-install.sh --channel 9.0
  echo "export PATH=\$HOME/.dotnet:\$HOME/.dotnet/tools:\$PATH" >> ~/.bashrc
'
sudo -u gha-runner bash -lc 'dotnet tool install -g csharpier'
```

Android SDK + command-line tools: download `commandlinetools-linux-*.zip` from https://developer.android.com/studio#command-tools, unzip to `/home/gha-runner/Android/Sdk/cmdline-tools/latest/`. Then:

```bash
sudo -u gha-runner bash -lc '
  export ANDROID_HOME=$HOME/Android/Sdk
  export PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$PATH
  yes | sdkmanager --licenses
  NDK=$(grep -oE "ndkVersion[[:space:]]*:[[:space:]]*.[0-9.]+." /opt/sts2/repo-config/config.gradle | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")
  sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" "ndk;$NDK"
  echo "export ANDROID_HOME=\$HOME/Android/Sdk" >> ~/.bashrc
'
```

### 3. Place proprietary artifacts

Create `/opt/sts2/` owned by the runner user, then populate it:

```bash
sudo mkdir -p /opt/sts2
sudo chown gha-runner:gha-runner /opt/sts2
sudo -u gha-runner mkdir -p \
  /opt/sts2/upstream/godot-export/.godot/mono/publish/arm64 \
  /opt/sts2/vendor/godot \
  /opt/sts2/vendor/fmod-sdk \
  /opt/sts2/android/libs/release/arm64-v8a \
  /opt/sts2/keystore
```

Copy artifacts in as the runner user (never leave them root-owned):

| Path | Source | Permissions |
| --- | --- | --- |
| `/opt/sts2/upstream/godot-export/.godot/mono/publish/arm64/sts2.dll` | Desktop game export | 640 |
| `...GodotSharp.dll`, `...0Harmony.dll` | Same export | 640 |
| `/opt/sts2/vendor/godot/` | Custom Godot 4.5.1 fork source tree | 755 / 644 |
| `/opt/sts2/vendor/fmod-sdk/` | FMOD Engine unzipped | 755 / 644 |
| `/opt/sts2/android/libs/release/arm64-v8a/libgodot_android.so` | Build of `vendor/godot` via `scripts/build-godot.sh` | 644 |
| `/opt/sts2/android/libs/release/godot-lib.template_release.aar` | Same build | 644 |
| `/opt/sts2/keystore/sts2.keystore` | Your release signing keystore | **600** |

Double-check the keystore:

```bash
sudo chmod 600 /opt/sts2/keystore/sts2.keystore
sudo chown gha-runner:gha-runner /opt/sts2/keystore/sts2.keystore
```

### 4. Install the GitHub Actions runner

From the repo's `Settings → Actions → Runners → New self-hosted runner` page, copy the download URL and token. Then as `gha-runner`:

```bash
sudo -u gha-runner bash -lc '
  cd ~/runner
  curl -O -L "<url from GitHub>"
  tar xzf actions-runner-linux-x64-*.tar.gz
  ./config.sh \
    --url https://github.com/<owner>/<repo> \
    --token <token from GitHub> \
    --name "sts2-builder-$(hostname)" \
    --labels self-hosted,linux,x64,sts2 \
    --work _work \
    --unattended
'
```

### 5. Install as a systemd service

```bash
cd /home/gha-runner/runner
sudo ./svc.sh install gha-runner
sudo ./svc.sh start
sudo ./svc.sh status
```

Service logs: `journalctl -u actions.runner.<owner>-<repo>.sts2-builder-*.service -f`.

### 6. Set required repository secrets

In `Settings → Secrets and variables → Actions → New repository secret`:

| Secret | Value |
| --- | --- |
| `SIGNING_KEYSTORE_PASSWORD` | The password for `/opt/sts2/keystore/sts2.keystore` |
| `SIGNING_KEYSTORE_ALIAS` | The signing alias inside that keystore (e.g. `sts2`) |

The keystore file itself is not a secret; it stays on the runner's disk and never leaves the machine.

## How the workflows use the runner

- `.github/workflows/apk-build.yml` targets `runs-on: [self-hosted, linux, sts2]`, symlinks `/opt/sts2/upstream`, `/opt/sts2/vendor`, and `/opt/sts2/android/libs/release` into the workspace checkout, writes a scoped `gradle.properties` with the signing secrets into the job's home, runs `scripts/doctor.sh` then `scripts/build.sh --no-bump`, uploads the APK and its SHA-256 as artifacts, and cleans up the scoped gradle.properties on exit.
- Triggers: every push to `main`, every tag `v*.*.*`, and `workflow_dispatch` for manual smoke tests.
- Concurrency is gated per-ref so back-to-back commits cancel the earlier build.
- `.github/workflows/release.yml` runs on a hosted runner for the draft step, then depends on the `apk-build.yml` run for the same tag to finish before attaching the APK and checksum.

## Operations

### Pausing builds

Stop the service:

```bash
sudo /home/gha-runner/runner/svc.sh stop
```

Starting back up: `svc.sh start`. Queued workflow runs resume automatically.

### Working directory corruption

If a build leaves the workspace in a weird state:

```bash
sudo systemctl stop actions.runner.*.service
sudo -u gha-runner rm -rf /home/gha-runner/runner/_work
sudo systemctl start actions.runner.*.service
```

The next build re-checks out from scratch.

### Rotating the signing password

1. Update the password with `keytool -storepasswd -keystore /opt/sts2/keystore/sts2.keystore`.
2. Update the `SIGNING_KEYSTORE_PASSWORD` secret in GitHub.
3. The next workflow run uses the new value; no runner restart needed.

### Rotating the signing keystore itself

If you need to replace the file (new cert, compromise, etc.):

1. Place the new `.keystore` at `/opt/sts2/keystore/sts2.keystore.new`, chmod 600, chown `gha-runner`.
2. Stop the runner service.
3. Move the old aside, rename `.new` to the live path.
4. Update the GHA secrets if the password or alias changed.
5. Start the runner.

**Warning:** signing a release with a different keystore than previously-published APKs means existing installs cannot upgrade (Android refuses). Only rotate if you are ready to break that install chain.

### Updating the runner binary

GitHub deprecates runner versions every ~90 days. When the runner self-updates fails or when you see a deprecation banner:

```bash
sudo /home/gha-runner/runner/svc.sh stop
sudo -u gha-runner bash -lc '
  cd ~/runner
  # Optional: back up _diag/ if you want the logs
  curl -O -L "<new runner tarball URL from GitHub>"
  tar xzf actions-runner-linux-x64-*.tar.gz --overwrite
'
sudo /home/gha-runner/runner/svc.sh start
```

### Security hygiene

- Keep the runner user isolated: no sudoers entries, no shared Docker daemon, no shared secrets on disk beyond `/opt/sts2/keystore/`.
- Enable unattended upgrades for security patches: `sudo dpkg-reconfigure -plow unattended-upgrades`.
- Review `Settings → Actions → General → Fork pull request workflows from outside collaborators` and require approval before running workflows from forks.
- Audit the runner log periodically: `journalctl -u actions.runner.*.service --since yesterday`.

## Decommissioning

```bash
sudo /home/gha-runner/runner/svc.sh stop
sudo /home/gha-runner/runner/svc.sh uninstall
sudo -u gha-runner /home/gha-runner/runner/config.sh remove --token <removal token from GitHub>
sudo userdel -r gha-runner
sudo rm -rf /opt/sts2
```

Also remove the runner entry from `Settings → Actions → Runners` in the GitHub UI.
