#!/usr/bin/env bash
set -euo pipefail

NO_BUMP=false
SKIP_DOCTOR=false
for arg in "$@"; do
    case "$arg" in
        --no-bump)     NO_BUMP=true ;;
        --skip-doctor) SKIP_DOCTOR=true ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCHER_DIR="$ROOT/src/STS2Mobile"
BUILD_DIR="$ROOT/android"
GRADLE_PROPS="$BUILD_DIR/gradle.properties"
APK_DIR="$BUILD_DIR/build/outputs/apk/mono/release"

# 0. Preflight (populates CRYPTO_SO_PATH, CSHARPIER_BIN, NDK_*)
if [ "$SKIP_DOCTOR" = false ]; then
    # shellcheck disable=SC1091
    source "$ROOT/scripts/doctor.sh"
    if [ "${FAILED:-0}" -gt 0 ]; then
        echo "ERROR: preflight failed. Fix items above or re-run with --skip-doctor (not recommended)." >&2
        exit 1
    fi
fi

# 1. Format
echo "Formatting C# code..."
CSHARPIER="${CSHARPIER_BIN:-$(command -v csharpier || echo "$HOME/.dotnet/tools/csharpier")}"
if [ ! -x "$CSHARPIER" ] && ! command -v "$CSHARPIER" >/dev/null 2>&1; then
    echo "ERROR: csharpier not found. Run: dotnet tool install -g csharpier" >&2
    exit 1
fi
"$CSHARPIER" format "$PATCHER_DIR"

# 2. Build patcher
echo "Building patcher..."
cd "$PATCHER_DIR"
dotnet publish -c Release

PUBLISH_DIR="$PATCHER_DIR/bin/Release/net9.0/publish"
BCL_DIR="$BUILD_DIR/assets/dotnet_bcl"
mkdir -p "$BCL_DIR"

copy_or_die() {
    local src="$1"
    local dst="$2"
    local hint="$3"
    if [ ! -f "$src" ]; then
        echo "ERROR: missing $src" >&2
        echo "       $hint" >&2
        exit 1
    fi
    cp "$src" "$dst"
}

for dll in STS2Mobile.dll SteamKit2.dll protobuf-net.dll protobuf-net.Core.dll \
           System.IO.Hashing.dll ZstdSharp.dll; do
    copy_or_die "$PUBLISH_DIR/$dll" "$BCL_DIR/" \
        "re-run 'dotnet publish -c Release' in $PATCHER_DIR"
done

copy_or_die "$ROOT/upstream/godot-export/.godot/mono/publish/arm64/GodotSharp.dll" "$BCL_DIR/" \
    "export the desktop game to upstream/godot-export/"

# TLS native lib for SteamKit2 over HTTPS. Fatal if missing - runtime will
# fail obscurely inside SSL handshake.
mkdir -p "$BUILD_DIR/libs/release/arm64-v8a"
if [ -n "${CRYPTO_SO_PATH:-}" ] && [ -f "$CRYPTO_SO_PATH" ]; then
    cp "$CRYPTO_SO_PATH" "$BUILD_DIR/libs/release/arm64-v8a/"
else
    echo "ERROR: libSystem.Security.Cryptography.Native.Android.so not resolved." >&2
    echo "       Run scripts/doctor.sh to diagnose, or run 'dotnet publish' first." >&2
    exit 1
fi

echo "Copied patcher + dependencies to android assets"

# 3. Bump version (skip with --no-bump)
CURRENT_NAME=$(grep '^export_version_name=' "$GRADLE_PROPS" | cut -d= -f2)
CURRENT_CODE=$(grep '^export_version_code=' "$GRADLE_PROPS" | cut -d= -f2)

if [ "$NO_BUMP" = true ]; then
    NEW_NAME="$CURRENT_NAME"
    NEW_CODE="$CURRENT_CODE"
    echo "Version: $NEW_NAME ($NEW_CODE) (no bump)"
else
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_NAME"
    PATCH=$((PATCH + 1))
    NEW_NAME="$MAJOR.$MINOR.$PATCH"
    NEW_CODE=$((CURRENT_CODE + 1))

    sed -i "s/^export_version_name=.*/export_version_name=$NEW_NAME/" "$GRADLE_PROPS"
    sed -i "s/^export_version_code=.*/export_version_code=$NEW_CODE/" "$GRADLE_PROPS"
    echo "Version: $CURRENT_NAME ($CURRENT_CODE) -> $NEW_NAME ($NEW_CODE)"
fi

# 4. Build APK
echo "Building APK..."
cd "$BUILD_DIR"
./gradlew assembleMonoRelease

echo "Done: $APK_DIR/StS2Launcher-v$NEW_NAME.apk"
