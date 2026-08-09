#!/bin/bash

GCALCLI_DIR="$HOME/Library/Application Support/gcalcli"
MEETINGS_FILE="$GCALCLI_DIR/.meetings.json"
JOINED_FILE="$GCALCLI_DIR/.meetings-joined"

touch "$JOINED_FILE"

if [[ ! -f "$MEETINGS_FILE" ]]; then
    exit 0
fi

current_time=$(date +%s)
meeting_buffer_time=$((current_time + 243))

jq -r '.meetings[] | "\(.time) \(.meet_link) \(.name)"' "$MEETINGS_FILE" 2>/dev/null | while read -r meeting_time meet_link meeting_name; do
    if [[ $meeting_time -ge $current_time && $meeting_time -le $meeting_buffer_time ]]; then

        today=$(date '+%Y-%m-%d')
        meeting_key="${today}_${meeting_time}_${meet_link}"

        if ! grep -q "$meeting_key" "$JOINED_FILE"; then
            open "$meet_link"
            echo "$meeting_key" >> "$JOINED_FILE"

            # Nearest whole minute. Anything under 30s reads as "now" rather than
            # the nonsense "in 0 minutes".
            minutes_away=$(( (meeting_time - current_time + 30) / 60 ))
            case $minutes_away in
                0) countdown="starting now" ;;
                1) countdown="starting in 1 minute" ;;
                *) countdown="starting in $minutes_away minutes" ;;
            esac

            # -- so a title beginning with a dash isn't parsed as a say(1) flag.
            say -- "$meeting_name $countdown"
        fi
    fi
done

grep "$(date '+%Y-%m-%d')" "$JOINED_FILE" > "$JOINED_FILE.tmp" 2>/dev/null || touch "$JOINED_FILE.tmp"
mv "$JOINED_FILE.tmp" "$JOINED_FILE"