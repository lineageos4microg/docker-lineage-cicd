#!/bin/bash
#
# Build script
#
###########################################################

OUTPUT=/dev/null
if [ "$DEBUG" = true ]; then
  OUTPUT=/var/log/docker.log
fi

if ! [ -z "$DEVICE_LIST" ]; then

  # cd to working directory
  cd $SRC_DIR

  # If the source directory is empty
  if ! [ "$(ls -A $SRC_DIR)" ]; then
    # Initialize repository
    echo ">> [$(date)] Initializing repository"
    yes | repo init -u git://github.com/lineageos/android.git -b $BRANCH_NAME 2>&1 >&$OUTPUT
  fi

  # Copy local manifests to the appropriate folder in order take them into consideration
  echo ">> [$(date)] Copying '$LMANIFEST_DIR/*.xml' to '$SRC_DIR/.repo/local_manifests/'"
  cp * $LMANIFEST_DIR/*.xml $SRC_DIR/.repo/local_manifests/

  # Go to "vendor/cm" and reset it's current git status ( remove previous changes ) only if the directory exists
  if [ -d "vendor/cm" ]; then
    cd vendor/cm
    git reset --hard 2>&1 >&$OUTPUT
    cd $SRC_DIR
  fi

  # Sync the source code
  echo ">> [$(date)] Syncing repository"
  repo sync 2>&1 >&$OUTPUT

  # If requested, clean the OUT dir in order to avoid clutter
  if [ "$CLEAN_OUTDIR" = true ]; then
    echo ">> [$(date)] Cleaning '$ZIP_DIR'"
    rm -Rf "$ZIP_DIR/*"
  fi

  # Prepare the environment
  echo ">> [$(date)] Preparing build environment"
  source build/envsetup.sh 2>&1 >&$OUTPUT

  # Set a custom updater URI if a OTA URL is provided
  if ! [ -z "$OTA_URL" ]; then
    echo ">> [$(date)] Adding OTA URL '$OTA_URL' to build.prop"
    sed -i "1s;^;ADDITIONAL_DEFAULT_PROPERTIES += cm.updater.uri=$OTA_URL\n\n;" vendor/cm/config/common.mk
  fi

  # Cycle DEVICE_LIST environment variable, to know which one may be executed next
  IFS=','
  for codename in $DEVICE_LIST; do
    if ! [ -z "$codename" ]; then
      # Start the build
      echo ">> [$(date)] Starting build for $codename"
      if brunch $codename 2>&1 >&$OUTPUT; then
        # Move produced ZIP files to the main OUT directory
        echo ">> [$(date)] Moving build artifacts for $codename to '$ZIP_DIR'"
        cd $SRC_DIR
        find out/target/product/$codename -name '*UNOFFICIAL*.zip*' -exec mv {} $ZIP_DIR \;

        # Clean everything, in order to start fresh on next build
        if [ "$CLEAN_AFTER_BUILD" = true ]; then
          echo ">> [$(date)] Cleaning build for $codename"
          make clean 2>&1 >&$OUTPUT
        fi
      else
        echo ">> [$(date)] Failed build for $codename"
      fi
      echo ">> [$(date)] Finishing build for $codename"
    fi
  done

  # Clean the src directory if requested
  if [ "$CLEAN_SRCDIR" = true ]; then
    rm -Rf "$SRC_DIR/*"
  fi
fi
