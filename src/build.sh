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
  cd frameworks/base
  if [ "$SIGNATURE_SPOOFING" = "yes" ]; then
    echo ">> [$(date)] Applying the standard signature spoofing patch to frameworks/base" >> $DOCKER_LOG
    patch -p1 -i /root/android_frameworks_base-N.patch
    git clean -f
  elif [ "$SIGNATURE_SPOOFING" = "restricted" ]; then
    echo ">> [$(date)] Applying the restricted signature spoofing patch to frameworks/base" >> $DOCKER_LOG
    sed 's/android:protectionLevel="dangerous"/android:protectionLevel="signature|privileged"/' /root/android_frameworks_base-N.patch | patch -p1 
    git clean -f
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
    sed -i "1s;^;PRODUCT_PACKAGES += $CUSTOM_PACKAGES\n\n;" vendor/cm/config/common.mk
  fi

  # Cycle DEVICE_LIST environment variable, to know which one may be executed next
  IFS=','
  for codename in $DEVICE_LIST; do
    if ! [ -z "$codename" ]; then
      if [ "$ZIP_SUBDIR" = true ]; then
        zipsubdir=$codename
        mkdir -p $ZIP_DIR/$zipsubdir
      else
        zipsubdir=
      fi
      # Start the build
      if [ -z "$KEYS_DIR" ]; then
        echo ">> [$(date)] Starting build for $codename" >> $DOCKER_LOG
        if brunch $codename 2>&1 >&$DEBUG_LOG; then
          # Move produced ZIP files to the main OUT directory
          echo ">> [$(date)] Moving build artifacts for $codename to '$ZIP_DIR/$zipsubdir'" >> $DOCKER_LOG
          cd $SRC_DIR
          find out/target/product/$codename -name '*UNOFFICIAL*.zip*' -exec sh -c 'sha256sum {} > $ZIP_DIR/$zipsubdir/{}.sha256sum && mv {} $ZIP_DIR/$zipsubdir/' \; >&$DEBUG_LOG
        else
          echo ">> [$(date)] Failed build for $codename" >> $DOCKER_LOG
        fi
      else
        echo ">> [$(date)] Starting build for $codename" >> $DOCKER_LOG
        if breakfast $codename 2>&1 >&$DEBUG_LOG && \
             mka target-files-package dist 2>&1 >&$DEBUG_LOG; then
          echo ">> [$(date)] Signing build output for $codename" >> $DOCKER_LOG
          build_number=$(<$SRC_DIR/out/build_number.txt)
          if $SRC_DIR/build/tools/releasetools/sign_target_files_apks -o -d $SRC_DIR/$KEYS_DIR \
               $SRC_DIR/out/dist/lineage_$codename-target_files-$build_number.zip \
               $SRC_DIR/out/dist/lineage_$codename-signed_target_files-$build_number.zip 2>&1 >&$DEBUG_LOG && \
             $SRC_DIR/build/tools/releasetools/ota_from_target_files -k $SRC_DIR/$KEYS_DIR/releasekey --block --backup=true \
               $SRC_DIR/out/dist/lineage_$codename-signed_target_files-$build_number.zip \
               $ZIP_DIR/$zipsubdir/lineage-14.1-$builddate-UNOFFICIAL-$codename-signed.zip 2>&1 >&$DEBUG_LOG; then
            cd $ZIP_DIR/$zipsubdir
            md5sum lineage-14.1-$builddate-UNOFFICIAL-$codename-signed.zip > lineage-14.1-$builddate-UNOFFICIAL-$codename-signed.zip.md5sum
            sha256sum lineage-14.1-$builddate-UNOFFICIAL-$codename-signed.zip > lineage-14.1-$builddate-UNOFFICIAL-$codename-signed.zip.sha256sum
            cd $SRC_DIR
            echo ">> [$(date)] Build completed for $codename" >> $DOCKER_LOG
          else
            echo ">> [$(date)] Failed signing for $codename" >> $DOCKER_LOG
          fi
          rm -f $SRC_DIR/out/dist/lineage_$codename-target_files-$build_number.zip
          rm -f $SRC_DIR/out/dist/lineage_$codename-signed_target_files-$build_number.zip
        else
          echo ">> [$(date)] Failed build for $codename" >> $DOCKER_LOG
        fi
      fi
      # Clean everything, in order to start fresh on next build
      if [ "$CLEAN_AFTER_BUILD" = true ]; then
        echo ">> [$(date)] Cleaning build for $codename" >> $DOCKER_LOG
        rm -rf $SRC_DIR/out/target/product/$codename/
      fi
      echo ">> [$(date)] Finishing build for $codename" >> $DOCKER_LOG
    fi
  done

  # Clean the src directory if requested
  if [ "$CLEAN_SRCDIR" = true ]; then
    rm -Rf "$SRC_DIR/*"
  fi
fi
