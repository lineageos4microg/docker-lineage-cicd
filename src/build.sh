#!/bin/bash

# Docker build script
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

IFS=','
shopt -s dotglob

# cd to working directory
cd "$SRC_DIR"

if [ -f /root/userscripts/begin.sh ]; then
  echo ">> [$(date)] Running begin.sh"
  /root/userscripts/begin.sh
fi

# If requested, clean the OUT dir in order to avoid clutter
if [ "$CLEAN_OUTDIR" = true ]; then
  echo ">> [$(date)] Cleaning '$ZIP_DIR'"
  rm "$ZIP_DIR/*"
fi

# Treat DEVICE_LIST as DEVICE_LIST_<first_branch>
first_branch=$(cut -d ',' -f 1 <<< "$BRANCH_NAME")
if [ ! -z "$DEVICE_LIST" ]; then
  device_list_first_branch="DEVICE_LIST_$(sed 's/[^[:alnum:]]/_/g' <<< $first_branch)"
  device_list_first_branch=${device_list_first_branch^^}
  read $device_list_first_branch <<< "$DEVICE_LIST,${!device_list_first_branch}"
fi

# If needed, migrate from the old SRC_DIR structure
if [ -d "$SRC_DIR/.repo" ]; then
  echo ">> [$(date)] Removing old repository"
  rm -rf "$SRC_DIR/*"
fi

mkdir -p "$TMP_DIR/device"
mkdir -p "$TMP_DIR/workdir"
mkdir -p "$TMP_DIR/merged"

cd "$MIRROR_DIR"

if [ ! -d .repo ]; then
  echo ">> [$(date)] Initializing mirror repository"
  yes | repo init -q -u https://github.com/LineageOS/mirror --mirror --no-clone-bundle -p linux
fi

# Copy local manifests to the appropriate folder in order take them into consideration
echo ">> [$(date)] Copying '$LMANIFEST_DIR/*.xml' to '.repo/local_manifests/'"
mkdir -p .repo/local_manifests
rsync -a --delete --include '*.xml' --exclude '*' "$LMANIFEST_DIR/" .repo/local_manifests/

if [ "$INCLUDE_PROPRIETARY" = true ]; then
  wget -q -O .repo/local_manifests/proprietary.xml "https://raw.githubusercontent.com/TheMuppets/manifests/mirror/default.xml"
fi

echo ">> [$(date)] Syncing mirror repository"
repo sync -q --no-clone-bundle

for branch in $BRANCH_NAME; do
  branch_dir=$(sed 's/[^[:alnum:]]/_/g' <<< $branch)
  branch_dir=${branch_dir^^}
  device_list_cur_branch="DEVICE_LIST_$branch_dir"

  if [ ! -z "$branch" ] && [ ! -z "${!device_list_cur_branch}" ]; then

    mkdir -p "$SRC_DIR/$branch_dir"
    cd "$SRC_DIR/$branch_dir"

    echo ">> [$(date)] Branch:  $branch"
    echo ">> [$(date)] Devices: ${!device_list_cur_branch}"

    # Reset the current git status of "vendor/cm" (remove previous changes) if the directory exists
    if [ -d "vendor/cm" ]; then
      cd vendor/cm
      git reset -q --hard
      cd ../..
    fi

    # Reset the current git status of "frameworks/base" (remove previous changes) if the directory exists
    if [ -d "frameworks/base" ]; then
      cd frameworks/base
      git reset -q --hard
      cd ../..
    fi

    if [ ! -d .repo ]; then
      echo ">> [$(date)] Initializing branch repository"
      yes | repo init -q -u https://github.com/LineageOS/android.git --reference "$MIRROR_DIR" -b "$branch"
    fi

    # Copy local manifests to the appropriate folder in order take them into consideration
    echo ">> [$(date)] Copying '$LMANIFEST_DIR/*.xml' to '.repo/local_manifests/'"
    mkdir -p .repo/local_manifests
    rsync -a --delete --include '*.xml' --exclude '*' "$LMANIFEST_DIR/" .repo/local_manifests/

    if [ "$INCLUDE_PROPRIETARY" = true ]; then
      if [[ $branch =~ .*cm\-13\.0.* ]]; then
        themuppets_branch=cm-13.0
      elif [[ $branch =~ .*cm-14\.1.* ]]; then
        themuppets_branch=cm-14.1
      else
        themuppets_branch=cm-14.1
        echo ">> [$(date)] Can't find a matching branch on github.com/TheMuppets, using $themuppets_branch"
      fi
      wget -q -O .repo/local_manifests/proprietary.xml "https://raw.githubusercontent.com/TheMuppets/manifests/$themuppets_branch/muppets.xml"
    fi

    echo ">> [$(date)] Syncing branch repository"
    builddate=$(date +%Y%m%d)
    repo sync -q -c

    android_version=$(sed -n -e 's/^\s*PLATFORM_VERSION := //p' build/core/version_defaults.mk)
    android_version_major=$(cut -d '.' -f 1 <<< $android_version)

    # If needed, apply the microG's signature spoofing patch
    if [ "$SIGNATURE_SPOOFING" = "yes" ] || [ "$SIGNATURE_SPOOFING" = "restricted" ]; then
      # Determine which patch should be applied to the current Android source tree
      patch_name=""
      case $android_version in
        4.4* )    patch_name="android_frameworks_base-KK-LP.patch" ;;
        5.*  )    patch_name="android_frameworks_base-KK-LP.patch" ;;
        6.*  )    patch_name="android_frameworks_base-M.patch" ;;
        7.*  )    patch_name="android_frameworks_base-N.patch" ;;
      esac

      if ! [ -z $patch_name ]; then
        cd frameworks/base
        if [ "$SIGNATURE_SPOOFING" = "yes" ]; then
          echo ">> [$(date)] Applying the standard signature spoofing patch ($patch_name) to frameworks/base"
          echo ">> [$(date)] WARNING: the standard signature spoofing patch introduces a security threat"
          patch --quiet -p1 -i "/root/signature_spoofing_patches/$patch_name"
        else
          echo ">> [$(date)] Applying the restricted signature spoofing patch (based on $patch_name) to frameworks/base"
          sed 's/android:protectionLevel="dangerous"/android:protectionLevel="signature|privileged"/' "/root/signature_spoofing_patches/$patch_name" | patch --quiet -p1
        fi
        git clean -q -f
        cd ../..
      else
        echo ">> [$(date)] ERROR: can't find a suitable signature spoofing patch for the current Android version ($android_version)"
        exit 1
      fi
    fi

    echo ">> [$(date)] Setting \"$RELEASE_TYPE\" as release type"
    sed -i '/#.*Filter out random types/d' vendor/cm/config/common.mk
    sed -i '/$(filter .*$(CM_BUILDTYPE)/,+3d' vendor/cm/config/common.mk

    # Set a custom updater URI if a OTA URL is provided
    if ! [ -z "$OTA_URL" ]; then
      echo ">> [$(date)] Adding OTA URL '$OTA_URL' to build.prop"
      sed -i "1s;^;PRODUCT_PROPERTY_OVERRIDES += $OTA_PROP=$OTA_URL\n\n;" vendor/cm/config/common.mk
    fi

    # Add custom packages to be installed
    if ! [ -z "$CUSTOM_PACKAGES" ]; then
      echo ">> [$(date)] Adding custom packages ($CUSTOM_PACKAGES)"
      sed -i "1s;^;PRODUCT_PACKAGES += $CUSTOM_PACKAGES\n\n;" vendor/cm/config/common.mk
    fi

    if [ "$SIGN_BUILDS" = true ]; then
      echo ">> [$(date)] Adding keys path ($KEYS_DIR)"
      sed -i "1s;^;PRODUCT_DEFAULT_DEV_CERTIFICATE := $KEYS_DIR/releasekey\nPRODUCT_OTA_PUBLIC_KEYS := $KEYS_DIR/releasekey\nPRODUCT_EXTRA_RECOVERY_KEYS := $KEYS_DIR/releasekey\n\n;" vendor/cm/config/common.mk
    fi

    if [ "$android_version_major" -ge "7" ]; then
      jdk_version=8
    elif [ "$android_version_major" -ge "5" ]; then
      jdk_version=7
    else
      echo ">> [$(date)] ERROR: $branch requires a JDK version too old (< 7); aborting"
      exit 1
    fi

    echo ">> [$(date)] Using OpenJDK $jdk_version"
    update-java-alternatives -s java-1.$jdk_version.0-openjdk-amd64 > /dev/null 2>&1

    # Prepare the environment
    echo ">> [$(date)] Preparing build environment"
    source build/envsetup.sh > /dev/null

    if [ -f /root/userscripts/before.sh ]; then
      echo ">> [$(date)] Running before.sh"
      /root/userscripts/before.sh
    fi

    for codename in ${!device_list_cur_branch}; do
      if ! [ -z "$codename" ]; then

        currentdate=$(date +%Y%m%d)
        if [ "$builddate" != "$currentdate" ]; then
          # Sync the source code
          echo ">> [$(date)] Syncing mirror repository"
          builddate=$currentdate
          cd "$MIRROR_DIR"
          repo sync -q --no-clone-bundle
          echo ">> [$(date)] Syncing branch repository"
          cd "$SRC_DIR/$branch_dir"
          repo sync -q -c
        fi

        mount -t overlay overlay -o lowerdir="$SRC_DIR/$branch_dir",upperdir="$TMP_DIR/device",workdir="$TMP_DIR/workdir" "$TMP_DIR/merged"
        cd "$TMP_DIR/merged"

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
        los_ver_major=$(sed -n -e 's/^\s*PRODUCT_VERSION_MAJOR = //p' vendor/cm/config/common.mk)
        los_ver_minor=$(sed -n -e 's/^\s*PRODUCT_VERSION_MINOR = //p' vendor/cm/config/common.mk)
        DEBUG_LOG="$LOGS_DIR/$logsubdir/lineage-$los_ver_major.$los_ver_minor-$builddate-$RELEASE_TYPE-$codename.log"

        if [ -f /root/userscripts/pre-build.sh ]; then
          echo ">> [$(date)] Running pre-build.sh for $codename" >> "$DEBUG_LOG" 2>&1
          /root/userscripts/pre-build.sh $codename >> "$DEBUG_LOG" 2>&1
        fi

        # Start the build
        echo ">> [$(date)] Starting build for $codename, $branch branch" | tee -a "$DEBUG_LOG"
        build_successful=false
        if brunch $codename >> "$DEBUG_LOG" 2>&1; then
          currentdate=$(date +%Y%m%d)
          if [ "$builddate" != "$currentdate" ]; then
            find out/target/product/$codename -name "lineage-*-$currentdate-*.zip*" -type f -maxdepth 1 -exec sh /root/fix_build_date.sh {} $currentdate $builddate \; >> "$DEBUG_LOG" 2>&1
          fi

          if [ "$BUILD_DELTA" = true ]; then
            if [ -d "delta_last/$codename/" ]; then
              # If not the first build, create delta files
              echo ">> [$(date)] Generating delta files for $codename" | tee -a "$DEBUG_LOG"
              cd /root/delta
              if ./opendelta.sh $codename >> "$DEBUG_LOG" 2>&1; then
                echo ">> [$(date)] Delta generation for $codename completed" | tee -a "$DEBUG_LOG"
              else
                echo ">> [$(date)] Delta generation for $codename failed" | tee -a "$DEBUG_LOG"
              fi
              if [ "$DELETE_OLD_DELTAS" -gt "0" ]; then
                /usr/bin/python /root/clean_up.py -n $DELETE_OLD_DELTAS "$DELTA_DIR" >> "$DEBUG_LOG" 2>&1
              fi
              cd "$TMP_DIR/merged"
            else
              # If the first build, copy the current full zip in $SRC_DIR/merged/delta_last/$codename/
              echo ">> [$(date)] No previous build for $codename; using current build as base for the next delta" | tee -a "$DEBUG_LOG"
              mkdir -p delta_last/$codename/ >> "$DEBUG_LOG" 2>&1
              find out/target/product/$codename -name 'lineage-*.zip' -type f -maxdepth 1 -exec cp {} "$SRC_DIR/merged/delta_last/$codename/" \; >> "$DEBUG_LOG" 2>&1
            fi
          fi
          # Move produced ZIP files to the main OUT directory
          echo ">> [$(date)] Moving build artifacts for $codename to '$ZIP_DIR/$zipsubdir'" | tee -a "$DEBUG_LOG"
          cd out/target/product/$codename
          for build in lineage-*.zip; do
            sha256sum "$build" > "$ZIP_DIR/$zipsubdir/$build.sha256sum"
          done
          find . -name 'lineage-*.zip*' -type f -maxdepth 1 -exec mv {} "$ZIP_DIR/$zipsubdir/" \; >> "$DEBUG_LOG" 2>&1
          cd "$TMP_DIR/merged"
          build_successful=true
        else
          echo ">> [$(date)] Failed build for $codename" | tee -a "$DEBUG_LOG"
        fi

        # Remove old zips and logs
        if [ "$DELETE_OLD_ZIPS" -gt "0" ]; then
          /usr/bin/python /root/clean_up.py -n $DELETE_OLD_ZIPS "$ZIP_DIR"
        fi
        if [ "$DELETE_OLD_LOGS" -gt "0" ]; then
          /usr/bin/python /root/clean_up.py -n $DELETE_OLD_LOGS "$LOGS_DIR"
        fi
        if [ -f /root/userscripts/post-build.sh ]; then
          echo ">> [$(date)] Running post-build.sh for $codename" >> "$DEBUG_LOG" 2>&1
          /root/userscripts/post-build.sh $codename $build_successful >> "$DEBUG_LOG" 2>&1
        fi
        echo ">> [$(date)] Finishing build for $codename" | tee -a "$DEBUG_LOG"

        # The Jack server must be stopped manually, as we want to unmount $TMP_DIR/merged
        cd "$TMP_DIR"
        if [ -f "$TMP_DIR/merged/prebuilts/sdk/tools/jack-admin" ]; then
          "$TMP_DIR/merged/prebuilts/sdk/tools/jack-admin kill-server" > /dev/null 2>&1 || true
        fi
        lsof | grep "$TMP_DIR/merged" | awk '{ print $2 }' | xargs kill

        while [ ! -z "$(lsof | grep $TMP_DIR/merged)" ]; do
          sleep 1
        done

        umount "$TMP_DIR/merged"
        echo ">> [$(date)] Cleaning source dir for device $codename"
        rm -rf device/*

      fi
    done

    # Clean the branch source directory if requested
    if [ "$CLEAN_SRCDIR" = true ]; then
      rm -rf "$SRC_DIR/$branch_dir"
    fi

  fi
done

# Create the OpenDelta's builds JSON file
if ! [ -z "$OPENDELTA_BUILDS_JSON" ]; then
  echo ">> [$(date)] Creating OpenDelta's builds JSON file (ZIP_DIR/$OPENDELTA_BUILDS_JSON)"
  if [ "$ZIP_SUBDIR" != true ]; then
    echo ">> [$(date)] WARNING: OpenDelta requires zip builds separated per device! You should set ZIP_SUBDIR to true"
  fi
  /usr/bin/python /root/opendelta_builds_json.py "$ZIP_DIR" -o "$ZIP_DIR/$OPENDELTA_BUILDS_JSON"
fi

if [ -f /root/userscripts/end.sh ]; then
  echo ">> [$(date)] Running end.sh"
  /root/userscripts/end.sh
fi

