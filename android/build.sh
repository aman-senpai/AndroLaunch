#!/usr/bin/env bash
#
# Builds the AndroLaunch Comp companion APK.
#
# The UI is Jetpack Compose + Material 3, so the canonical build is Gradle:
# this script is a thin wrapper that sets up the local Gradle home (the daemon
# and dependency cache must stay inside the repo because the build runs sandboxed),
# assembles the debug APK, signs it with the long-standing debug keystore, and
# copies it to the path the macOS app bundles.
#
# Requirements: a JDK 17+ (Android Studio's JBR is auto-detected), Android SDK
# platform 34 + build-tools 34.0.0 (see README), and network access on the first
# build while Gradle downloads the Android Gradle Plugin, Kotlin and Compose.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"

if [[ -z "${JAVA_HOME:-}" && -d "/Applications/Android Studio.app/Contents/jbr/Contents/Home" ]]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi
# Sandbox-safe Gradle home: keep the daemon, wrapper and dependency cache local.
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$REPO/.gradle}"

cd "$ROOT"
./gradlew --console=plain :app:assembleDebug "$@"

APK="$ROOT/app/build/outputs/apk/debug/app-debug.apk"
[[ -f "$APK" ]] || { echo "missing build output: $APK" >&2; exit 1; }
cp "$APK" "$ROOT/AndroLaunchCompanion.apk"

echo "built: $ROOT/AndroLaunchCompanion.apk ($(du -h "$ROOT/AndroLaunchCompanion.apk" | cut -f1))"
