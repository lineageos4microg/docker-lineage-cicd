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
# - handle local manifests
# - Sync mirror if we're using one
# - Branch-specific stuff
# -  main sync and build loop
#    For each device in `$DEVICE_LIST`
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

# Handle parameters and environment variables
branch=$BRANCH_NAME
echo ">> [$(date)] Branch:  $branch"

devices=$DEVICE_LIST
echo ">> [$(date)] Devices: $devices"

vendor=lineage

## CLEAN_OUTDIR
if [ "$CLEAN_OUTDIR" = true ]; then
 echo ">> [$(date)] Cleaning '$ZIP_DIR'"
 rm -rf "${ZIP_DIR:?}/"*
fi

## PARALLEL_JOBS
jobs_arg=()
if [ -n "${PARALLEL_JOBS-}" ]; then
  if [[ "$PARALLEL_JOBS" =~ ^[1-9][0-9]*$ ]]; then
    jobs_arg+=( "-j$PARALLEL_JOBS" )
  else
    echo "PARALLEL_JOBS is not a positive number: $PARALLEL_JOBS"
    exit 1
  fi
fi

## RETRY_FETCHES
retry_fetches_arg=()
if [ -n "${RETRY_FETCHES-}" ]; then
  if [[ "$RETRY_FETCHES" =~ ^[1-9][0-9]*$ ]]; then
    retry_fetches_arg+=( "--retry-fetches=$RETRY_FETCHES" )
  else
    echo "RETRY_FETCHES is not a positive number: $RETRY_FETCHES"
    exit 1
  fi
fi

# Handle local manifests
## Copy local manifests
echo ">> [$(date)] Copying '$LMANIFEST_DIR/*.xml' to '.repo/local_manifests/'"
mkdir -p .repo/local_manifests
rsync -a --delete --include '*.xml' --exclude '*' "$LMANIFEST_DIR/" .repo/local_manifests/

## Pick up TheMuppets manifest if required
rm -f .repo/local_manifests/proprietary.xml
if [ "$INCLUDE_PROPRIETARY" = true ]; then
  wget -q -O .repo/local_manifests/proprietary.xml "https://raw.githubusercontent.com/TheMuppets/manifests/$themuppets_branch/muppets.xml"
  /root/build_manifest.py --remote "https://gitlab.com" --remotename "gitlab_https" \
    "https://gitlab.com/the-muppets/manifest/raw/$themuppets_branch/muppets.xml" .repo/local_manifests/proprietary_gitlab.xml
fi

# Sync mirror if we're using one
if [ "$LOCAL_MIRROR" = true ]; then

  cd "$MIRROR_DIR"
  if [ "$INIT_MIRROR" = true ]; then
    if [ ! -d .repo ]; then
      echo ">> [$(date)] Initializing mirror repository" | tee -a "$repo_log"
      ( yes||: ) | repo init -u https://github.com/LineageOS/mirror --mirror --no-clone-bundle -p linux --git-lfs &>> "$repo_log"
    fi
  else
    echo ">> [$(date)] Initializing mirror repository disabled" | tee -a "$repo_log"
  fi
  if [ "$SYNC_MIRROR" = true ]; then
    echo ">> [$(date)] Syncing mirror repository" | tee -a "$repo_log"
    repo sync "${jobs_arg[@]}" --force-sync --no-clone-bundle &>> "$repo_log"
  else
    echo ">> [$(date)] Sync mirror repository disabled" | tee -a "$repo_log"
  fi
fi

# Branch-specific stuff
branch_dir=${branch//[^[:alnum:]]/_}
branch_dir=${branch_dir^^}

if [ -n "$branch" ] && [ -n "$devices" ]; then
  case "$branch" in
    lineage-21.0*)
      themuppets_branch="lineage-21.0"
      android_version="14"
      ;;
    *)
      echo ">> [$(date)] Building branch $branch is not (yet) suppported"
      exit 1
      ;;
    esac
    android_version_major=$(cut -d '.' -f 1 <<< $android_version)

    mkdir -p "$SRC_DIR/$branch_dir"
    cd "$SRC_DIR/$branch_dir"
fi

# -  main sync and build loop
#    For each device in `$DEVICE_LIST`
for codename in ${devices//,/ }; do
  if [ -n "$codename" ]; then
  # - `repo init`
  # - `repo sync`
  # - setup our overlays
    
  fi

# More stuff to do

done
