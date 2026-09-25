#!/usr/bin/env bash
# =============================================================================
# Listen to Eve - Local Android Debug Build Helper
# =============================================================================
# Usage:
#   ./build_debug_apk.sh [SEARCH_PROXY_ENDPOINT]
#
# Examples:
#   # For Android Emulator with local backend:
#   ./build_debug_apk.sh http://10.0.2.2:3000/api/search
#
#   # For physical device with backend on LAN:
#   ./build_debug_apk.sh http://192.168.1.50:3000/api/search
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PROXY_ENDPOINT="${1:-${SEARCH_PROXY_ENDPOINT:-http://10.0.2.2:3000/api/search}}"

echo "========================================================"
echo "Listen to Eve — Building Local Android Debug APK"
echo "Target Endpoint: $PROXY_ENDPOINT"
echo "========================================================"

if ! command -v flutter &> /dev/null; then
    echo "Error: 'flutter' command not found in PATH."
    echo "Please ensure the Flutter SDK is installed and added to your PATH."
    exit 1
fi

echo "--> Resolving dependencies..."
flutter pub get

echo "--> Running static analysis..."
flutter analyze

echo "--> Running unit tests..."
flutter test

echo "--> Building debug APK with SEARCH_PROXY_ENDPOINT=$PROXY_ENDPOINT..."
flutter build apk --debug --dart-define=SEARCH_PROXY_ENDPOINT="$PROXY_ENDPOINT"

APK_PATH="$SCRIPT_DIR/build/app/outputs/flutter-apk/app-debug.apk"
echo ""
echo "========================================================"
echo "Build succeeded!"
echo "Debug APK location: $APK_PATH"
echo "To install on connected device/emulator:"
echo "  adb install -r $APK_PATH"
echo "========================================================"
