#!/usr/bin/env bash
# Gets the Android toolchain into a usable state before a build or run.
#
#  - Stops Gradle daemons left behind by an interrupted build, which otherwise
#    hold the file-hash lock and fail the next build with "already locked".
#  - Checks the emulator answers adb within a few seconds; if it is hung,
#    kills it and cold-boots it again, then waits until boot completes.
#
# Usage: tool/android_ready.sh [avd_name]   (default: Medium_Phone)

set -u
AVD="${1:-Medium_Phone}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Runs a command, giving up after $1 seconds. macOS has no `timeout`.
with_timeout() {
  local secs=$1; shift
  "$@" & local pid=$!
  ( sleep "$secs"; kill "$pid" 2>/dev/null ) & local watcher=$!
  wait "$pid" 2>/dev/null; local code=$?
  kill "$watcher" 2>/dev/null
  return $code
}

echo "• Stopping stale Gradle daemons"
(cd "$ROOT/android" && ./gradlew --stop >/dev/null 2>&1)
pkill -f GradleDaemon 2>/dev/null

serial=$(adb devices | awk '/^emulator-[0-9]+\tdevice/{print $1; exit}')
if [ -n "$serial" ]; then
  if [ "$(with_timeout 8 adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
    echo "• Emulator $serial is responsive"
    exit 0
  fi
  echo "• Emulator $serial is not responding; restarting it"
  with_timeout 10 adb -s "$serial" emu kill >/dev/null 2>&1
  pkill -f "qemu-system.*$AVD" 2>/dev/null
  sleep 3
fi

echo "• Booting $AVD (cold boot)"
nohup "${ANDROID_HOME:-$HOME/Library/Android/sdk}/emulator/emulator" \
  -avd "$AVD" -no-snapshot-load >/dev/null 2>&1 &

for _ in $(seq 1 150); do
  serial=$(adb devices | awk '/^emulator-[0-9]+\tdevice/{print $1; exit}')
  if [ -n "$serial" ] && \
     [ "$(with_timeout 5 adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
    echo "• Emulator $serial booted"
    exit 0
  fi
  sleep 2
done

echo "✗ Emulator did not boot within 5 minutes" >&2
exit 1
