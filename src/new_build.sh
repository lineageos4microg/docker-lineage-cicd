#!/bin/bash

# Slimmed-down Docker build script
# Copyright (c) 2017 Julian Xhokaxhiu
# Copyright (C) 2017-2018 Nicola Corna <nicola@corna.info>
# Copyright (C) 2024 Pete Fotheringham <petefoth@e.email>
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
# along with this program.  If not, see <http://www.gnu.org/licenses/>


# Outline
# - Call `begin.sh`
# - Handle parameters and environment variables
#      -  CLEAN_OUTDIR
#      -  PARALLEL_JOBS
#      -  RETRY_FETCHES
# - handle manifests
# - Sync mirror
# - Branch-specific stuff
# -  main sync and build loop For each device in `$DEVICE_LIST`
#     - setup build overlay
#     - `repo init`
#     - `repo sync`
#     - Call `before.sh`
#     - `breakfast` - in case of failure, call
#         - `post-build.sh`
#         - `do_cleanup`
#     - `mka`
#     - move artefacts to `ZIPDIR`
#         - ROM zip file
#         - `.img` files
#         - create the checksum files
#         - Remove old zips and logs
#     - call `post-build.sh`
#     - call `do_cleanup`
# - call `end.sh`

# do_cleanup function
do_cleanup() {
  echo ">> [$(date)] Cleaning up" | tee -a "$DEBUG_LOG"

  if [ "$BUILD_OVERLAY" = true ]; then
    # The Jack server must be stopped manually, as we want to unmount $TMP_DIR/merged
    cd "$TMP_DIR"
    if [ -f "$TMP_DIR/merged/prebuilts/sdk/tools/jack-admin" ]; then
      "$TMP_DIR/merged/prebuilts/sdk/tools/jack-admin kill-server" &> /dev/null || true
    fi
    lsof | grep "$TMP_DIR/merged" | awk '{ print $2 }' | sort -u | xargs -r kill &> /dev/null || true

    while lsof | grep -q "$TMP_DIR"/merged; do
      sleep 1
    done

    umount "$TMP_DIR/merged"
  fi

  if [ "$CLEAN_AFTER_BUILD" = true ]; then
    echo ">> [$(date)] Cleaning source dir for device $codename" | tee -a "$DEBUG_LOG"
    if [ "$BUILD_OVERLAY" = true ]; then
      cd "$TMP_DIR"
      rm -rf ./* || true
    else
      cd "$source_dir"
      (set +eu ; mka "${jobs_arg[@]}" clean) &>> "$DEBUG_LOG"
    fi
  fi
}

# Build script

set -eEuo pipefail
repo_log="$LOGS_DIR/repo-$(date +%Y%m%d).log"

# cd to working directory
cd "$SRC_DIR"

# Call `begin.sh`
if [ -f /root/userscripts/begin.sh ]; then
  echo ">> [$(date)] Running begin.sh"
  /root/userscripts/begin.sh || { echo ">> [$(date)] Error: begin.sh failed!"; exit 1; }
fi
