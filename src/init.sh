#!/bin/bash

# Docker init script
# Copyright (c) 2017 Julian Xhokaxhiu
# Copyright (C) 2017 Nicola Corna <nicola@corna.info>
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Copy the user scripts
mkdir -p /root/userscripts
cp -r $USERSCRIPTS_DIR/. /root/userscripts
find /root/userscripts ! -type d ! -user root -exec echo ">> [$(date)] {} is not owned by root, removing" \; -exec rm {} \;
find /root/userscripts ! -type d -perm /g=w,o=w -exec echo ">> [$(date)] {} is writable by non-root users, removing" \; -exec rm {} \;

# Initialize CCache if it will be used
if [ "$USE_CCACHE" = 1 ]; then
  ccache -M $CCACHE_SIZE 2>&1
fi

# Initialize Git user information
git config --global user.name $USER_NAME
git config --global user.email $USER_MAIL

if [ "$CRONTAB_TIME" = "now" ]; then
  /root/build.sh
else
  # Initialize the cronjob
  cronFile=/tmp/buildcron
  printf "SHELL=/bin/bash\n" > $cronFile
  printenv -0 | sed -e 's/=\x0/=""\n/g'  | sed -e 's/\x0/\n/g' | sed -e "s/_=/PRINTENV=/g" >> $cronFile
  printf "\n$CRONTAB_TIME /usr/bin/flock -n /tmp/lock.build /root/build.sh >> $DOCKER_LOG 2>&1\n" >> $cronFile
  crontab $cronFile
  rm $cronFile

  # Run crond in foreground
  cron -f 2>&1
fi
