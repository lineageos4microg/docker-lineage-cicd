#!/bin/bash
#
# Build script
#
###########################################################

if ! [ -z "$DEVICE_LIST" ]; then

  # If the source directory is empty
  if ! [ "$(ls -A $SRC_DIR)" ]; then
    # Initialize repository
    yes | repo init -u git://github.com/lineageos/android.git -b $BRANCH_NAME
  fi

  # If a Custom manifest URL has been specified
  if ! [ -z "$CUSTOM_MANIFEST_URL" ]; then
    wget -O .repo/local_manifests/local_manifest.xml $CUSTOM_MANIFEST_URL
  fi

  # Go to "vendor/cm" and reset it's current git status ( remove previous changes ) only if the directory exists
  if [ -d "vendor/cm" ]; then
    cd vendor/cm
    git reset --hard
    cd $SRC_DIR
  fi

  # Sync the source code
  repo sync

  # If requested, clean the OUT dir in order to avoid clutter
  if [ "$CLEAN_OUTDIR" = true ]; then
    rm -Rf "$OUT_DIR/*"
  fi

  # Prepare the environment
  source build/envsetup.sh

  # Set a custom updater URI if a OTA URL is provided
  if ! [ -z "$OTA_URL" ]; then
    sed -i "1s;^;ADDITIONAL_DEFAULT_PROPERTIES += cm.updater.uri=$OTA_URL\n\n;" vendor/cm/config/common.mk
  fi

  # Cycle DEVICE_LIST environment variable, to know which one may be executed next
  IFS=','
  for codename in $DEVICE_LIST; do
    if ! [ -z "$codename" ]; then
      # Start the build
      brunch $codename

      # Move produced ZIP files to the main OUT directory
      find out/target/product/$codename/ -name '*UNOFFICIAL*.zip*' -exec mv {} $OUT_DIR \;

      # Clean everything, in order to start fresh on next build
      cd $SRC_DIR
      make clean
    fi
  done

  # Clean the src directory if requested
  if [ "$CLEAN_SRCDIR" = true ]; then
    rm -Rf "$SRC_DIR/*"
  fi
fi