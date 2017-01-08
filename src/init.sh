#!/bin/bash
#
# Init script
#
###########################################################

# Set a custom updater URI if a OTA URL is provided
if ! [ -z "$OTA_URL" ]; then
  export ADDITIONAL_DEFAULT_PROPERTIES="cm.updater.uri=$OTA_URL"
fi

# Initialize CCache if it will be used
if [ "$USE_CCACHE" = 1 ]; then
  ccache -M 50G
fi

# Initialize Git user information
git config --global user.name $USER_NAME
git config --global user.email $USER_MAIL

# Initialize the cronjob
echo -e "$CRONTAB_TIME /usr/bin/flock -n /tmp/lock.build /root/build.sh\n" > /etc/cron.d/crontab

# Start the cron job service
cron -f