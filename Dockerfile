FROM ubuntu:20.04@sha256:669e010b58baf5beb2836b253c1fd5768333f0d1dbcb834f7c07a4dc93f474be
LABEL maintainer="Nicola Corna <nicola@corna.info>"

# Environment variables
#######################

ENV MIRROR_DIR /srv/mirror
ENV SRC_DIR /srv/src
ENV TMP_DIR /srv/tmp
ENV CCACHE_DIR /srv/ccache
ENV ZIP_DIR /srv/zips
ENV LMANIFEST_DIR /srv/local_manifests
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

# We need to specify the ccache binary since it is no longer packaged along with AOSP
ENV CCACHE_EXEC /usr/bin/ccache

# Environment for the LineageOS branches name
# See https://github.com/LineageOS/android/branches for possible options
ENV BRANCH_NAME 'lineage-16.0'

# Environment for the device list (separate by comma if more than one)
# eg. DEVICE_LIST=hammerhead,bullhead,angler
ENV DEVICE_LIST ''

# Release type string
ENV RELEASE_TYPE 'UNOFFICIAL'

# OTA URL that will be used inside CMUpdater
# Use this in combination with LineageOTA to make sure your device can auto-update itself from this buildbot
ENV OTA_URL ''

# User identity
ENV USER_NAME 'LineageOS Buildbot'
ENV USER_MAIL 'lineageos-buildbot@docker.host'

# Include proprietary files, downloaded automatically from github.com/TheMuppets/ and gitlab.com/the-muppets/
# Only some branches are supported
ENV INCLUDE_PROPRIETARY true

# Mount an overlay filesystem over the source dir to do each build on a clean source
ENV BUILD_OVERLAY false

# Clone the full LineageOS mirror (> 200 GB)
ENV LOCAL_MIRROR false

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

# Sign the builds with the keys in $KEYS_DIR
ENV SIGN_BUILDS false

# When SIGN_BUILDS = true but no keys have been provided, generate a new set with this subject
ENV KEYS_SUBJECT '/C=US/ST=California/L=Mountain View/O=Android/OU=Android/CN=Android/emailAddress=android@android.com'

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

# Delete old zips in $ZIP_DIR, keep only the N latest one (0 to disable)
ENV DELETE_OLD_ZIPS 0

# Delete old logs in $LOGS_DIR, keep only the N latest one (0 to disable)
ENV DELETE_OLD_LOGS 0

# build type of your builds (user|userdebug|eng)
ENV BUILD_TYPE "userdebug"

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
VOLUME $MIRROR_DIR
VOLUME $SRC_DIR
VOLUME $TMP_DIR
VOLUME $CCACHE_DIR
VOLUME $ZIP_DIR
VOLUME $LMANIFEST_DIR
VOLUME $KEYS_DIR
VOLUME $LOGS_DIR
VOLUME $USERSCRIPTS_DIR

# Create missing directories
############################
RUN mkdir -p $MIRROR_DIR $SRC_DIR $TMP_DIR $CCACHE_DIR $ZIP_DIR $LMANIFEST_DIR \
      $KEYS_DIR $LOGS_DIR $USERSCRIPTS_DIR

# Install build dependencies
############################
RUN apt-get -qq update && \
      apt-get install -y bc bison bsdmainutils build-essential ccache cgpt clang \
      cron curl flex g++-multilib gcc-multilib git gnupg gperf imagemagick \
      kmod lib32ncurses5-dev lib32readline-dev lib32z1-dev liblz4-tool \
      libncurses5 libncurses5-dev libsdl1.2-dev libssl-dev libxml2 \
      libxml2-utils lsof lzop maven openjdk-8-jdk pngcrush procps \
      python rsync schedtool squashfs-tools wget xdelta3 xsltproc yasm zip \
      zlib1g-dev \
      && rm -rf /var/lib/apt/lists/*

RUN curl https://storage.googleapis.com/git-repo-downloads/repo > /usr/local/bin/repo && \
      chmod a+x /usr/local/bin/repo

# Re-enable TLSv1 and TLSv1.1 in OpenJDK 8 config
#(for cm-14.1/lineage-15.1, might be removed later)
###################################################
RUN echo "jdk.tls.disabledAlgorithms=SSLv3, RC4, DES, MD5withRSA, DH keySize < 1024, EC keySize < 224, 3DES_EDE_CBC, anon, NULL, include jdk.disabled.namedCurves" | tee -a /etc/java-8-openjdk/security/java.security

# Copy required files
#####################
COPY src/ /root/

# Set the work directory
########################
WORKDIR $SRC_DIR

# Allow redirection of stdout to docker logs
############################################
RUN ln -sf /proc/1/fd/1 /var/log/docker.log

# Set the entry point to init.sh
################################
ENTRYPOINT /root/init.sh
