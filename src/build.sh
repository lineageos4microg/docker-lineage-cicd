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

retry_fetches_arg=()
if [ -n "${RETRY_FETCHES-}" ]; then
  if [[ "$RETRY_FETCHES" =~ ^[1-9][0-9]*$ ]]; then
    retry_fetches_arg+=( "--retry-fetches=$RETRY_FETCHES" )
  else
    echo "RETRY_FETCHES is not a positive number: $RETRY_FETCHES"
    exit 1
  fi
fi

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

  if [ "$SYNC_MIRROR" = true ]; then
    echo ">> [$(date)] Syncing mirror repository" | tee -a "$repo_log"
    repo sync "${jobs_arg[@]}" --force-sync --no-clone-bundle &>> "$repo_log"
  else
    echo ">> [$(date)] Sync mirror repository disabled" | tee -a "$repo_log"
  fi
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
        user_build_spoofing_patch="android_frameworks_base-user_build.patch"
        ;;
      lineage-19.1*)
        themuppets_branch="lineage-19.1"
        android_version="12"
        frameworks_base_patch="android_frameworks_base-S.patch"
        modules_permission_patch="packages_modules_Permission-S.patch"
        user_build_spoofing_patch="android_frameworks_base-user_build.patch"
        ;;
      lineage-20.0*)
        themuppets_branch="lineage-20.0"
        android_version="13"
        frameworks_base_patch="android_frameworks_base-Android13.patch"
        modules_permission_patch="packages_modules_Permission-Android13.patch"
        user_build_spoofing_patch="android_frameworks_base-user_build.patch"
        ;;
      lineage-21.0*)
        themuppets_branch="lineage-21.0"
        android_version="14"
        frameworks_base_patch="android_frameworks_base-Android14.patch"
        modules_permission_patch="packages_modules_Permission-Android14.patch"
        user_build_spoofing_patch="android_frameworks_base-user_build.patch"
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

    if [ "$CALL_REPO_INIT" = true ]; then
      echo ">> [$(date)] (Re)initializing branch repository" | tee -a "$repo_log"
      if [ "$LOCAL_MIRROR" = true ]; then
        ( yes||: ) | repo init -u https://github.com/LineageOS/android.git --reference "$MIRROR_DIR" -b "$branch" --git-lfs &>> "$repo_log"
      else
        ( yes||: ) | repo init -u https://github.com/LineageOS/android.git -b "$branch" --git-lfs &>> "$repo_log"
      fi
    else
      echo ">> [$(date)] Calling repo init disabled"
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

    builddate=$(date +%Y%m%d)
    if [ "$CALL_REPO_SYNC" = true ]; then
      echo ">> [$(date)] Syncing branch repository" | tee -a "$repo_log"
      repo sync "${jobs_arg[@]}" -c --force-sync &>> "$repo_log"
    else
      echo ">> [$(date)] Syncing branch repository disabled" | tee -a "$repo_log"
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

    patches_applied=false
    if [ "$APPLY_PATCHES" = true ]; then

      if [ "$USER_BUILD_SPOOFING" = "yes" ]; then
        # For user builds, we need to patch the LOS signature spoofing code
        # which were disabled for user builds
        if [ -n "$user_build_spoofing_patch" ]; then
          cd frameworks/base
          echo ">> [$(date)] Applying the user build variant signature spoofing patch ($user_build_spoofing_patch) to frameworks/base"
          patch --quiet --force -p1 -i "/root/signature_spoofing_patches/$user_build_spoofing_patch"
          git clean -q -f
          cd ../..
        else
          echo ">> [$(date)] WARNING: User build signature spoofing requested, but branch ($branch) does not support built-in signature spoofing"
        fi
      fi

      # If needed, apply the microG's signature spoofing patch
      if [ "$SIGNATURE_SPOOFING" = "yes" ] || [ "$SIGNATURE_SPOOFING" = "restricted" ]; then
        patches_applied=true
        if [ -z "$frameworks_base_patch" ]; then
          echo ">> [$(date)] WARNING: Signature spoofing patches requested, but branch ($branch) does not support microG patches"
        else
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
      fi
    else
      echo ">> [$(date)] Applying patches disabled"
    fi

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

    if [ "$PREPARE_BUILD_ENVIRONMENT" = true ]; then
      # Prepare the environment
      echo ">> [$(date)] Preparing build environment"
      set +eu
      # shellcheck source=/dev/null
      source build/envsetup.sh > /dev/null
      set -eu
    else
      echo ">> [$(date)] Preparing build environment disabled"
    fi

    if [ -f /root/userscripts/before.sh ]; then
      echo ">> [$(date)] Running before.sh"
      /root/userscripts/before.sh || echo ">> [$(date)] Warning: before.sh failed!"
    fi

    for codename in ${devices//,/ }; do
      if [ -n "$codename" ]; then

      builddate=$(date +%Y%m%d)

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

        if [ -f /root/userscripts/pre-build.sh ]; then
          echo ">> [$(date)] Running pre-build.sh for $codename" >> "$DEBUG_LOG"
          /root/userscripts/pre-build.sh "$codename" &>> "$DEBUG_LOG" || echo ">> [$(date)] Warning: pre-build.sh failed!"
        fi

        build_successful=true
        if [ "$CALL_MKA" = true ]; then
          if [ "$patches_applied" = true ]; then
            # we changed the api - need to regenerate current.txt
            m api-stubs-docs-non-updatable-update-current-api  &>> "$DEBUG_LOG"
          fi

          # Start the build
          echo ">> [$(date)] Starting build for $codename, $branch branch" | tee -a "$DEBUG_LOG"
          build_successful=false
          files_to_hash=()

          if (set +eu ; brunch "${jobs_arg[@]}" $codename ) &>> "$DEBUG_LOG"; then

            if [ "$MAKE_IMG_ZIP_FILE" = true ]; then
              # make the `-img.zip` file
              echo ">> [$(date)] Making -img.zip file" | tee -a "$DEBUG_LOG"
              infile="out/target/product/$codename/obj/PACKAGING/target_files_intermediates/lineage_$codename-target_files-eng.root.zip"
              img_zip_file="lineage-$los_ver-$builddate-$RELEASE_TYPE-$codename-img.zip"
              img_from_target_files "$infile" "$img_zip_file"  &>> "$DEBUG_LOG"

              # move it to the zips directory
              mv "$img_zip_file" "$ZIP_DIR/$zipsubdir/" &>> "$DEBUG_LOG"
              files_to_hash+=( "$img_zip_file" )
            else
              echo ">> [$(date)] Making -img.zip file disabled"
            fi

          echo ">> [$(date)] Moving build artifacts for $codename to '$ZIP_DIR/$zipsubdir'" | tee -a "$DEBUG_LOG"
          cd out/target/product/"$codename"

          # Move the ROM zip files to the main OUT directory
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

          if [ "$ZIP_UP_IMAGES" = true ]; then
            echo ">> [$(date)] Zipping the .img files" | tee -a "$DEBUG_LOG"

            files_to_zip=()
            images_zip_file="lineage-$los_ver-$builddate-$RELEASE_TYPE-$codename-images.zip"

            for image in recovery boot vendor_boot dtbo super_empty vbmeta vendor_kernel_boot; do
              if [ -f "$image.img" ]; then
                echo ">> [$(date)] Adding $image.img" to "$images_zip_file" | tee -a "$DEBUG_LOG"
                files_to_zip+=( "$image.img" )
              fi
            done

            zip "$images_zip_file" "${files_to_zip[@]}"
            mv "$images_zip_file" "$ZIP_DIR/$zipsubdir/"
            files_to_hash+=( "$images_zip_file" )
          else
            echo ">> [$(date)] Zipping the '-img' files disabled"

            # rename and copy the images to the zips directory
            for image in recovery boot vendor_boot dtbo super_empty vbmeta vendor_kernel_boot; do
              if [ -f "$image.img" ]; then
                recovery_name="lineage-$los_ver-$builddate-$RELEASE_TYPE-$codename-$image.img"
                echo ">> [$(date)] Copying $image.img" to "$ZIP_DIR/$zipsubdir/$recovery_name" >> "$DEBUG_LOG"
                cp "$image.img" "$ZIP_DIR/$zipsubdir/$recovery_name" &>> "$DEBUG_LOG"
                files_to_hash+=( "$recovery_name" )
              fi
            done
          fi

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
        else
          echo ">> [$(date)] Calling mka for $codename, $branch branch disabled"
        fi
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

        # call post-build.sh
        if [ -f /root/userscripts/post-build.sh ]; then
          echo ">> [$(date)] Running post-build.sh for $codename" >> "$DEBUG_LOG"
          /root/userscripts/post-build.sh "$codename" "$build_successful" "$branch" &>> "$DEBUG_LOG" || echo ">> [$(date)] Warning: post-build.sh failed!"
        fi
        echo ">> [$(date)] Finishing build for $codename" | tee -a "$DEBUG_LOG"

        do_cleanup
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
