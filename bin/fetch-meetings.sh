#!/bin/zsh

# fetch meetings with hangout_links and start times today and tomorrow
# cache for use elsewhere
GCALCLI="/opt/homebrew/bin/gcalcli"
GCALCLI_DIR="$HOME/Library/Application Support/gcalcli"
MEETINGS_FILE="$GCALCLI_DIR/.meetings.json"
TEMP_FILE="$GCALCLI_DIR/.meetings.tmp"

export GCALCLI_CONFIG="$GCALCLI_DIR"
$GCALCLI agenda --military --tsv --nostarted --details={time,url,title} \
    $(date '+%Y-%m-%d') \
    $(date -v+2d '+%Y-%m-%d') \
    | grep -E "meet\.google\.com|https://" \
    | while IFS=$'\t' read -r start_date start_time end_date end_time html_link hangout_link title; do

    meeting_time=$(date -j -f "%Y-%m-%d %H:%M" "$start_date $start_time" "+%s" 2>/dev/null)

    if [[ -n "$meeting_time" && "$hangout_link" == *"meet.google.com"* ]]; then
      echo "{\"name\":\"$title\",\"time\":$meeting_time,\"meet_link\":\"$hangout_link\"}"
    fi

done | jq -s '{"meetings": .}' > "$TEMP_FILE"

mv "$TEMP_FILE" "$MEETINGS_FILE"

echo "$MEETINGS_FILE Updated with new meetings"