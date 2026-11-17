#!/bin/bash
# Open a URL in the Chrome window that belongs to a Google account.
#
#   open-in-chrome.sh <url> <account-email>
#   DRY_RUN=1 open-in-chrome.sh <url> <account-email>   # report the choice, open nothing
#
# Chrome's AppleScript doesn't expose which profile a window belongs to, but a
# Gmail tab's title contains the signed-in address. So:
#   1. a window with a Gmail tab for <account>, preferring the one with the most
#      Google tabs (mail, calendar, docs...) -> new tab there, window raised
#   2. else the profile whose signed-in user is <account> (from Local State)
#   3. else plain `open`, wherever Chrome feels like putting it

url="$1"
account="$2"
LOCAL_STATE="$HOME/Library/Application Support/Google/Chrome/Local State"

if [[ -z "$url" || -z "$account" ]]; then
    echo "usage: $0 <url> <account-email>" >&2
    exit 2
fi

if pgrep -xq "Google Chrome"; then
    result=$(osascript - "$url" "$account" "${DRY_RUN:-}" <<'APPLESCRIPT' 2>&1
on run argv
    set theUrl to item 1 of argv
    set theAccount to item 2 of argv
    set dryRun to (item 3 of argv) is not ""

    tell application "Google Chrome"
        set bestWindow to missing value
        set bestScore to -1
        repeat with w in windows
            if mode of w is "normal" then
                set ownsAccount to false
                set googleTabs to 0
                repeat with t in tabs of w
                    set u to URL of t
                    if u starts with "https://mail.google.com/" and (title of t) contains theAccount then set ownsAccount to true
                    if u contains ".google.com/" then set googleTabs to googleTabs + 1
                end repeat
                if ownsAccount and googleTabs > bestScore then
                    set bestWindow to w
                    set bestScore to googleTabs
                end if
            end if
        end repeat

        if bestWindow is missing value then return "none"
        if dryRun then return "would open in window " & (id of bestWindow) & " (" & bestScore & " google tabs): " & (name of bestWindow)

        tell bestWindow to make new tab with properties {URL:theUrl}
        set index of bestWindow to 1
        activate
        return "opened in window " & (id of bestWindow)
    end tell
end run
APPLESCRIPT
)
    # "none" or an osascript error (e.g. Automation permission denied) falls through.
    if [[ "$result" == *"window "* ]]; then
        echo "$result"
        exit 0
    fi
    echo "no window found by Gmail tab ($result)" >&2
fi

profile_dir=$(jq -r --arg a "$account" \
    '.profile.info_cache | to_entries[] | select(.value.user_name == $a) | .key' \
    "$LOCAL_STATE" 2>/dev/null | head -1)

if [[ -n "$profile_dir" ]]; then
    if [[ -n "$DRY_RUN" ]]; then echo "would open in profile $profile_dir"; exit 0; fi
    # -n is what makes --args reach an already running Chrome; it hands off and exits.
    open -na "Google Chrome" --args --profile-directory="$profile_dir" "$url"
    echo "opened in profile $profile_dir"
    exit 0
fi

if [[ -n "$DRY_RUN" ]]; then echo "would open with default handler"; exit 0; fi
open "$url"
echo "no Chrome profile for $account, opened with default handler"
