#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_DIR="$ROOT/vendor/godot"
ANDROID_LIBS="$ROOT/android/libs/release"

if [ ! -d "$GODOT_DIR" ]; then
    echo "ERROR: $GODOT_DIR missing. Clone the project's Godot 4.5.1 fork there first." >&2
    exit 1
fi

export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
if [ -z "${ANDROID_NDK_ROOT:-}" ]; then
    if [ ! -d "$ANDROID_HOME/ndk" ]; then
        echo "ERROR: no NDKs installed at $ANDROID_HOME/ndk (set ANDROID_NDK_ROOT to override)" >&2
        exit 1
    fi
    # NDK version directories are semver-clean; ls is fine here.
    # shellcheck disable=SC2012
    LATEST_NDK=$(ls -1 "$ANDROID_HOME/ndk" | sort -V | tail -1)
    export ANDROID_NDK_ROOT="$ANDROID_HOME/ndk/$LATEST_NDK"
fi

# Optional Python venv for SCons; skip silently if absent and rely on system scons.
if [ -f "$ROOT/venv/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "$ROOT/venv/bin/activate"
fi

if ! command -v scons >/dev/null 2>&1; then
    echo "ERROR: scons not on PATH. Install via 'pip3 install scons' or create a venv at $ROOT/venv." >&2
    exit 1
fi

# Build Godot for Android arm64
echo "Building Godot (android arm64 template_release)..."
cd "$GODOT_DIR"
scons platform=android arch=arm64 target=template_release module_mono_enabled=yes -j"$(nproc)"

BUILT_SO="$GODOT_DIR/platform/android/java/lib/libs/release/arm64-v8a/libgodot_android.so"
if [ ! -f "$BUILT_SO" ]; then
    echo "ERROR: Expected output not found at $BUILT_SO" >&2
    exit 1
fi

# Update the .so inside the AAR
echo "Updating libgodot_android.so in AAR..."
AAR="$ANDROID_LIBS/godot-lib.template_release.aar"
if [ ! -f "$AAR" ]; then
    echo "ERROR: $AAR missing (expected upstream Godot AAR to patch into)" >&2
    exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
mkdir -p "$TMPDIR/jni/arm64-v8a"
cp "$BUILT_SO" "$TMPDIR/jni/arm64-v8a/libgodot_android.so"
(cd "$TMPDIR" && zip -u "$AAR" jni/arm64-v8a/libgodot_android.so)

mkdir -p "$ANDROID_LIBS/arm64-v8a"
cp "$BUILT_SO" "$ANDROID_LIBS/arm64-v8a/libgodot_android.so"

echo "Godot engine rebuild complete!"
