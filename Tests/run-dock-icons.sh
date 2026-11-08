#!/bin/sh
# Memory defaults and a fake Dock tile; no app, real Dock changes, or visible windows.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
exec python3 "$root/Tests/run-settings-panes.py" "$@"
