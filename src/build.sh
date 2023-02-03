#!/bin/bash

# Docker build script
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

repo_log="$LOGS_DIR/repo-$(date +%Y%m%d).log"

# cd to working directory
cd "$SRC_DIR"

if [ -f /root/userscripts/begin.sh ]; then
  echo ">> [$(date)] Running begin.sh"
  /root/userscripts/begin.sh || echo ">> [$(date)] Warning: begin.sh failed!"
fi

# If requested, clean the OUT dir in order to avoid clutter
if [ "$CLEAN_OUTDIR" = true ]; then
  echo ">> [$(date)] Cleaning '$ZIP_DIR'"
  rm -rf "${ZIP_DIR:?}/"*
fi

# Treat DEVICE_LIST as DEVICE_LIST_<first_branch>
first_branch=$(cut -d ',' -f 1 <<< "$BRANCH_NAME")
if [ -n "$DEVICE_LIST" ]; then
  device_list_first_branch="DEVICE_LIST_${first_branch//[^[:alnum:]]/_}"
  device_list_first_branch=${device_list_first_branch^^}
  read -r "${device_list_first_branch?}" <<< "$DEVICE_LIST,${!device_list_first_branch:-}"
fi

# If needed, migrate from the old SRC_DIR structure
if [ -d "$SRC_DIR/.repo" ]; then
  branch_dir=$(repo info -o | sed -ne 's/Manifest branch: refs\/heads\///p' | sed 's/[^[:alnum:]]/_/g')
  branch_dir=${branch_dir^^}
  echo ">> [$(date)] WARNING: old source dir detected, moving source from \"\$SRC_DIR\" to \"\$SRC_DIR/$branch_dir\""
  if [ -d "$branch_dir" ] && [ -z "$(ls -A "$branch_dir")" ]; then
    echo ">> [$(date)] ERROR: $branch_dir already exists and is not empty; aborting"
  fi
  mkdir -p "$branch_dir"
  find . -maxdepth 1 ! -name "$branch_dir" ! -path . -exec mv {} "$branch_dir" \;
fi


jobs_arg=()
if [ -n "${PARALLEL_JOBS-}" ]; then
  if [[ "$PARALLEL_JOBS" =~ ^[1-9][0-9]*$ ]]; then
    jobs_arg+=( "-j$PARALLEL_JOBS" )
  else
    echo "PARALLEL_JOBS is not a positive number: $PARALLEL_JOBS"
    exit 1
  fi
fi


if [ "$LOCAL_MIRROR" = true ]; then

  cd "$MIRROR_DIR"

  if [ ! -d .repo ]; then
    echo ">> [$(date)] Initializing mirror repository" | tee -a "$repo_log"
    ( yes||: ) | repo init -u https://github.com/LineageOS/mirror --mirror --no-clone-bundle -p linux &>> "$repo_log"
  fi

  # Copy local manifests to the appropriate folder in order take them into consideration
  echo ">> [$(date)] Copying '$LMANIFEST_DIR/*.xml' to '.repo/local_manifests/'"
  mkdir -p .repo/local_manifests
  rsync -a --delete --include '*.xml' --exclude '*' "$LMANIFEST_DIR/" .repo/local_manifests/

  rm -f .repo/local_manifests/proprietary.xml
  if [ "$INCLUDE_PROPRIETARY" = true ]; then
    wget -q -O .repo/local_manifests/proprietary.xml "https://raw.githubusercontent.com/TheMuppets/manifests/mirror/default.xml"
    /root/build_manifest.py --remote "https://gitlab.com" --remotename "gitlab_https" \
      "https://gitlab.com/the-muppets/manifest/raw/mirror/default.xml" .repo/local_manifests/proprietary_gitlab.xml
  fi

  echo ">> [$(date)] Syncing mirror repository" | tee -a "$repo_log"
  repo sync "${jobs_arg[@]}" --force-sync --no-clone-bundle &>> "$repo_log"
fi

for branch in ${BRANCH_NAME//,/ }; do
  branch_dir=${branch//[^[:alnum:]]/_}
  branch_dir=${branch_dir^^}
  device_list_cur_branch="DEVICE_LIST_$branch_dir"
  devices=${!device_list_cur_branch}

  if [ -n "$branch" ] && [ -n "$devices" ]; then
    vendor=lineage
    apps_permissioncontroller_patch=""
    modules_permission_patch=""
    case "$branch" in
      cm-14.1*)
        vendor="cm"
        themuppets_branch="cm-14.1"
        android_version="7.1.2"
        frameworks_base_patch="android_frameworks_base-N.patch"
        ;;
      lineage-15.1*)
        themuppets_branch="lineage-15.1"
        android_version="8.1"
        frameworks_base_patch="android_frameworks_base-O.patch"
        ;;
      lineage-16.0*)
        themuppets_branch="lineage-16.0"
        android_version="9"
        frameworks_base_patch="android_frameworks_base-P.patch"
        ;;
      lineage-17.1*)
        themuppets_branch="lineage-17.1"
        android_version="10"
        frameworks_base_patch="android_frameworks_base-Q.patch"
        ;;
      lineage-18.1*)
        themuppets_branch="lineage-18.1"
        android_version="11"
        frameworks_base_patch="android_frameworks_base-R.patch"
        apps_permissioncontroller_patch="packages_apps_PermissionController-R.patch"
        ;;
      lineage-19.1*)
        themuppets_branch="lineage-19.1"
        android_version="12"
        frameworks_base_patch="android_frameworks_base-S.patch"
        modules_permission_patch="packages_modules_Permission-S.patch"
        ;;
      lineage-20.0*)
        themuppets_branch="lineage-20.0"
        android_version="13"
        frameworks_base_patch="android_frameworks_base-Android13.patch"
        modules_permission_patch="packages_modules_Permission-Android13.patch"
        ;;
      *)
        echo ">> [$(date)] Building branch $branch is not (yet) suppported"
        exit 1
        ;;
      esac

    android_version_major=$(cut -d '.' -f 1 <<< $android_version)

    mkdir -p "$SRC_DIR/$branch_dir"
    cd "$SRC_DIR/$branch_dir"

    echo ">> [$(date)] Branch:  $branch"
    echo ">> [$(date)] Devices: $devices"

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

    echo ">> [$(date)] (Re)initializing branch repository" | tee -a "$repo_log"
    if [ "$LOCAL_MIRROR" = true ]; then
      ( yes||: ) | repo init -u https://github.com/LineageOS/android.git --reference "$MIRROR_DIR" -b "$branch" &>> "$repo_log"
    else
      ( yes||: ) | repo init -u https://github.com/LineageOS/android.git -b "$branch" &>> "$repo_log"
    fi

    # Copy local manifests to the appropriate folder in order take them into consideration
    echo ">> [$(date)] Copying '$LMANIFEST_DIR/*.xml' to '.repo/local_manifests/'"
    mkdir -p .repo/local_manifests
    rsync -a --delete --include '*.xml' --exclude '*' "$LMANIFEST_DIR/" .repo/local_manifests/

    rm -f .repo/local_manifests/proprietary.xml
    if [ "$INCLUDE_PROPRIETARY" = true ]; then
      wget -q -O .repo/local_manifests/proprietary.xml "https://raw.githubusercontent.com/TheMuppets/manifests/$themuppets_branch/muppets.xml"
      /root/build_manifest.py --remote "https://gitlab.com" --remotename "gitlab_https" \
        "https://gitlab.com/the-muppets/manifest/raw/$themuppets_branch/muppets.xml" .repo/local_manifests/proprietary_gitlab.xml
    fi

    echo ">> [$(date)] Syncing branch repository" | tee -a "$repo_log"
    builddate=$(date +%Y%m%d)
    repo sync "${jobs_arg[@]}" -c --force-sync &>> "$repo_log"

    if [ ! -d "vendor/$vendor" ]; then
      echo ">> [$(date)] Missing \"vendor/$vendor\", aborting"
      exit 1
    fi

    # Set up our overlay
    mkdir -p "vendor/$vendor/overlay/microg/"
    sed -i "1s;^;PRODUCT_PACKAGE_OVERLAYS := vendor/$vendor/overlay/microg\n;" "vendor/$vendor/config/common.mk"

    makefile_containing_version="vendor/$vendor/config/common.mk"
    if [ -f "vendor/$vendor/config/version.mk" ]; then
      makefile_containing_version="vendor/$vendor/config/version.mk"
    fi
    los_ver_major=$(sed -n -e 's/^\s*PRODUCT_VERSION_MAJOR = //p' "$makefile_containing_version")
    los_ver_minor=$(sed -n -e 's/^\s*PRODUCT_VERSION_MINOR = //p' "$makefile_containing_version")
    los_ver="$los_ver_major.$los_ver_minor"

    # If needed, apply the microG's signature spoofing patch
    if [ "$SIGNATURE_SPOOFING" = "yes" ] || [ "$SIGNATURE_SPOOFING" = "restricted" ]; then
      # Determine which patch should be applied to the current Android source tree
      cd frameworks/base
      if [ "$SIGNATURE_SPOOFING" = "yes" ]; then
        echo ">> [$(date)] Applying the standard signature spoofing patch ($frameworks_base_patch) to frameworks/base"
        echo ">> [$(date)] WARNING: the standard signature spoofing patch introduces a security threat"
        patch --quiet --force -p1 -i "/root/signature_spoofing_patches/$frameworks_base_patch"
      else
        echo ">> [$(date)] Applying the restricted signature spoofing patch (based on $frameworks_base_patch) to frameworks/base"
        sed 's/android:protectionLevel="dangerous"/android:protectionLevel="signature|privileged"/' "/root/signature_spoofing_patches/$frameworks_base_patch" | patch --quiet --force -p1
      fi
      git clean -q -f
      cd ../..

      if [ -n "$apps_permissioncontroller_patch" ] && [ "$SIGNATURE_SPOOFING" = "yes" ]; then
        cd packages/apps/PermissionController
        echo ">> [$(date)] Applying the apps/PermissionController patch ($apps_permissioncontroller_patch) to packages/apps/PermissionController"
        patch --quiet --force -p1 -i "/root/signature_spoofing_patches/$apps_permissioncontroller_patch"
        git clean -q -f
        cd ../../..
      fi
      
      if [ -n "$modules_permission_patch" ] && [ "$SIGNATURE_SPOOFING" = "yes" ]; then
        cd packages/modules/Permission
        echo ">> [$(date)] Applying the modules/Permission patch ($modules_permission_patch) to packages/modules/Permission"
        patch --quiet --force -p1 -i "/root/signature_spoofing_patches/$modules_permission_patch"
        git clean -q -f
        cd ../../..
      fi

      # Override device-specific settings for the location providers
      mkdir -p "vendor/$vendor/overlay/microg/frameworks/base/core/res/res/values/"
      cp /root/signature_spoofing_patches/frameworks_base_config.xml "vendor/$vendor/overlay/microg/frameworks/base/core/res/res/values/config.xml"
    fi

    echo ">> [$(date)] Setting \"$RELEASE_TYPE\" as release type"
    sed -i "/\$(filter .*\$(${vendor^^}_BUILDTYPE)/,/endif/d" "$makefile_containing_version"

    # Set a custom updater URI if a OTA URL is provided
    echo ">> [$(date)] Adding OTA URL overlay (for custom URL $OTA_URL)"
    if [ -n "$OTA_URL" ]; then
      updater_url_overlay_dir="vendor/$vendor/overlay/microg/packages/apps/Updater/res/values/"
      mkdir -p "$updater_url_overlay_dir"

      if grep -q updater_server_url packages/apps/Updater/res/values/strings.xml; then
        # "New" updater configuration: full URL (with placeholders {device}, {type} and {incr})
        sed "s|{name}|updater_server_url|g; s|{url}|$OTA_URL/v1/{device}/{type}/{incr}|g" /root/packages_updater_strings.xml > "$updater_url_overlay_dir/strings.xml"
      elif grep -q conf_update_server_url_def packages/apps/Updater/res/values/strings.xml; then
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

    # Prepare the environment
    echo ">> [$(date)] Preparing build environment"
    set +eu
    # shellcheck source=/dev/null
    source build/envsetup.sh > /dev/null
    set -eu

    if [ -f /root/userscripts/before.sh ]; then
      echo ">> [$(date)] Running before.sh"
      /root/userscripts/before.sh || echo ">> [$(date)] Warning: before.sh failed!"
    fi

    for codename in ${devices//,/ }; do
      if [ -n "$codename" ]; then

        if [ "$BUILD_OVERLAY" = true ]; then
          lowerdir=$SRC_DIR/$branch_dir
          upperdir=$TMP_DIR/device
          workdir=$TMP_DIR/workdir
          merged=$TMP_DIR/merged
          mkdir -p "$upperdir" "$workdir" "$merged"
          mount -t overlay overlay -o lowerdir="$lowerdir",upperdir="$upperdir",workdir="$workdir" "$merged"
          source_dir="$TMP_DIR/merged"
        else
          source_dir="$SRC_DIR/$branch_dir"
        fi
        cd "$source_dir"

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

        DEBUG_LOG="$LOGS_DIR/$logsubdir/lineage-$los_ver-$builddate-$RELEASE_TYPE-$codename.log"

        set +eu
        breakfast "$codename" "$BUILD_TYPE" &>> "$DEBUG_LOG"
        breakfast_returncode=$?
        set -eu
        if [ $breakfast_returncode -ne 0 ]; then
            echo ">> [$(date)] breakfast failed for $codename, $branch branch" | tee -a "$DEBUG_LOG"
            continue
        fi

        if [ -f /root/userscripts/pre-build.sh ]; then
          echo ">> [$(date)] Running pre-build.sh for $codename" >> "$DEBUG_LOG"
          /root/userscripts/pre-build.sh "$codename" &>> "$DEBUG_LOG" || echo ">> [$(date)] Warning: pre-build.sh failed!"
        fi

        # Start the build
        echo ">> [$(date)] Starting build for $codename, $branch branch" | tee -a "$DEBUG_LOG"
        build_successful=false
        if (set +eu ; mka "${jobs_arg[@]}" bacon) &>> "$DEBUG_LOG"; then

          # Move produced ZIP files to the main OUT directory
          echo ">> [$(date)] Moving build artifacts for $codename to '$ZIP_DIR/$zipsubdir'" | tee -a "$DEBUG_LOG"
          cd out/target/product/"$codename"
          files_to_hash=()
          for build in lineage-*.zip; do
            cp -v system/build.prop "$ZIP_DIR/$zipsubdir/$build.prop" &>> "$DEBUG_LOG"
            mv "$build" "$ZIP_DIR/$zipsubdir/" &>> "$DEBUG_LOG"
            files_to_hash+=( "$build" )
          done
          for image in recovery boot vendor_boot; do
            if [ -f "$image.img" ]; then
              recovery_name="lineage-$los_ver-$builddate-$RELEASE_TYPE-$codename-$image.img"
              cp "$image.img" "$ZIP_DIR/$zipsubdir/$recovery_name" &>> "$DEBUG_LOG"
              files_to_hash+=( "$recovery_name" )
            fi
          done
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
        if [ -f /root/userscripts/post-build.sh ]; then
          echo ">> [$(date)] Running post-build.sh for $codename" >> "$DEBUG_LOG"
          /root/userscripts/post-build.sh "$codename" $build_successful &>> "$DEBUG_LOG" || echo ">> [$(date)] Warning: post-build.sh failed!"
        fi
        echo ">> [$(date)] Finishing build for $codename" | tee -a "$DEBUG_LOG"

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

      fi
    done

  fi
done

if [ "$DELETE_OLD_LOGS" -gt "0" ]; then
  find "$LOGS_DIR" -maxdepth 1 -name 'repo-*.log' | sort | head -n -"$DELETE_OLD_LOGS" | xargs -r rm || true
fi

if [ -f /root/userscripts/end.sh ]; then
  echo ">> [$(date)] Running end.sh"
  /root/userscripts/end.sh || echo ">> [$(date)] Warning: end.sh failed!"
fi
