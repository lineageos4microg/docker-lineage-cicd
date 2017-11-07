FROM ubuntu:16.04
MAINTAINER Nicola Corna <nicola@corna.info>

# Environment variables
#######################

ENV SRC_DIR /srv/src
ENV CCACHE_DIR /srv/ccache
ENV ZIP_DIR /srv/zips
ENV LMANIFEST_DIR /srv/local_manifests
ENV DELTA_DIR /srv/delta
ENV KEYS_DIR /srv/keys
ENV LOGS_DIR /srv/logs
ENV USERSCRIPTS_DIR /srv/userscripts

ENV DEBIAN_FRONTEND noninteractive
ENV USER root

# Configurable environment variables
####################################

# By default we want to use CCACHE, you can disable this
# WARNING: disabling this may slow down a lot your builds!
ENV USE_CCACHE 1

# ccache maximum size. It should be a number followed by an optional suffix: k,
# M, G, T (decimal), Ki, Mi, Gi or Ti (binary). The default suffix is G. Use 0
# for no limit.
ENV CCACHE_SIZE 50G

# Environment for the LineageOS Branch name
# See https://github.com/LineageOS/android_vendor_cm/branches for possible options
ENV BRANCH_NAME 'cm-14.1'

# Environment for the device list (separate by comma if more than one)
# eg. DEVICE_LIST=hammerhead,bullhead,angler
ENV DEVICE_LIST ''

# Release type string
ENV RELEASE_TYPE 'UNOFFICIAL'

# OTA build.prop key that will be used inside Updater/CMUpdater
# This should be set to 'cm.updater.uri. for LineageOS/Cyanogenmod <= 14.1 and
# to 'lineage.updater.uri' for LineageOS >= 15.0
ENV OTA_PROP 'cm.updater.uri'

# OTA URL that will be used inside CMUpdater
# Use this in combination with LineageOTA to make sure your device can auto-update itself from this buildbot
ENV OTA_URL ''

# User identity
ENV USER_NAME 'LineageOS Buildbot'
ENV USER_MAIL 'lineageos-buildbot@docker.host'

# If you want to start always fresh (re-download all the source code everytime) set this to 'true'
ENV CLEAN_SRCDIR false

# If you want to preserve old ZIPs set this to 'false'
ENV CLEAN_OUTDIR false

# Change this cron rule to what fits best for you
# Use 'now' to start the build immediately
# For example, '0 10 * * *' means 'Every day at 10:00 UTC'
ENV CRONTAB_TIME 'now'

# Clean artifacts output after each build
ENV CLEAN_AFTER_BUILD true

# Provide root capabilities builtin inside the ROM (see http://lineageos.org/Update-and-Build-Prep/)
ENV WITH_SU false

# Provide a default JACK configuration in order to avoid out-of-memory issues
ENV ANDROID_JACK_VM_ARGS "-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx4G"

# Custom packages to be installed
ENV CUSTOM_PACKAGES ''

# Key path (from the root of the android source)
ENV SIGN_BUILDS false

# Move the resulting zips to $ZIP_DIR/$codename instead of $ZIP_DIR/
ENV ZIP_SUBDIR true

# Write the verbose logs to $LOGS_DIR/$codename instead of $LOGS_DIR/
ENV LOGS_SUBDIR true

# Apply the MicroG's signature spoofing patch
# Valid values are "no", "yes" (for the original MicroG's patch) and
# "restricted" (to grant the permission only to the system privileged apps).
#
# The original ("yes") patch allows user apps to gain the ability to spoof
# themselves as other apps, which can be a major security threat. Using the
# restricted patch and embedding the apps that requires it as system privileged
# apps is a much secure option. See the README.md ("Custom mode") for an
# example.
ENV SIGNATURE_SPOOFING "no"

# Generate delta files
ENV BUILD_DELTA false

# Delete old zips in $ZIP_DIR, keep only the N latest one (0 to disable)
ENV DELETE_OLD_ZIPS 0

# Delete old deltas in $DELTA_DIR, keep only the N latest one (0 to disable)
ENV DELETE_OLD_DELTAS 0

# Delete old logs in $LOGS_DIR, keep only the N latest one (0 to disable)
ENV DELETE_OLD_LOGS 0

# Create a JSON file that indexes the build zips at the end of the build process
# (for the updates in OpenDelta). The file will be created in $ZIP_DIR with the
# specified name; leave empty to skip it.
# Requires ZIP_SUBDIR.
ENV OPENDELTA_BUILDS_JSON ''

# You can optionally specify a USERSCRIPTS_DIR volume containing these scripts:
#  * begin.sh, run at the very beginning
#  * before.sh, run after the syncing and patching, before starting the builds
#  * pre-build.sh, run before the build of every device 
#  * post-build.sh, run after the build of every device
#  * end.sh, run at the very end
# Each script will be run in $SRC_DIR and must be owned and writeable only by
# root

# Create Volume entry points
############################
VOLUME $SRC_DIR
VOLUME $CCACHE_DIR
VOLUME $ZIP_DIR
VOLUME $LMANIFEST_DIR
VOLUME $DELTA_DIR
VOLUME $KEYS_DIR
VOLUME $LOGS_DIR
VOLUME $USERSCRIPTS_DIR

# Copy required files
#####################
COPY src/ /root/

# Create missing directories
############################
RUN mkdir -p $SRC_DIR
RUN mkdir -p $CCACHE_DIR
RUN mkdir -p $ZIP_DIR
RUN mkdir -p $LMANIFEST_DIR
RUN mkdir -p $DELTA_DIR
RUN mkdir -p $KEYS_DIR
RUN mkdir -p $LOGS_DIR
RUN mkdir -p $USERSCRIPTS_DIR

# Install build dependencies
############################
RUN apt-get -qq update
RUN apt-get -qqy upgrade

RUN apt-get install -y bc bison build-essential ccache cron curl flex \
      g++-multilib gcc-multilib git gnupg gperf imagemagick lib32ncurses5-dev \
      lib32readline6-dev lib32z1-dev libesd0-dev liblz4-tool libncurses5-dev \
      libsdl1.2-dev libssl-dev libwxgtk3.0-dev libxml2 libxml2-utils lzop \
      maven openjdk-8-jdk pngcrush rsync schedtool squashfs-tools wget xdelta3 \
      xsltproc zip zlib1g-dev

RUN curl https://storage.googleapis.com/git-repo-downloads/repo > /usr/local/bin/repo
RUN chmod a+x /usr/local/bin/repo

# Download and build delta tools
################################
RUN cd /root/ && \
        mkdir delta && \
        git clone --depth=1 https://github.com/omnirom/android_packages_apps_OpenDelta.git OpenDelta && \
        gcc -o delta/zipadjust OpenDelta/jni/zipadjust.c OpenDelta/jni/zipadjust_run.c -lz && \
        cp OpenDelta/server/minsignapk.jar OpenDelta/server/opendelta.sh delta/ && \
        chmod +x delta/opendelta.sh && \
        rm -rf OpenDelta/ && \
        sed -i -e 's|^\s*HOME=.*|HOME=/root|; \
                   s|^\s*BIN_XDELTA=.*|BIN_XDELTA=xdelta3|; \
                   s|^\s*FILE_MATCH=.*|FILE_MATCH=lineage-\*.zip|; \
                   s|^\s*PATH_CURRENT=.*|PATH_CURRENT=$SRC_DIR/out/target/product/$DEVICE|; \
                   s|^\s*PATH_LAST=.*|PATH_LAST=$SRC_DIR/delta_last/$DEVICE|; \
                   s|^\s*KEY_X509=.*|KEY_X509=$KEYS_DIR/releasekey.x509.pem|; \
                   s|^\s*KEY_PK8=.*|KEY_PK8=$KEYS_DIR/releasekey.pk8|; \
                   s|publish|$DELTA_DIR|g' /root/delta/opendelta.sh

# Set the work directory
########################
WORKDIR $SRC_DIR

# Allow redirection of stdout to docker logs
############################################
RUN ln -sf /proc/1/fd/1 /var/log/docker.log

# Set the entry point to init.sh
################################
ENTRYPOINT /root/init.sh
