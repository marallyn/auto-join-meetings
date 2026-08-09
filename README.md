# comprehensive step by step guide to setting up auto-join-meetings
Not really, but it's a good start.

## get gcalcli setup
Follow the instructions [here](https://github.com/insanum/gcalcli) to get gcalcli setup.

## clone this repo
`git clone git@github.com:marallyn/auto-join-meetings.git`

## install the launchd agents
```
./bin/install.sh
```

This substitutes your real paths into the plist templates in `bin/`, writes them to
`~/Library/LaunchAgents`, loads them, and removes any leftover crontab entries from
older versions of this repo (backed up to the log directory first).

Two agents get installed:

| label | script | schedule |
| --- | --- | --- |
| `com.auto-join-meetings.fetch` | `bin/fetch-meetings.sh` | :00 :15 :30 :45 |
| `com.auto-join-meetings.join` | `bin/auto-join-meeting.sh` | every 60 seconds |

Because the plists are templates, `install.sh` writes a *generated copy* into
`~/Library/LaunchAgents` rather than symlinking. Edit a template, re-run
`install.sh`. It's idempotent.

To remove everything: `./bin/uninstall.sh`

## check on it
```
# is it loaded and waiting?
launchctl print gui/$UID/com.auto-join-meetings.fetch

# force a run right now
launchctl kickstart -k gui/$UID/com.auto-join-meetings.fetch

# what did it say?
tail -f ~/Library/Logs/auto-join-meetings/fetch.log
```

Unlike the cron setup this replaced, output is not thrown away — gcalcli auth
failures show up in the logs instead of failing silently.

## adjust scripts to your liking
Adjust the directory constants in fetch-meetings.sh and auto-join-meeting.sh to match your setup, or add a PR to pull these values from a config file.

Adjust this line of auto-join-meeting.sh:
```
meeting_buffer_time=$((current_time + 243))
```
243 is four minutes and three seconds.  Adjust as needed, or add a PR to pull this value from a config file.
