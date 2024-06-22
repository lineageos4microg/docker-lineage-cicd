#!/bin/bash

# Docker init script
# Copyright (c) 2017 Julian Xhokaxhiu
# Copyright (C) 2017-2018 Nicola Corna <nicola@corna.info>
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

set -eEuo pipefail

# Copy the user scripts
mkdir -p /root/userscripts
cp -r "$USERSCRIPTS_DIR"/. /root/userscripts
find /root/userscripts ! -type d ! -user root -exec echo ">> [$(date)] {} is not owned by root, removing" \; -exec rm {} \;
find /root/userscripts ! -type d -perm /g=w,o=w -exec echo ">> [$(date)] {} is writable by non-root users, removing" \; -exec rm {} \;

# Initialize CCache if it will be used
if [ "$USE_CCACHE" = 1 ]; then
  ccache -M "$CCACHE_SIZE" 2>&1
fi

# Initialize Git user information
git config --global user.name "$USER_NAME"
git config --global user.email "$USER_MAIL"

if [ "$SIGN_BUILDS" = true ]; then
  for c in bluetooth cyngn-app media networkstack nfc platform releasekey sdk_sandbox shared testcert testkey verity ; do
    if [ ! -f "$KEYS_DIR/$c.pk8" ]; then
      echo ">> [$(date)]  Generating $c..."
      /root/make_key "$KEYS_DIR/$c" "$KEYS_SUBJECT" <<< '' &> /dev/null
    fi
  done

  for c in cyngn{-priv,}-app testkey; do
    for e in pk8 x509.pem; do
      ln -sf releasekey.$e "$KEYS_DIR/$c.$e" 2> /dev/null
    done
  done
fi

# Android 14 requires to set a BUILD file for bazel to avoid errors:
cat > "$KEYS_DIR"/BUILD << _EOB
# adding an empty BUILD file fixes the A14 build error:
# "ERROR: no such package 'keys': BUILD file not found in any of the following directories. Add a BUILD file to a directory to mark it as a package."
# adding the filegroup "android_certificate_directory" fixes the A14 build error:
# "no such target '//keys:android_certificate_directory': target 'android_certificate_directory' not declared in package 'keys'"
filegroup(
name = "android_certificate_directory",
srcs = glob([
"*.pk8",
"*.pem",
]),
visibility = ["//visibility:public"],
)
_EOB

if [ "$CRONTAB_TIME" = "now" ]; then
  /root/build.sh
else
  # Initialize the cronjob
  cronFile=/tmp/buildcron
  printf "SHELL=/bin/bash\n" > $cronFile
  printenv -0 | sed -e 's/=\x0/=""\n/g'  | sed -e 's/\x0/\n/g' | sed -e "s/_=/PRINTENV=/g" >> $cronFile
  printf '\n%s /usr/bin/flock -n /var/lock/build.lock /root/build.sh >> /var/log/docker.log 2>&1\n' "$CRONTAB_TIME" >> $cronFile
  crontab $cronFile
  rm $cronFile

  # Run crond in foreground
  cron -f 2>&1
fi
