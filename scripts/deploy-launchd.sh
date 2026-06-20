#!/bin/zsh
# Build the latest dev (debug) build and push it to the launchd-run location, then restart
# the agent. Manual one-shot; the autodeploy WatchPaths agent does this automatically on
# every build, so you normally only need `swift build`.
#
#   ./scripts/deploy-launchd.sh
#
set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

echo "==> Building latest dev build (debug)…"
swift build

exec "$REPO/scripts/install-launchd.sh"
