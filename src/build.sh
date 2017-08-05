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

DOCKER_LOG=/var/log/docker.log
DEBUG_LOG=/dev/null
if [ "$DEBUG" = true ]; then
  DEBUG_LOG=$DOCKER_LOG
fi

if ! [ -z "$DEVICE_LIST" ]; then

  # cd to working directory
  cd $SRC_DIR

  # If the source directory is empty
  if ! [ "$(ls -A $SRC_DIR)" ]; then
    # Initialize repository
    echo ">> [$(date)] Initializing repository" >> $DOCKER_LOG
    yes | repo init -u https://github.com/lineageos/android.git -b $BRANCH_NAME 2>&1 >&$DEBUG_LOG
  fi

  # Copy local manifests to the appropriate folder in order take them into consideration
  echo ">> [$(date)] Copying '$LMANIFEST_DIR/*.xml' to '$SRC_DIR/.repo/local_manifests/'" >> $DOCKER_LOG
  cp $LMANIFEST_DIR/*.xml $SRC_DIR/.repo/local_manifests/ >&$DEBUG_LOG

  # Reset the current git status of "vendor/cm" (remove previous changes) if the directory exists
  if [ -d "vendor/cm" ]; then
    cd vendor/cm
    git reset --hard 2>&1 >&$DEBUG_LOG
    cd $SRC_DIR
  fi

  # Reset the current git status of "frameworks/base" (remove previous changes) if the directory exists
  if [ -d "frameworks/base" ]; then
    cd frameworks/base
    git reset --hard 2>&1 >&$DEBUG_LOG
    cd $SRC_DIR
  fi

  # Sync the source code
  echo ">> [$(date)] Syncing repository" >> $DOCKER_LOG
  builddate=$(date +%Y%m%d)
  repo sync 2>&1 >&$DEBUG_LOG

  # If needed, apply the MicroG's signature spoofing patch
  if [ "$SIGNATURE_SPOOFING" = "yes" ] || [ "$SIGNATURE_SPOOFING" = "restricted" ]; then
    # Determine which patch should be applied to the current branch
    patch_name=""
    git_branch=$(repo --no-pager info 2> /dev/null | grep -i "Manifest branch: ")
    git_branch=${git_branch#Manifest branch: }
    case $(echo $git_branch | grep -o "cm-[0-9][0-9]*\.[0-9]") in
      "cm-11.0")            patch_name="android_frameworks_base-KK-LP.patch" ;;
      "cm-12.0"|"cm-12.1")  patch_name="android_frameworks_base-KK-LP.patch" ;;
      "cm-13.0")            patch_name="android_frameworks_base-M.patch" ;;
      "cm-14.0"|"cm-14.1")  patch_name="android_frameworks_base-N.patch" ;;
    esac

    if ! [ -z $patch_name ]; then
      cd frameworks/base
      if [ "$SIGNATURE_SPOOFING" = "yes" ]; then
        echo ">> [$(date)] Applying the standard signature spoofing patch ($patch_name) to frameworks/base" >> $DOCKER_LOG
        echo ">> [$(date)] WARNING: the standard signature spoofing patch introduces a security threat" >> $DOCKER_LOG
        patch -p1 -i "/root/signature_spoofing_patches/$patch_name"
      else
        echo ">> [$(date)] Applying the restricted signature spoofing patch (based on $patch_name) to frameworks/base" >> $DOCKER_LOG
        sed 's/android:protectionLevel="dangerous"/android:protectionLevel="signature|privileged"/' "/root/signature_spoofing_patches/$patch_name" | patch -p1
      fi
      git clean -f
    else
      echo ">> [$(date)] ERROR: can't find a suitable signature spoofing patch for the current LineageOS branch ($git_branch)" >> $DOCKER_LOG
      exit 1
    fi
  fi
  cd $SRC_DIR

  # If requested, clean the OUT dir in order to avoid clutter
  if [ "$CLEAN_OUTDIR" = true ]; then
    echo ">> [$(date)] Cleaning '$ZIP_DIR'" >> $DOCKER_LOG
    cd $ZIP_DIR
    rm *
    cd $SRC_DIR
  fi

  # Prepare the environment
  echo ">> [$(date)] Preparing build environment" >> $DOCKER_LOG
  source build/envsetup.sh 2>&1 >&$DEBUG_LOG

  echo ">> [$(date)] Setting \"$RELEASE_TYPE\" as release type" >> $DOCKER_LOG
  sed -i '/#.*Filter out random types/d' vendor/cm/config/common.mk
  sed -i '/$(filter .*$(CM_BUILDTYPE)/,+3d' vendor/cm/config/common.mk

  # Set a custom updater URI if a OTA URL is provided
  if ! [ -z "$OTA_URL" ]; then
    echo ">> [$(date)] Adding OTA URL '$OTA_URL' to build.prop" >> $DOCKER_LOG
    sed -i "1s;^;PRODUCT_PROPERTY_OVERRIDES += cm.updater.uri=$OTA_URL\n\n;" vendor/cm/config/common.mk >&$DEBUG_LOG
  fi

  # Add custom packages to be installed
  if ! [ -z "$CUSTOM_PACKAGES" ]; then
    echo ">> [$(date)] Adding custom packages ($CUSTOM_PACKAGES)" >> $DOCKER_LOG
    sed -i "1s;^;PRODUCT_PACKAGES += $CUSTOM_PACKAGES\n\n;" vendor/cm/config/common.mk
  fi

  if [ "$SIGN_BUILDS" = true ]; then
    echo ">> [$(date)] Adding keys path ($KEYS_DIR)" >> $DOCKER_LOG
    sed -i "1s;^;PRODUCT_DEFAULT_DEV_CERTIFICATE := $KEYS_DIR/releasekey\nPRODUCT_OTA_PUBLIC_KEYS := $KEYS_DIR/releasekey\nPRODUCT_EXTRA_RECOVERY_KEYS := $KEYS_DIR/releasekey\n\n;" vendor/cm/config/common.mk
  fi

  # Cycle DEVICE_LIST environment variable, to know which one may be executed next
  IFS=','
  for codename in $DEVICE_LIST; do
    currentdate=$(date +%Y%m%d)
    if [ "$builddate" != "$currentdate" ]; then
      # Sync the source code
      echo ">> [$(date)] Syncing repository" >> $DOCKER_LOG
      builddate=$currentdate
      repo sync 2>&1 >&$DEBUG_LOG
    fi

    if ! [ -z "$codename" ]; then
      if [ "$ZIP_SUBDIR" = true ]; then
        zipsubdir=$codename
        mkdir -p $ZIP_DIR/$zipsubdir
      else
        zipsubdir=
      fi
      # Start the build
      echo ">> [$(date)] Starting build for $codename" >> $DOCKER_LOG
      if brunch $codename 2>&1 >&$DEBUG_LOG; then
        currentdate=$(date +%Y%m%d)
        if [ "$builddate" != "$currentdate" ]; then
          find out/target/product/$codename -name "lineage-*-$currentdate-*.zip*" -exec sh /root/fix_build_date.sh {} $currentdate $builddate \;
        fi

        if [ "$BUILD_DELTA" = true ]; then
          if [ -d "$SRC_DIR/delta_last/$codename/" ]; then
            # If not the first build, create delta files
            echo ">> [$(date)] Generating delta files for $codename" >> $DOCKER_LOG
            cd /root/delta
            if ./opendelta.sh $codename >&$DEBUG_LOG; then
              echo ">> [$(date)] Delta generation for $codename completed" >> $DOCKER_LOG
            else
              echo ">> [$(date)] Delta generation for $codename failed" >> $DOCKER_LOG
            fi
            if [ "$DELETE_OLD_DELTAS" -gt "0" ]; then
              /usr/bin/python /root/clean_up.py -n $DELETE_OLD_DELTAS $DELTA_DIR
            fi
          else
            # If the first build, copy the current full zip in $SRC_DIR/delta_last/$codename/
            echo ">> [$(date)] No previous build for $codename; using current build as base for the next delta" >> $DOCKER_LOG
            mkdir -p $SRC_DIR/delta_last/$codename/
            find out/target/product/$codename -name 'lineage-*.zip' -exec cp {} $SRC_DIR/delta_last/$codename/ \;
          fi
        fi
        # Move produced ZIP files to the main OUT directory
        echo ">> [$(date)] Moving build artifacts for $codename to '$ZIP_DIR/$zipsubdir'" >> $DOCKER_LOG
        cd $SRC_DIR
        find out/target/product/$codename -name 'lineage-*.zip*' -exec mv {} $ZIP_DIR/$zipsubdir/ \; >&$DEBUG_LOG
        if [ "$DELETE_OLD_ZIPS" -gt "0" ]; then
          /usr/bin/python /root/clean_up.py -n $DELETE_OLD_ZIPS $ZIP_DIR
        fi
      else
        echo ">> [$(date)] Failed build for $codename" >> $DOCKER_LOG
      fi
      # Clean everything, in order to start fresh on next build
      if [ "$CLEAN_AFTER_BUILD" = true ]; then
        echo ">> [$(date)] Cleaning build for $codename" >> $DOCKER_LOG
        rm -rf $SRC_DIR/out/target/product/$codename/
      fi
      echo ">> [$(date)] Finishing build for $codename" >> $DOCKER_LOG
    fi
  done

  # Create the OpenDelta's builds JSON file
  if ! [ -z "$OPENDELTA_BUILDS_JSON" ]; then
    echo ">> [$(date)] Creating OpenDelta's builds JSON file (ZIP_DIR/$OPENDELTA_BUILDS_JSON)" >> $DOCKER_LOG
    if [ "$ZIP_SUBDIR" != true ]; then
      echo ">> [$(date)] WARNING: OpenDelta requires zip builds separated per device! You should set ZIP_SUBDIR to true" >> $DOCKER_LOG
    fi
    /usr/bin/python /root/opendelta_builds_json.py $ZIP_DIR -o $ZIP_DIR/$OPENDELTA_BUILDS_JSON
  fi

  # Clean the src directory if requested
  if [ "$CLEAN_SRCDIR" = true ]; then
    rm -Rf "$SRC_DIR/*"
  fi
fi
