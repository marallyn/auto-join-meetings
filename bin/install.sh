#!/bin/bash

# Install the auto-join-meetings LaunchAgents.
#
# Substitutes the real repo and home paths into the plist templates, writes them
# to ~/Library/LaunchAgents, loads them, and removes the cron entries this
# replaced. Idempotent: re-run it after editing a template.

set -euo pipefail

LABELS=(com.auto-join-meetings.fetch com.auto-join-meetings.join)
AGENTS_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs/auto-join-meetings"

if [[ "$(uname)" != "Darwin" ]]; then
    echo "launchd is macOS-only; this machine is $(uname)." >&2
    exit 1
fi

# Resolve this script's real directory, following symlinks, so install.sh works
# when invoked through a symlink on PATH.
script_path="${BASH_SOURCE[0]}"
while [[ -L "$script_path" ]]; do
    link_dir=$(cd -P "$(dirname "$script_path")" && pwd)
    script_path=$(readlink "$script_path")
    [[ "$script_path" != /* ]] && script_path="$link_dir/$script_path"
done
BIN_DIR=$(cd -P "$(dirname "$script_path")" && pwd)
REPO_DIR=$(dirname "$BIN_DIR")

if [[ ! -x /opt/homebrew/bin/gcalcli ]]; then
    echo "warning: /opt/homebrew/bin/gcalcli not found. The fetch job will fail" >&2
    echo "         until gcalcli is installed and authorized." >&2
fi

mkdir -p "$AGENTS_DIR" "$LOG_DIR"

for label in "${LABELS[@]}"; do
    template="$BIN_DIR/$label.plist"
    installed="$AGENTS_DIR/$label.plist"

    if [[ ! -f "$template" ]]; then
        echo "missing template: $template" >&2
        exit 1
    fi

    sed -e "s|__REPO_DIR__|$REPO_DIR|g" \
        -e "s|__HOME__|$HOME|g" \
        "$template" > "$installed"

    # A malformed plist loads as a silent no-op, so validate before bootstrapping.
    if ! plutil -lint "$installed" >/dev/null; then
        echo "generated plist is invalid: $installed" >&2
        exit 1
    fi

    # bootout exits non-zero with "No such process" when the job isn't loaded,
    # which is the normal case on a first install. Tolerate only that.
    launchctl bootout "gui/$UID/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$UID" "$installed"

    echo "installed $label"
done

# Drop the cron entries this replaced so the jobs can't double-fire. Matches the
# job lines by script name and the comment lines the old README suggested above them.
# grep returns non-zero on no match, which is a normal outcome here, not an error.
if crontab_current=$(crontab -l 2>/dev/null); then
    cron_job_re='auto-join-meeting'
    cron_comment_re='^#.*[Mm]eeting'

    doomed=$(printf '%s\n' "$crontab_current" \
        | grep -e "$cron_job_re" -e "$cron_comment_re" || true)

    echo
    if [[ -n "$doomed" ]]; then
        backup="$LOG_DIR/crontab.backup.txt"
        printf '%s\n' "$crontab_current" > "$backup"

        echo "removing these crontab lines (backup: $backup):"
        printf '%s\n' "$doomed" | sed 's/^/  /'

        printf '%s\n' "$crontab_current" \
            | { grep -v -e "$cron_job_re" -e "$cron_comment_re" || true; } \
            | crontab -
        echo "crontab updated"
    else
        echo "no auto-join-meetings crontab entries found; nothing to remove"
    fi
else
    echo
    echo "no crontab for $USER; nothing to remove"
fi

echo
for label in "${LABELS[@]}"; do
    printf '%s: ' "$label"
    launchctl print "gui/$UID/$label" | awk -F'= ' '/^\tstate = /{print $2}'
done

echo
echo "logs: $LOG_DIR"
echo "force a run: launchctl kickstart -k gui/$UID/${LABELS[0]}"
