#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_GRADLE="$ROOT/android/config.gradle"

# Single source of truth: read NDK version from android/config.gradle
if [ ! -f "$CONFIG_GRADLE" ]; then
    echo "ERROR: cannot find $CONFIG_GRADLE" >&2
    exit 1
fi
NDK_VERSION=$(grep -oE "ndkVersion[[:space:]]*:[[:space:]]*'[0-9.]+'" "$CONFIG_GRADLE" \
              | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)
if [ -z "$NDK_VERSION" ]; then
    echo "ERROR: could not parse ndkVersion from $CONFIG_GRADLE" >&2
    exit 1
fi

ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
NDK="${ANDROID_NDK_ROOT:-$ANDROID_SDK/ndk/$NDK_VERSION}"

case "$(uname -s)" in
    Linux)   HOST_TAG="linux-x86_64" ;;
    Darwin)  HOST_TAG="darwin-x86_64" ;;
    MINGW*|MSYS*|CYGWIN*) HOST_TAG="windows-x86_64" ;;
    *)       HOST_TAG="$(uname -s | tr '[:upper:]' '[:lower:]')-x86_64" ;;
esac

CC="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin/aarch64-linux-android24-clang"
if [ ! -x "$CC" ]; then
    echo "ERROR: NDK compiler not found at $CC" >&2
    echo "       Install NDK $NDK_VERSION: sdkmanager 'ndk;$NDK_VERSION'" >&2
    exit 1
fi

cd "$SCRIPT_DIR"
OUT=out/arm64-v8a
mkdir -p "$OUT"

"$CC" -shared -o "$OUT/libsteam_api.so" steam_stub.c steam_stub_auto.c -Wl,-soname,libsteam_api.so
"$CC" -shared -o "$OUT/libsentry.so" sentry_stub.c

ls -lh "$OUT/"
