#!/bin/bash
#
# Build script
#
###########################################################

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
    yes | repo init -u git://github.com/lineageos/android.git -b $BRANCH_NAME 2>&1 >&$DEBUG_LOG
  fi

  # Copy local manifests to the appropriate folder in order take them into consideration
  echo ">> [$(date)] Copying '$LMANIFEST_DIR/*.xml' to '$SRC_DIR/.repo/local_manifests/'" >> $DOCKER_LOG
  cp $LMANIFEST_DIR/*.xml $SRC_DIR/.repo/local_manifests/ >&$DEBUG_LOG

  # Go to "vendor/cm" and reset it's current git status ( remove previous changes ) only if the directory exists
  if [ -d "vendor/cm" ]; then
    cd vendor/cm
    git reset --hard 2>&1 >&$DEBUG_LOG
    cd $SRC_DIR
  fi

  # Sync the source code
  echo ">> [$(date)] Syncing repository" >> $DOCKER_LOG
  repo sync 2>&1 >&$DEBUG_LOG

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

  # Set a custom updater URI if a OTA URL is provided
  if ! [ -z "$OTA_URL" ]; then
    echo ">> [$(date)] Adding OTA URL '$OTA_URL' to build.prop" >> $DOCKER_LOG
    sed -i "1s;^;PRODUCT_PROPERTY_OVERRIDES += cm.updater.uri=$OTA_URL\n\n;" vendor/cm/config/common.mk >&$DEBUG_LOG
  fi

  # Cycle DEVICE_LIST environment variable, to know which one may be executed next
  IFS=','
  for codename in $DEVICE_LIST; do
    if ! [ -z "$codename" ]; then
      # Start the build
      echo ">> [$(date)] Starting build for $codename" >> $DOCKER_LOG
      if brunch $codename 2>&1 >&$DEBUG_LOG; then
        # Move produced ZIP files to the main OUT directory
        echo ">> [$(date)] Moving build artifacts for $codename to '$ZIP_DIR'" >> $DOCKER_LOG
        cd $SRC_DIR
        find out/target/product/$codename -name '*UNOFFICIAL*.zip*' -exec mv {} $ZIP_DIR \; >&$DEBUG_LOG
      else
        echo ">> [$(date)] Failed build for $codename" >> $DOCKER_LOG
      fi
      # Clean everything, in order to start fresh on next build
      if [ "$CLEAN_AFTER_BUILD" = true ]; then
        echo ">> [$(date)] Cleaning build for $codename" >> $DOCKER_LOG
        make clean 2>&1 >&$DEBUG_LOG
      fi
      echo ">> [$(date)] Finishing build for $codename" >> $DOCKER_LOG
    fi
  done

  # Clean the src directory if requested
  if [ "$CLEAN_SRCDIR" = true ]; then
    rm -Rf "$SRC_DIR/*"
  fi
fi
