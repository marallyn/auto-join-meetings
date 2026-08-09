#!/bin/bash

# Remove the auto-join-meetings LaunchAgents. Leaves ~/Library/Logs/auto-join-meetings
# alone so any crontab backup and past output survive.

set -euo pipefail

LABELS=(com.auto-join-meetings.fetch com.auto-join-meetings.join)
AGENTS_DIR="$HOME/Library/LaunchAgents"

for label in "${LABELS[@]}"; do
    # Non-zero here just means the job wasn't loaded, which is fine when
    # uninstalling a partial install.
    launchctl bootout "gui/$UID/$label" 2>/dev/null || true
    rm -f "$AGENTS_DIR/$label.plist"
    echo "removed $label"
done

echo
echo "logs kept at $HOME/Library/Logs/auto-join-meetings"
