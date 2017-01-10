#!/bin/bash
#
# Init script
#
###########################################################

# Initialize CCache if it will be used
if [ "$USE_CCACHE" = 1 ]; then
  ccache -M 50G
fi

# Initialize Git user information
git config --global user.name $USER_NAME
git config --global user.email $USER_MAIL

# Initialize the cronjob
echo -e "$CRONTAB_TIME /usr/bin/flock -n /tmp/lock.build /root/build.sh\n" > /var/spool/cron/root
chmod 0600 /var/spool/cron/root

# Run crond in foreground
crond -n -m off -P