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
#      -  ENABLE_EXTENDROM & EXTEND_ROM_PACKAGES
#      -  CLEAN_OUTDIR
#      -  PARALLEL_JOBS
#      -  RETRY_FETCHES
# - Branch-specific stuff
# - handle local manifests
# - Sync mirror if we're using one
# -  main sync and build loop
#    For each device in `$DEVICE_LIST`
#     - setup subdirectories
#     - `repo init`
#     - `repo sync`
#     - setup our overlays
#     - Set RELEASE_TYPE
#     - Handle OTA_URL
#     - Add custom packages to be installed
#     - Handle keys
#     - Setup / enable EXTENDROM
#     - Prepare the environment
#     - Call `before.sh`
#     - `breakfast` - in case of failure, call
#         - `post-build.sh`
#         - `do_cleanup`
#     - Call `pre-build.sh`
#     - Call `mka`
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
      echo ">> [$(date)] Removing $TMP_DIR for device $codename" | tee -a "$DEBUG_LOG"
      cd "$TMP_DIR"
      rm -rf ./* || true
    else
      cd "$source_dir"
      echo ">> [$(date)] Removing $PWD/out" | tee -a "$DEBUG_LOG"
      rm -rf out || true
      echo ">> [$(date)] Removing $PWD/vendor(except extendrom)" | tee -a "$DEBUG_LOG"
      cd vendor
      find . -maxdepth 1 -type d -not -name "extendrom" -exec rm -rf {} \; || true
      cd ..
      echo ">> [$(date)] Removing $PWD/.repo/local_manifests/roomservice.xml" | tee -a "$DEBUG_LOG"
      rm -f .repo/local_manifests/roomservice.xml
      echo ">> [$(date)] Cleaning system/core" | tee -a "$DEBUG_LOG"
      cd system/core
      git reset -q --hard
      git clean -q -fd
      cd ../..
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

if [ "$BUILD_OVERLAY" = true ]; then
  echo "Using BUILD_OVERLAY is not yet working"
  exit 1
fi

if [ "$WITH_GMS" = true ] && [ "$ENABLE_EXTENDROM" = true ]  ; then
    echo "WITH_GMS and ENABLE_EXTENDROM cannot be used together: choose one or the other"
    exit 1
fi

## ENABLE_EXTENDROM
if [ "$ENABLE_EXTENDROM" = true ]  ; then
    EXTENDROM_PACKAGES="$EXTENDROM_PACKAGES FDroid FakeStore_GH MicrogGmsCore_GH_PRERELEASE GsfProxy_GH"
    echo "Including EXTEND_ROM_PACKAGES $EXTENDROM_PACKAGES"
fi

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

# Branch-specific stuff
branch_dir=${branch//[^[:alnum:]]/_}
branch_dir=${branch_dir^^}

source_dir="$SRC_DIR/$branch_dir"
mkdir -p "$source_dir"
cd "$SRC_DIR/$branch_dir"

# select branch and android version without maintaining a list
branch_num=${branch##*-}
themuppets_branch=$branch
android_version=$(echo "($branch_num - 7)" | bc)
echo ">> [$(date)] Android version: $android_version"
android_version_major=$(echo "($branch_num - 7) / 1" | bc)

if [ "$RESET_VENDOR_UNDO_PATCHES" = true ]; then
  # Remove previous changes of vendor/cm, vendor/lineage and frameworks/base (if they exist)
  # TODO: maybe reset everything using https://source.android.com/setup/develop/repo#forall
  for path in "vendor/cm" "vendor/lineage" "frameworks/base" "packages/apps/PermissionController" "packages/modules/Permission"; do
    if [ -d "$path" ]; then
      cd "$path"
      git reset -q --hard
      git clean -q -fd
      cd "$SRC_DIR/$branch_dir"
    fi
  done
else
  echo ">> [$(date)] Resetting vendor and undoing patches disabled" | tee -a "$repo_log"
fi

# Handle local manifests
## Copy local manifests
echo ">> [$(date)] Copying '$LMANIFEST_DIR/*.xml' to '.repo/local_manifests/'"
mkdir -p .repo/local_manifests
rsync -a --delete --include '*.xml' --exclude '*' "$LMANIFEST_DIR/" .repo/local_manifests/

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
    repo sync "${jobs_arg[@]}" "${retry_fetches_arg[@]}" --force-sync --no-clone-bundle &>> "$repo_log"

  else
    echo ">> [$(date)] Sync mirror repository disabled" | tee -a "$repo_log"
  fi
  cd "$source_dir"
fi

# -  main sync and build loop
#    For each device in `$DEVICE_LIST`
for codename in ${devices//,/ }; do
  if [ -n "$codename" ]; then
    builddate=$(date +%Y%m%d)

    # setup subdirectories
    if [ "$ZIP_SUBDIR" = true ]; then
      zipsubdir=$codename
      mkdir -p "$ZIP_DIR/$zipsubdir"
    else
      zipsubdir=
    fi
    if [ "$LOGS_SUBDIR" = true ]; then
      logsubdir=$codename
      mkdir -p "$LOGS_DIR/$logsubdir"
    else
      logsubdir=
    fi

    # Set device specific logfils
    DEBUG_LOG="$LOGS_DIR/$logsubdir/$branch-$builddate-$RELEASE_TYPE-$codename.log"
    ## Pick up TheMuppets manifest if required
    rm -f .repo/local_manifests/proprietary.xml
    if [ "$INCLUDE_PROPRIETARY" = true ]; then
      wget -q -O .repo/local_manifests/proprietary.xml "https://raw.githubusercontent.com/TheMuppets/manifests/$themuppets_branch/muppets.xml"
      /root/build_manifest.py --remote "https://gitlab.com" --remotename "gitlab_https" \
        "https://gitlab.com/the-muppets/manifest/raw/$themuppets_branch/muppets.xml" .repo/local_manifests/proprietary_gitlab.xml
    fi

    # `repo init`
    if [ "$CALL_REPO_INIT" = true ]; then
      echo ">> [$(date)] (Re)initializing branch repository" | tee -a "$repo_log"
      if [ "$LOCAL_MIRROR" = true ]; then
        ( yes||: ) | repo init -u https://github.com/LineageOS/android.git --reference "$MIRROR_DIR" -b "$branch" -g default,-darwin,-muppets,muppets_"${codename}" --git-lfs &>> "$repo_log"
      else
        ( yes||: ) | repo init -u https://github.com/LineageOS/android.git -b "$branch" -g default,-darwin,-muppets,muppets_"${codename}" --git-lfs &>> "$repo_log"
      fi
    else
      echo ">> [$(date)] Calling repo init disabled"
    fi

    # `repo sync`
    repo_sync_returncode=0
    if [ "$CALL_REPO_SYNC" = true ]; then
      set +eu
      echo ">> [$(date)] Syncing branch repository" | tee -a "$repo_log"
      repo sync "${jobs_arg[@]}" "${retry_fetches_arg[@]}" --current-branch --force-sync &>> "$repo_log"
      repo_sync_returncode=$?
      set -eu
    else
      echo ">> [$(date)] Syncing branch repository disabled" | tee -a "$repo_log"
    fi

    if [ $repo_sync_returncode -ne 0 ]; then
        echo ">> [$(date)] repo sync failed for $codename, $branch branch" | tee -a "$DEBUG_LOG"
        # call post-build.sh so the failure is logged in a way that is more visible
        if [ -f /root/userscripts/post-build.sh ]; then
          echo ">> [$(date)] Running post-build.sh for $codename" >> "$DEBUG_LOG"
          /root/userscripts/post-build.sh "$codename" false "$branch" &>> "$DEBUG_LOG" || echo ">> [$(date)] Warning: post-build.sh failed!"
        fi
        do_cleanup
        continue
    fi

    if [ "$WITH_GMS" = true ]; then
      echo ">> [$(date)] Populating vendor/partner_gms-tv/products" | tee -a "$repo_log"
      rm -rf "$source_dir/vendor/partner_gms-tv" || true
      mkdir -p  "$source_dir/vendor/partner_gms-tv/products"
      cp  -r "$source_dir/vendor/partner_gms/products/"  "$source_dir/vendor/partner_gms-tv/" | tee -a "$DEBUG_LOG"
    fi

    if [ "$CALL_GIT_LFS_PULL" = true ]; then
      echo ">> [$(date)] Calling git lfs pull" | tee -a "$repo_log"
      repo forall -v -c git lfs pull &>> "$repo_log"
    else
      echo ">> [$(date)] Calling git lfs pull disabled" | tee -a "$repo_log"
    fi

    if [ ! -d "vendor/$vendor" ]; then
      echo ">> [$(date)] Missing \"vendor/$vendor\", aborting"
      exit 1
    fi

  # Setup our overlays
    if [ "$BUILD_OVERLAY" = true ]; then
      echo "Using BUILD_OVERLAY is not yet working"
      exit 1

      # lowerdir=$SRC_DIR/$branch_dir
      # upperdir=$TMP_DIR/device
      # workdir=$TMP_DIR/workdir
      # merged=$TMP_DIR/merged
      # mkdir -p "$upperdir" "$workdir" "$merged"
      # mount -t overlay overlay -o lowerdir="$lowerdir",upperdir="$upperdir",workdir="$workdir" "$merged"
      # source_dir="$TMP_DIR/merged"
    else
      source_dir="$SRC_DIR/$branch_dir"
    fi

    mkdir -p "vendor/$vendor/overlay/microg/"
    sed -i "1s;^;PRODUCT_PACKAGE_OVERLAYS := vendor/$vendor/overlay/microg\n;" "vendor/$vendor/config/common.mk"

    makefile_containing_version="vendor/$vendor/config/common.mk"
    if [ -f "vendor/$vendor/config/version.mk" ]; then
      makefile_containing_version="vendor/$vendor/config/version.mk"
    fi
    los_ver_major=$(sed -n -e 's/^\s*PRODUCT_VERSION_MAJOR = //p' "$makefile_containing_version")
    los_ver_minor=$(sed -n -e 's/^\s*PRODUCT_VERSION_MINOR = //p' "$makefile_containing_version")
    los_ver="$los_ver_major.$los_ver_minor"

#    DEBUG_LOG="$LOGS_DIR/$logsubdir/lineage-$los_ver-$builddate-$RELEASE_TYPE-$codename.log"

    # Set RELEASE_TYPE
    echo ">> [$(date)] Setting \"$RELEASE_TYPE\" as release type"
    sed -i "/\$(filter .*\$(${vendor^^}_BUILDTYPE)/,/endif/d" "$makefile_containing_version"

    # Set a custom updater URI if a OTA URL is provided
    echo ">> [$(date)] Adding OTA URL overlay (for custom URL $OTA_URL)"
    if [ -n "$OTA_URL" ]; then
      if [ -d "packages/apps/Updater/app/src/main/res/values" ]; then
        # "New" Updater project structure
        updater_values_dir="packages/apps/Updater/app/src/main/res/values"
      elif [ -d "packages/apps/Updater/res/values" ]; then
        # "Old" Updater project structure
        updater_values_dir="packages/apps/Updater/res/values"
      else
        echo ">> [$(date)] ERROR: no 'values' dir of Updater app found"
        exit 1
      fi

      updater_url_overlay_dir="vendor/$vendor/overlay/microg/${updater_values_dir}/"
      mkdir -p "$updater_url_overlay_dir"

      if grep -q updater_server_url ${updater_values_dir}/strings.xml; then
        # "New" updater configuration: full URL (with placeholders {device}, {type} and {incr})
        sed "s|{name}|updater_server_url|g; s|{url}|$OTA_URL/v1/{device}/{type}/{incr}|g" /root/packages_updater_strings.xml > "$updater_url_overlay_dir/strings.xml"
      elif grep -q conf_update_server_url_def ${updater_values_dir}/strings.xml; then
        # "Old" updater configuration: just the URL
        sed "s|{name}|conf_update_server_url_def|g; s|{url}|$OTA_URL|g" /root/packages_updater_strings.xml > "$updater_url_overlay_dir/strings.xml"
      else
        echo ">> [$(date)] ERROR: no known Updater URL property found"
        exit 1
      fi
    fi

    # Add custom packages to be installed
    if [ -n "$CUSTOM_PACKAGES" ]; then
      echo ">> [$(date)] Adding custom packages ($CUSTOM_PACKAGES)"
      sed -i "1s;^;PRODUCT_PACKAGES += $CUSTOM_PACKAGES\n\n;" "vendor/$vendor/config/common.mk"
    fi

    # Handle keys
    if [ "$SIGN_BUILDS" = true ]; then
      echo ">> [$(date)] Adding keys path ($KEYS_DIR)"
      # Soong (Android 9+) complains if the signing keys are outside the build path
      ln -sf "$KEYS_DIR" user-keys
      if [ "$android_version_major" -lt "10" ]; then
        sed -i "1s;^;PRODUCT_DEFAULT_DEV_CERTIFICATE := user-keys/releasekey\nPRODUCT_OTA_PUBLIC_KEYS := user-keys/releasekey\nPRODUCT_EXTRA_RECOVERY_KEYS := user-keys/releasekey\n\n;" "vendor/$vendor/config/common.mk"
      fi

      if [ "$android_version_major" -ge "10" ]; then
        sed -i "1s;^;PRODUCT_DEFAULT_DEV_CERTIFICATE := user-keys/releasekey\nPRODUCT_OTA_PUBLIC_KEYS := user-keys/releasekey\n\n;" "vendor/$vendor/config/common.mk"
      fi
    fi

    # Setup EXTENDROM
    ## Enable it in `config/common.mk`
    if grep -q 'inherit-product, vendor/extendrom/config/common.mk' "$PWD/vendor/$vendor/lineage/config/common.mk" ; then
      echo "extendrom already enabled in /vendor/$vendor/config/common.mk"
    else
      echo "enabling extendrom in /vendor/$vendor/config/common.mk"
      echo "\$(call inherit-product, vendor/extendrom/config/common.mk)" >> "$PWD/vendor/$vendor/config/common.mk"
    fi

    ## call `er.sh` to download the packages & write the makefile
    "$PWD"/vendor/extendrom/er.sh || { echo ">> [$(date)] Error: extendrom/er.sh failed!"; exit 1; }

    # Prepare the environment
    if [ "$PREPARE_BUILD_ENVIRONMENT" = true ]; then
      echo ">> [$(date)] Preparing build environment"
      set +eu
      # shellcheck source=/dev/null
      source build/envsetup.sh > /dev/null
      set -eu
    else
      echo ">> [$(date)] Preparing build environment disabled"
    fi

    userscriptfail=false

    # Call `before.sh`
    if [ -f /root/userscripts/before.sh ]; then
      echo ">> [$(date)] Running before.sh"
      echo "before.sh is now called *after* repo sync."
      echo "In previous versions, iot was called *before* repo sync"
      /root/userscripts/before.sh "$branch" || { echo ">> [$(date)] Error: before.sh failed for $branch!"; userscriptfail=true; continue; }
    fi

    # Call breakfast
    breakfast_returncode=0
    if [ "$CALL_BREAKFAST" = true ]; then
      set +eu
      breakfast "$codename" "$BUILD_TYPE" &>> "$DEBUG_LOG"
      breakfast_returncode=$?
      set -eu
    else
      echo ">> [$(date)] Calling breakfast disabled"
    fi

    if [ $breakfast_returncode -ne 0 ]; then
        echo ">> [$(date)] breakfast failed for $codename, $branch branch" | tee -a "$DEBUG_LOG"
        # call post-build.sh so the failure is logged in a way that is more visible
        if [ -f /root/userscripts/post-build.sh ]; then
          echo ">> [$(date)] Running post-build.sh for $codename" >> "$DEBUG_LOG"
          /root/userscripts/post-build.sh "$codename" false "$branch" &>> "$DEBUG_LOG" || echo ">> [$(date)] Warning: post-build.sh failed!"
        fi
        do_cleanup
        continue
    fi

    # Apply the PlayIntegrity patch if the APPLY_PI_PATCH is set
    if [ "$APPLY_PI_PATCH" = true ]; then
      echo ">> [$(date)] Applying the PlayIntegrity patch for $codename" >> "$DEBUG_LOG"
      cd system/core

      git reset --hard
      git clean -q -fd
      wget -q https://git.disroot.org/flame-0/android_vendor_extra/raw/branch/main/patches/system_core/0001-Pass-SafetyNet.patch
      git apply 0001-Pass-SafetyNet.patch &>> "$DEBUG_LOG" || {
        echo ">> [$(date)] Error: Applying the PlayIntegrity patch failed for $codename on $branch!"; userscriptfail=true; continue; }
      cd ../..
    else
      echo ">> [$(date)] Applying PlayIntegrity patch disabled" | tee -a "$repo_log"
    fi

    # Call pre-build.sh
    if [ -f /root/userscripts/pre-build.sh ]; then
      echo ">> [$(date)] Running pre-build.sh for $codename" >> "$DEBUG_LOG"
      /root/userscripts/pre-build.sh "$codename" "$branch" &>> "$DEBUG_LOG" || {
        echo ">> [$(date)] Error: pre-build.sh failed for $codename on $branch!"; userscriptfail=true; continue; }
    fi

    # Call mka
    build_successful=true
    if [ "$CALL_MKA" = true ]; then
      # Start the build
      echo ">> [$(date)] Starting build for $codename, $branch branch" | tee -a "$DEBUG_LOG"
      build_successful=false
      files_to_hash=()

      if (set +eu ; mka "${jobs_arg[@]}" target-files-package bacon) &>> "$DEBUG_LOG"; then
        echo ">> [$(date)] Moving build artifacts for $codename to '$ZIP_DIR/$zipsubdir'" | tee -a "$DEBUG_LOG"

        # Move the ROM zip files to the main OUT directory
        cd out/target/product/"$codename"
        files_to_hash=()
        for build in lineage-*.zip; do
          cp -v system/build.prop "$ZIP_DIR/$zipsubdir/$build.prop" &>> "$DEBUG_LOG"
          mv "$build" "$ZIP_DIR/$zipsubdir/" &>> "$DEBUG_LOG"
          files_to_hash+=( "$build" )
        done

        # Now handle the .img files - where are they?
        img_dir=$(find "$source_dir/out/target/product/$codename/obj/PACKAGING" -name "IMAGES")
        if [ -d "$img_dir" ]; then
          cd "$img_dir"
        fi

        # rename and copy the images to the zips directory
        for image in recovery boot vendor_boot dtbo super_empty vbmeta vendor_kernel_boot init_boot; do
          if [ -f "$image.img" ]; then
            recovery_name="lineage-$los_ver-$builddate-$RELEASE_TYPE-$codename-$image.img"
            echo ">> [$(date)] Copying $image.img" to "$ZIP_DIR/$zipsubdir/$recovery_name" >> "$DEBUG_LOG"
            cp "$image.img" "$ZIP_DIR/$zipsubdir/$recovery_name" &>> "$DEBUG_LOG"
            files_to_hash+=( "$recovery_name" )
          fi
        done

        # create the checksum files
        cd "$ZIP_DIR/$zipsubdir"
        for f in "${files_to_hash[@]}"; do
          sha256sum "$f" > "$ZIP_DIR/$zipsubdir/$f.sha256sum"
        done
        cd "$source_dir"
        build_successful=true
      else
        echo ">> [$(date)] Failed build for $codename" | tee -a "$DEBUG_LOG"
      fi

      # Remove old zips and logs
      if [ "$DELETE_OLD_ZIPS" -gt "0" ]; then
        if [ "$ZIP_SUBDIR" = true ]; then
          /usr/bin/python /root/clean_up.py -n "$DELETE_OLD_ZIPS" -V "$los_ver" -N 1 "$ZIP_DIR/$zipsubdir"
        else
          /usr/bin/python /root/clean_up.py -n "$DELETE_OLD_ZIPS" -V "$los_ver" -N 1 -c "$codename" "$ZIP_DIR"
        fi
      fi
      if [ "$DELETE_OLD_LOGS" -gt "0" ]; then
        if [ "$LOGS_SUBDIR" = true ]; then
          /usr/bin/python /root/clean_up.py -n "$DELETE_OLD_LOGS" -V "$los_ver" -N 1 "$LOGS_DIR/$logsubdir"
        else
          /usr/bin/python /root/clean_up.py -n "$DELETE_OLD_LOGS" -V "$los_ver" -N 1 -c "$codename" "$LOGS_DIR"
        fi
      fi
    else
      echo ">> [$(date)] Calling mka for $codename, $branch branch disabled"
    fi

    # call post-build.sh
    if [ -f /root/userscripts/post-build.sh ]; then
      echo ">> [$(date)] Running post-build.sh for $codename" >> "$DEBUG_LOG"
      /root/userscripts/post-build.sh "$codename" "$build_successful" "$branch" &>> "$DEBUG_LOG" || {
        echo ">> [$(date)] Error: post-build.sh failed for $codename on $branch!"; userscriptfail=true; }
    fi
    echo ">> [$(date)] Finishing build for $codename" | tee -a "$DEBUG_LOG"

    do_cleanup
    if [ "$userscriptfail" = true ]; then
      echo ">> [$(date)] One or more userscripts failed!"
      exit 1
    fi
  fi
done

if [ -f /root/userscripts/end.sh ]; then
  echo ">> [$(date)] Running end.sh"
  /root/userscripts/end.sh || echo ">> [$(date)] Error: end.sh failed!"
fi
