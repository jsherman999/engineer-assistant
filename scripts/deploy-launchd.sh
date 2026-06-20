#!/bin/zsh
# Build the latest dev (debug) build and push it to the launchd-run location, then
# restart the launchd agent so it runs the freshly built binary.
#
#   ./scripts/deploy-launchd.sh
#
set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.jsherman.engineerassistant"
BIN="$HOME/Library/Application Support/EngineerAssistant/bin/EngineerAssistant"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"

cd "$REPO"

echo "==> Building latest dev build (debug)…"
swift build

echo "==> Stopping running launchd instance…"
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
# Wait for the process to release the binary so we can overwrite it.
for i in {1..10}; do
  pgrep -f "$BIN" >/dev/null || break
  sleep 0.3
done

echo "==> Pushing binary to launchd location: $BIN"
mkdir -p "$(dirname "$BIN")"
cp "$REPO/.build/debug/EngineerAssistant" "$BIN"
chmod +x "$BIN"

echo "==> Restarting launchd agent…"
launchctl bootstrap "gui/$UID_NUM" "$PLIST"
sleep 2

if launchctl list | grep -q "$LABEL"; then
  PID="$(pgrep -f "$BIN" || true)"
  echo "==> Deployed ✓  launchd agent running pid ${PID:-?} from latest dev build"
else
  echo "==> WARNING: agent not listed after bootstrap" >&2
  exit 1
fi
