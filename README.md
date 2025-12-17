# comprehensive step by step guide to setting up auto-join-meetings
Not really, but it's a good start.

## get gcalcli setup
Follow the instructions [here](https://github.com/insanum/gcalcli) to get gcalcli setup.

## clone this repo
`git clone git@github.com:marallyn/auto-join-meetings.git`

## setup crontab
Add something like this to your crontab:
```
# fetch new meetings every fifteen minutes
*/15 * * * * /path/to/code/auto-join-meetings/bin/fetch-meetings.sh > /dev/null 2>&1

# try to join meetings every minute
* * * * * /path/to/code/auto-join-meetings/bin/auto-join-meeting.sh /dev/null 2>&1
```

## adjust scripts to your liking
Adjust the directory constants in fetch-meetings.sh and auto-join-meeting.sh to match your setup, or add a PR to pull these values from a config file.

Adjust this line of auto-join-meeting.sh:
```
meeting_buffer_time=$((current_time + 243))
```
243 is four minutes and three seconds.  Adjust as needed, or add a PR to pull this value from a config file.
