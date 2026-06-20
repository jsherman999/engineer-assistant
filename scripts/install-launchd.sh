#!/bin/zsh
# Push the already-built dev binary (.build/debug) into the launchd bin/ location and
# restart the agent. Run manually, or invoked automatically by the autodeploy WatchPaths
# agent (com.jsherman.engineerassistant.autodeploy) whenever a build changes the binary.
set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.jsherman.engineerassistant"
SRC="$REPO/.build/debug/EngineerAssistant"
BIN="$HOME/Library/Application Support/EngineerAssistant/bin/EngineerAssistant"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"

[ -f "$SRC" ] || { echo "$(date '+%H:%M:%S') no build artifact at $SRC; skipping"; exit 0; }

# Let the build finish writing/linking before we read the artifact.
sleep 1

# Skip if bin/ already matches — dedupes redundant watch events and avoids needless restarts.
if cmp -s "$SRC" "$BIN"; then
  echo "$(date '+%H:%M:%S') bin/ already up to date; nothing to push"
  exit 0
fi

echo "$(date '+%H:%M:%S') pushing latest dev build -> launchd bin/"
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
for i in {1..10}; do pgrep -f "$BIN" >/dev/null || break; sleep 0.3; done
mkdir -p "$(dirname "$BIN")"
cp "$SRC" "$BIN"
chmod +x "$BIN"
launchctl bootstrap "gui/$UID_NUM" "$PLIST"
echo "$(date '+%H:%M:%S') deployed ✓ (pid $(pgrep -f "$BIN" || echo '?'))"
