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
    yes | repo init -u https://github.com/lineageos/android.git -b $BRANCH_NAME 2>&1 >&$DEBUG_LOG
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

  # If not yet done, apply the MicroG's signature spoofing patch
  cd frameworks/base
  if [ $(git rev-parse --abbrev-ref HEAD) != "signature_spoofing" ]; then
    echo ">> [$(date)] Applying signature spoofing patch to frameworks/base" >> $DOCKER_LOG
    repo start signature_spoofing
    wget -qO- https://raw.githubusercontent.com/microg/android_packages_apps_GmsCore/master/patches/android_frameworks_base-N.patch | patch -p1
    git clean -f
    git add .
    git commit -m "Add signature spoofing patch"
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

  # Set a custom updater URI if a OTA URL is provided
  if ! [ -z "$OTA_URL" ]; then
    echo ">> [$(date)] Adding OTA URL '$OTA_URL' to build.prop" >> $DOCKER_LOG
    sed -i "1s;^;PRODUCT_PROPERTY_OVERRIDES += cm.updater.uri=$OTA_URL\n\n;" vendor/cm/config/common.mk >&$DEBUG_LOG
  fi

  # Add custom packages to be installed
  if ! [ -z "$CUSTOM_PACKAGES" ]; then
    echo ">> [$(date)] Adding custom packages ($CUSTOM_PACKAGES)" >> $DOCKER_LOG
    echo "PRODUCT_PACKAGES += $CUSTOM_PACKAGES" >> vendor/cm/config/common.mk
  fi

  # Add custom static Java libraries to be installed
  if ! [ -z "$CUSTOM_STATIC_JAVA_LIBRARY" ]; then
    echo ">> [$(date)] Adding custom static Java libraries ($CUSTOM_STATIC_JAVA_LIBRARY)" >> $DOCKER_LOG
    echo "LOCAL_STATIC_JAVA_LIBRARIES += $CUSTOM_STATIC_JAVA_LIBRARY" >> vendor/cm/config/common.mk
  fi

  # Add keys
  if ! [ -z "$RELEASEKEY_PATH" ]; then
    echo ">> [$(date)] Adding keys path ($SRC_DIR/$RELEASEKEY_PATH)" >> $DOCKER_LOG
    echo "PRODUCT_DEFAULT_DEV_CERTIFICATE := $SRC_DIR/$RELEASEKEY_PATH" >> vendor/cm/config/common.mk
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
