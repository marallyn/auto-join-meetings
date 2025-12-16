#!/bin/zsh

echo "=== CRON ENVIRONMENT TEST ===" > /tmp/cron-test.log
echo "DATE: $(date)" >> /tmp/cron-test.log
echo "PATH: $PATH" >> /tmp/cron-test.log
echo "HOME: $HOME" >> /tmp/cron-test.log
echo "USER: $USER" >> /tmp/cron-test.log

# Test gcalcli location
echo "WHICH GCALCLI: $(which gcalcli)" >> /tmp/cron-test.log

echo "GCALCLI_CONFIG=$GCALCLI_CONFIG" >> /tmp/cron-test.log
# Test gcalcli auth
/opt/homebrew/bin/gcalcli list >> /tmp/cron-test.log 2>&1

echo "=== END TEST ===" >> /tmp/cron-test.log