#!/bin/zsh

# Report hours worked, derived from a calendar where every "Out of office"
# event marks NOT-working time. Worked time = window length - OOO time.
#
# Usage:
#   work-hours.sh                 # default: last 7 days (a week) ending now
#   work-hours.sh day             # last 24 hours
#   work-hours.sh week            # last 7 days
#   work-hours.sh month           # back one calendar month (e.g. May 30 -> Apr 30)
#   work-hours.sh --hours 336     # arbitrary N hours back
#   work-hours.sh --days 14       # arbitrary N days back
#   work-hours.sh 2026-05-01 2026-05-08            # explicit date range
#   work-hours.sh "2026-05-01 09:00:00" "2026-05-01 17:00:00"  # explicit datetimes

GCALCLI="/opt/homebrew/bin/gcalcli"
GCALCLI_DIR="$HOME/Library/Application Support/gcalcli"
CALENDAR="jeff.martin@promenade.co"
# ${0:A:h} resolves symlinks to the real script dir, so this works when the
# script is invoked through a symlink on PATH (e.g. ~/.local/bin/work-hours).
PYTHON_MATH="${0:A:h}/work_hours.py"
FMT="%Y-%m-%d %H:%M:%S"

export GCALCLI_CONFIG="$GCALCLI_DIR"

usage() {
    cat <<'EOF'
Report hours worked, derived from a calendar where every "Out of office"
event marks NOT-working time. Worked time = window length - OOO time.

Usage:
  work-hours.sh                 # default: last 7 days (a week) ending now
  work-hours.sh day             # last 24 hours
  work-hours.sh week            # last 7 days
  work-hours.sh month           # back one calendar month (e.g. May 30 -> Apr 30)
  work-hours.sh --hours 336     # arbitrary N hours back
  work-hours.sh --days 14       # arbitrary N days back
  work-hours.sh 2026-05-01 2026-05-08            # explicit date range
  work-hours.sh "2026-05-01 09:00:00" "2026-05-01 17:00:00"  # explicit datetimes
EOF
    exit "${1:-0}"
}

# Normalize a user-supplied date/datetime into the canonical FMT.
# Accepts "YYYY-MM-DD" (expanded to 00:00:00) or a full "YYYY-MM-DD HH:MM:SS".
normalize_dt() {
    local input="$1"
    if [[ "$input" == ????-??-?? ]]; then
        echo "$input 00:00:00"
    else
        echo "$input"
    fi
}

now=$(date "+$FMT")
window_end="$now"

case "$1" in
    -h|--help)
        usage 0
        ;;
    ""|week)
        window_start=$(date -v-7d "+$FMT")
        ;;
    day)
        window_start=$(date -v-1d "+$FMT")
        ;;
    month)
        window_start=$(date -v-1m "+$FMT")
        ;;
    --hours)
        [[ -n "$2" ]] || usage 2
        window_start=$(date -v-"$2"H "+$FMT")
        ;;
    --days)
        [[ -n "$2" ]] || usage 2
        window_start=$(date -v-"$2"d "+$FMT")
        ;;
    *)
        # Explicit range: <start> <end>
        [[ -n "$2" ]] || usage 2
        window_start=$(normalize_dt "$1")
        window_end=$(normalize_dt "$2")
        ;;
esac

# gcalcli's date args are day-granular, so fetch a slightly wider day range than
# the window; work_hours.py clamps to the exact [window_start, window_end].
fetch_start="${window_start:0:10}"
fetch_end=$(date -j -v+1d -f "%Y-%m-%d" "${window_end:0:10}" "+%Y-%m-%d")

"$GCALCLI" --calendar "$CALENDAR" agenda --military --tsv --details title \
    "$fetch_start" "$fetch_end" \
    | python3 "$PYTHON_MATH" "$window_start" "$window_end"
