#!/bin/bash
#
# Init script
#
###########################################################

DOCKER_LOG=/var/log/docker.log
DEBUG_LOG=/dev/null
if [ "$DEBUG" = true ]; then
  DEBUG_LOG=$DOCKER_LOG
fi

# Initialize CCache if it will be used
if [ "$USE_CCACHE" = 1 ]; then
  ccache -M 100G 2>&1 >&$DEBUG_LOG
fi

# Initialize Git user information
git config --global user.name $USER_NAME
git config --global user.email $USER_MAIL

# Initialize the cronjob
cronFile=/tmp/buildcron
printf "SHELL=/bin/bash\n" > $cronFile
printenv -0 | sed -e 's/=\x0/=""\n/g'  | sed -e 's/\x0/\n/g' | sed -e "s/_=/PRINTENV=/g" >> $cronFile
printf "\n$CRONTAB_TIME /usr/bin/flock -n /tmp/lock.build /root/build.sh >> $DOCKER_LOG 2>&1\n" >> $cronFile
crontab $cronFile
rm $cronFile

# Run crond in foreground
crond -n -m off 2>&1
