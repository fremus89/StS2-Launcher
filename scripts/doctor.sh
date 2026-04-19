#!/usr/bin/env bash
# Preflight check for the StS2-Launcher build environment.
#
# Runs to completion even when individual checks fail, prints a checklist
# with remediation hints, and exits non-zero if any critical item is missing.
#
# Side effects: exports resolved paths so scripts/build.sh can reuse them:
#   NDK_VERSION, NDK_ROOT, NDK_CC_PREFIX, NDK_HOST_TAG
#   CRYPTO_SO_PATH
#   CSHARPIER_BIN

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_DIR="$ROOT/android"
CONFIG_GRADLE="$ANDROID_DIR/config.gradle"
CSPROJ="$ROOT/src/STS2Mobile/STS2Mobile.csproj"

FAILED=0
WARNINGS=0
PASSED=0

_pass() {
    printf '  [ OK ]  %s\n' "$1"
    PASSED=$((PASSED + 1))
}

_fail() {
    printf '  [FAIL]  %s\n' "$1"
    if [ -n "${2:-}" ]; then
        printf '          -> %s\n' "$2"
    fi
    FAILED=$((FAILED + 1))
}

_warn() {
    printf '  [WARN]  %s\n' "$1"
    if [ -n "${2:-}" ]; then
        printf '          -> %s\n' "$2"
    fi
    WARNINGS=$((WARNINGS + 1))
}

_section() {
    printf '\n== %s ==\n' "$1"
}

echo "StS2-Launcher build doctor"
echo "root: $ROOT"

# ---------------------------------------------------------------------------
# Host toolchain
# ---------------------------------------------------------------------------
_section "Host toolchain"

if command -v dotnet >/dev/null 2>&1; then
    DOTNET_VER=$(dotnet --version 2>/dev/null || echo "unknown")
    case "$DOTNET_VER" in
        9.*) _pass ".NET SDK $DOTNET_VER" ;;
        *)   _fail ".NET SDK $DOTNET_VER (need 9.x)" "install .NET 9 SDK from https://dotnet.microsoft.com/download" ;;
    esac
else
    _fail ".NET SDK not found on PATH" "install .NET 9 SDK from https://dotnet.microsoft.com/download"
fi

if command -v csharpier >/dev/null 2>&1; then
    export CSHARPIER_BIN="$(command -v csharpier)"
    _pass "csharpier ($CSHARPIER_BIN)"
elif [ -x "$HOME/.dotnet/tools/csharpier" ]; then
    export CSHARPIER_BIN="$HOME/.dotnet/tools/csharpier"
    _pass "csharpier ($CSHARPIER_BIN)"
else
    _fail "csharpier not found" "run: dotnet tool install -g csharpier"
fi

for tool in python3 java zip unzip; do
    if command -v "$tool" >/dev/null 2>&1; then
        _pass "$tool"
    else
        _fail "$tool not found on PATH" "install $tool via your package manager"
    fi
done

if command -v java >/dev/null 2>&1; then
    JAVA_MAJOR=$(java -version 2>&1 | awk -F'[".]' '/version/ {print $2; exit}')
    if [ "${JAVA_MAJOR:-0}" -ge 17 ] 2>/dev/null; then
        _pass "java major version $JAVA_MAJOR (>= 17)"
    else
        _warn "java major version ${JAVA_MAJOR:-unknown} (gradle config requires 17)" "install JDK 17 (Temurin, Zulu, or Oracle)"
    fi
fi

if command -v scons >/dev/null 2>&1; then
    _pass "scons ($(scons --version 2>/dev/null | awk '/engine:/ {print $3; exit}'))"
else
    _warn "scons not found (only needed for scripts/build-godot.sh)" "pip3 install scons  (or use a venv at $ROOT/venv)"
fi

# ---------------------------------------------------------------------------
# Android SDK & NDK
# ---------------------------------------------------------------------------
_section "Android SDK & NDK"

ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
if [ -d "$ANDROID_SDK" ]; then
    _pass "Android SDK at $ANDROID_SDK"
    export ANDROID_HOME="$ANDROID_SDK"
else
    _fail "Android SDK not found (checked ANDROID_HOME, ANDROID_SDK_ROOT, $HOME/Android/Sdk)" \
          "install Android Studio or command-line tools, set ANDROID_HOME"
fi

if [ -f "$CONFIG_GRADLE" ]; then
    NDK_VERSION=$(grep -oE "ndkVersion[[:space:]]*:[[:space:]]*'[0-9.]+'" "$CONFIG_GRADLE" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)
    if [ -n "$NDK_VERSION" ]; then
        export NDK_VERSION
        _pass "NDK version pinned to $NDK_VERSION (from android/config.gradle)"
    else
        _fail "could not parse ndkVersion from android/config.gradle" "check file is not corrupted"
        NDK_VERSION=""
    fi
else
    _fail "android/config.gradle missing" "repo is incomplete - re-clone"
    NDK_VERSION=""
fi

if [ -n "$NDK_VERSION" ] && [ -d "$ANDROID_SDK/ndk/$NDK_VERSION" ]; then
    export NDK_ROOT="$ANDROID_SDK/ndk/$NDK_VERSION"
    _pass "NDK $NDK_VERSION installed at $NDK_ROOT"

    HOST_OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$HOST_OS" in
        linux)  NDK_HOST_TAG="linux-x86_64" ;;
        darwin) NDK_HOST_TAG="darwin-x86_64" ;;
        msys*|mingw*|cygwin*) NDK_HOST_TAG="windows-x86_64" ;;
        *)      NDK_HOST_TAG="$HOST_OS-x86_64" ;;
    esac
    export NDK_HOST_TAG
    export NDK_CC_PREFIX="$NDK_ROOT/toolchains/llvm/prebuilt/$NDK_HOST_TAG/bin"
    if [ -d "$NDK_CC_PREFIX" ]; then
        _pass "NDK toolchain for host $NDK_HOST_TAG"
    else
        _fail "NDK toolchain missing at $NDK_CC_PREFIX" "re-install NDK $NDK_VERSION or check host tag"
    fi
elif [ -n "$NDK_VERSION" ]; then
    _fail "NDK $NDK_VERSION not installed" \
          "sdkmanager 'ndk;$NDK_VERSION'  (or install via Android Studio SDK Manager)"
fi

# ---------------------------------------------------------------------------
# .NET Android Mono runtime (TLS native lib)
# ---------------------------------------------------------------------------
_section ".NET Android Mono runtime (TLS)"

CRYPTO_SO_PATH=""
NUGET_ROOT=""
if command -v dotnet >/dev/null 2>&1; then
    NUGET_ROOT=$(dotnet nuget locals global-packages --list 2>/dev/null | awk -F': ' '{print $2; exit}')
fi
if [ -z "$NUGET_ROOT" ]; then
    NUGET_ROOT="$HOME/.nuget/packages"
fi

MONO_PKG_DIR="$NUGET_ROOT/microsoft.netcore.app.runtime.mono.android-arm64"
if [ -d "$MONO_PKG_DIR" ]; then
    LATEST_MONO=$(ls -1 "$MONO_PKG_DIR" 2>/dev/null | sort -V | tail -1)
    if [ -n "$LATEST_MONO" ]; then
        CANDIDATE="$MONO_PKG_DIR/$LATEST_MONO/runtimes/android-arm64/native/libSystem.Security.Cryptography.Native.Android.so"
        if [ -f "$CANDIDATE" ]; then
            export CRYPTO_SO_PATH="$CANDIDATE"
            _pass "libSystem.Security.Cryptography.Native.Android.so ($LATEST_MONO)"
        else
            _fail "Mono Android package $LATEST_MONO present but native .so missing" \
                  "delete $MONO_PKG_DIR/$LATEST_MONO and re-run 'dotnet publish' in src/STS2Mobile"
        fi
    else
        _fail "$MONO_PKG_DIR exists but has no versions" "run 'dotnet publish' in src/STS2Mobile"
    fi
else
    _fail "microsoft.netcore.app.runtime.mono.android-arm64 package not in NuGet cache" \
          "run 'dotnet publish -c Release' in src/STS2Mobile to restore it"
fi

# ---------------------------------------------------------------------------
# External artifacts (not redistributable, must be sourced manually)
# ---------------------------------------------------------------------------
_section "External artifacts"

GODOT_EXPORT="$ROOT/upstream/godot-export/.godot/mono/publish/arm64"
for dll in sts2.dll GodotSharp.dll 0Harmony.dll; do
    if [ -f "$GODOT_EXPORT/$dll" ]; then
        _pass "upstream/godot-export/.../$dll"
    else
        _fail "missing $GODOT_EXPORT/$dll" \
              "export the desktop game to upstream/godot-export/ (needs the desktop .godot/mono/publish/arm64/ folder)"
    fi
done

if [ -d "$ROOT/vendor/godot" ]; then
    _pass "vendor/godot/ (custom Godot 4.5.1 source)"
else
    _warn "vendor/godot/ missing (only needed for scripts/build-godot.sh)" \
          "clone the project's Godot 4.5.1 fork into vendor/godot/"
fi

if [ -d "$ROOT/vendor/fmod-sdk" ]; then
    _pass "vendor/fmod-sdk/"
else
    _fail "vendor/fmod-sdk/ missing" \
          "download FMOD Engine from https://www.fmod.com/download and extract to vendor/fmod-sdk/"
fi

GODOT_AAR="$ANDROID_DIR/libs/release/godot-lib.template_release.aar"
GODOT_SO="$ANDROID_DIR/libs/release/arm64-v8a/libgodot_android.so"
if [ -f "$GODOT_AAR" ] && [ -f "$GODOT_SO" ]; then
    _pass "Godot Android libs in android/libs/release/"
else
    _fail "Godot Android libs missing (libgodot_android.so + godot-lib.template_release.aar)" \
          "run bash scripts/build-godot.sh after vendor/godot/ is populated"
fi

# ---------------------------------------------------------------------------
# Signing
# ---------------------------------------------------------------------------
_section "Release signing"

if [ -f "$ANDROID_DIR/sts2.keystore" ]; then
    _pass "android/sts2.keystore"
else
    _fail "android/sts2.keystore missing" \
          "generate one: keytool -genkey -v -keystore android/sts2.keystore -keyalg RSA -keysize 2048 -validity 10000 -alias sts2"
fi

USER_GRADLE_PROPS="$HOME/.gradle/gradle.properties"
HAVE_PASSWORD=0
HAVE_ALIAS=0
if [ -n "${release_keystore_password:-}" ]; then HAVE_PASSWORD=1; fi
if [ -n "${release_keystore_alias:-}" ]; then HAVE_ALIAS=1; fi
if [ -f "$USER_GRADLE_PROPS" ]; then
    grep -q '^release_keystore_password=' "$USER_GRADLE_PROPS" 2>/dev/null && HAVE_PASSWORD=1
    grep -q '^release_keystore_alias=' "$USER_GRADLE_PROPS" 2>/dev/null && HAVE_ALIAS=1
fi
if [ "$HAVE_PASSWORD" -eq 1 ] && [ "$HAVE_ALIAS" -eq 1 ]; then
    _pass "release_keystore_password and release_keystore_alias configured"
else
    _fail "signing credentials not configured" \
          "set release_keystore_password and release_keystore_alias in $USER_GRADLE_PROPS or export as env vars"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
_section "Summary"
if [ "$FAILED" -eq 0 ]; then
    printf "  %d passed, %d warning(s). Ready to build.\n" "$PASSED" "$WARNINGS"
    # shellcheck disable=SC2128
    [ "${BASH_SOURCE:-$0}" = "$0" ] && exit 0
else
    printf "  %d passed, %d failed, %d warning(s). Fix the items above and re-run.\n" \
        "$PASSED" "$FAILED" "$WARNINGS"
    # shellcheck disable=SC2128
    [ "${BASH_SOURCE:-$0}" = "$0" ] && exit 1
fi
