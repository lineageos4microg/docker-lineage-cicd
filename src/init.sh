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
cronFile=/tmp/buildcron
printf "SHELL=/bin/bash\n" > $cronFile
printenv -0 | sed -e 's/=\x0/=""\n/g'  | sed -e 's/\x0/\n/g' | sed -e "s/_=/PRINTENV=/g" >> $cronFile
printf "\n$CRONTAB_TIME /usr/bin/flock -n /tmp/lock.build /root/build.sh 2>&1\n" >> $cronFile
crontab $cronFile
rm $cronFile

# Run crond in foreground
crond -n -m off