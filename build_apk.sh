#!/usr/bin/env bash
set -e

echo "=== Listen to Eve: Release APK Build Helper ==="

# 1. Ensure swap space is available if running on memory-constrained VMs (e.g. Codespaces)
SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')
if [ -z "$SWAP_TOTAL" ] || [ "$SWAP_TOTAL" -lt 1024 ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    echo "Configuring 2GB swap space to prevent memory daemon exhaustion..."
    if [ ! -f /swapfile_eve ]; then
      sudo fallocate -l 2G /swapfile_eve 2>/dev/null || sudo dd if=/dev/zero of=/swapfile_eve bs=1M count=2048 2>/dev/null || true
      if [ -f /swapfile_eve ]; then
        sudo chmod 600 /swapfile_eve
        sudo mkswap /swapfile_eve >/dev/null 2>&1 || true
        sudo swapon /swapfile_eve >/dev/null 2>&1 || true
      fi
    else
      sudo swapon /swapfile_eve >/dev/null 2>&1 || true
    fi
  fi
fi

# 2. Reset any stale/invalid flutter jdk-dir setting first
flutter config --jdk-dir="" > /dev/null 2>&1 || true

# 3. Terminate any previous background gradle daemons
pkill -f '.*GradleDaemon.*' > /dev/null 2>&1 || true

# 4. Check for installed JDKs or install OpenJDK 17 if missing
JDK_CANDIDATES=(
  "/usr/lib/jvm/java-17-openjdk-amd64"
  "/usr/lib/jvm/java-17-openjdk-arm64"
  "/usr/lib/jvm/java-17-openjdk"
  "/usr/lib/jvm/java-21-openjdk-amd64"
  "/usr/lib/jvm/java-21-openjdk-arm64"
  "/usr/lib/jvm/java-21-openjdk"
  "/usr/lib/jvm/default-java"
)

FOUND_JDK=""
for path in "${JDK_CANDIDATES[@]}"; do
  if [ -d "$path" ] && [ -x "$path/bin/java" ]; then
    FOUND_JDK="$path"
    break
  fi
done

# If no Java 17/21 found in standard paths, attempt to derive from system java or install
if [ -z "$FOUND_JDK" ]; then
  if command -v apt-get >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
    echo "Installing OpenJDK 17..."
    apt-get update -qq && apt-get install -y -qq openjdk-17-jdk
    FOUND_JDK="/usr/lib/jvm/java-17-openjdk-amd64"
  elif command -v java >/dev/null 2>&1; then
    JAVA_BIN=$(readlink -f "$(which java)")
    DERIVED_DIR=$(dirname "$(dirname "$JAVA_BIN")")
    if [ -d "$DERIVED_DIR" ] && [ -x "$DERIVED_DIR/bin/javac" ]; then
      FOUND_JDK="$DERIVED_DIR"
    fi
  fi
fi

if [ -n "$FOUND_JDK" ] && [ -d "$FOUND_JDK" ]; then
  echo "Setting JAVA_HOME to: $FOUND_JDK"
  export JAVA_HOME="$FOUND_JDK"
  export PATH="$JAVA_HOME/bin:$PATH"
  flutter config --jdk-dir="$FOUND_JDK"
else
  echo "Using system Java without explicit JAVA_HOME"
  unset JAVA_HOME || true
fi

echo "Active Java version:"
java -version 2>&1 | head -n 2

# 5. Navigate to flutter source
cd "$(dirname "$0")"

# 6. Resolve dependencies
echo "Fetching dependencies..."
flutter pub get

# 7. Build release APK with memory safety
echo "Building Release APK..."
export GRADLE_OPTS="-Dorg.gradle.workers.max=2 -Dorg.gradle.jvmargs=\"-Xmx1280m -XX:MaxMetaspaceSize=384m -XX:+UseG1GC\""
flutter build apk --release --no-tree-shake-icons --android-skip-build-dependency-validation || flutter build apk --release --no-tree-shake-icons

echo "=== Build complete! APK output ==="
ls -lh build/app/outputs/flutter-apk/app-release.apk
