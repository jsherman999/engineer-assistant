#!/bin/zsh
# Restart the launchd-managed EngineerAssistant app (no rebuild).
# `kickstart -k` kills any running instance and starts a fresh one, so this works
# whether the app is open or you've quit it. To restart WITH a rebuild, use
# ./scripts/deploy-launchd.sh instead.
#
#   ./scripts/restart-app.sh
#
set -e

LABEL="com.jsherman.engineerassistant"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN="$HOME/Library/Application Support/EngineerAssistant/bin/EngineerAssistant"
UID_NUM="$(id -u)"

# If the agent isn't loaded (e.g. after a fresh checkout or a bootout), load it first.
if ! launchctl print "gui/$UID_NUM/$LABEL" >/dev/null 2>&1; then
  echo "Agent not loaded — bootstrapping it…"
  launchctl bootstrap "gui/$UID_NUM" "$PLIST"
fi

echo "Restarting $LABEL…"
launchctl kickstart -k "gui/$UID_NUM/$LABEL"

# Confirm it came up.
for i in {1..10}; do
  PID="$(pgrep -f "$BIN" || true)"
  [ -n "$PID" ] && break
  sleep 0.3
done

if [ -n "$PID" ]; then
  echo "Running ✓ (pid $PID)"
else
  echo "WARNING: app did not start; check /tmp/engineerassistant.err.log" >&2
  exit 1
fi
