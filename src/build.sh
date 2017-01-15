#!/bin/bash
#
# Build script
#
###########################################################

if ! [ -z "$DEVICE_LIST" ]; then

  # cd to working directory
  cd $SRC_DIR

  # If the source directory is empty
  if ! [ "$(ls -A $SRC_DIR)" ]; then
    # Initialize repository
    echo "-------- Initializing repository [$(date)] --------"
    yes | repo init -u git://github.com/lineageos/android.git -b $BRANCH_NAME &>/dev/null
  fi

  # Go to "vendor/cm" and reset it's current git status ( remove previous changes ) only if the directory exists
  if [ -d "vendor/cm" ]; then
    cd vendor/cm
    git reset --hard &>/dev/null
    cd $SRC_DIR
  fi

  # Sync the source code
  echo "-------- Syncing repository [$(date)] --------"
  repo sync &>/dev/null

  # If requested, clean the OUT dir in order to avoid clutter
  if [ "$CLEAN_OUTDIR" = true ]; then
    rm -Rf "$OUT_DIR/*"
  fi

  # Prepare the environment
  echo "-------- Preparing build environment [$(date)] --------"
  source build/envsetup.sh &>/dev/null

  # Set a custom updater URI if a OTA URL is provided
  if ! [ -z "$OTA_URL" ]; then
    sed -i "1s;^;ADDITIONAL_DEFAULT_PROPERTIES += cm.updater.uri=$OTA_URL\n\n;" vendor/cm/config/common.mk &>/dev/null
  fi

  # Cycle DEVICE_LIST environment variable, to know which one may be executed next
  IFS=','
  for codename in $DEVICE_LIST; do
    if ! [ -z "$codename" ]; then
      # Start the build
      echo "-------- Starting build for >> $codename << [$(date)] --------"
      brunch $codename &>/dev/null

      # Move produced ZIP files to the main OUT directory
      find out/target/product/$codename/ -name '*UNOFFICIAL*.zip*' -exec mv {} $OUT_DIR \; &>/dev/null

      # Clean everything, in order to start fresh on next build
      cd $SRC_DIR
      make clean &>/dev/null
      echo "-------- Finishing build for >> $codename << [$(date)] --------"
    fi
  done

  # Clean the src directory if requested
  if [ "$CLEAN_SRCDIR" = true ]; then
    rm -Rf "$SRC_DIR/*"
  fi
fi
