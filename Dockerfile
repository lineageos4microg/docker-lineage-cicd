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
ENV DEBIAN_FRONTEND noninteractive
ENV USER root

# Configurable environment variables
####################################

# By default we want to use CCACHE, you can disable this
# WARNING: disabling this may slow down a lot your builds!
ENV USE_CCACHE 1

# Environment for the LineageOS Branch name
# See https://github.com/LineageOS/android_vendor_cm/branches for possible options
ENV BRANCH_NAME 'cm-14.1'

# Environment for the device list ( separate by comma if more than one)
# eg. DEVICE_LIST=hammerhead,bullhead,angler
ENV DEVICE_LIST ''

# OTA URL that will be used inside CMUpdater
# Use this in combination with LineageOTA to make sure your device can auto-update itself from this buildbot
ENV OTA_URL ''

# User identity
ENV USER_NAME 'LineageOS Buildbot'
ENV USER_MAIL 'lineageos-buildbot@docker.host'

# If you want to start always fresh ( re-download all the source code everytime ) set this to 'true'
ENV CLEAN_SRCDIR false

# If you want to preserve old ZIPs set this to 'false'
ENV CLEAN_OUTDIR true

# Change this cron rule to what fits best for you
# By Default = At 10:00 UTC ~ 2am PST/PDT
# Use 'now' to start the build immediately
ENV CRONTAB_TIME '0 10 * * *'

# Print detailed output rather than only summary
ENV DEBUG false

# Clean artifacts output after each build
ENV CLEAN_AFTER_BUILD true

# Provide root capabilities builtin inside the ROM ( see http://lineageos.org/Update-and-Build-Prep/ )
ENV WITH_SU true

# Provide a default JACK configuration in order to avoid out-of-memory issues
ENV ANDROID_JACK_VM_ARGS "-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx4G"

# Custom packages to be installed
ENV CUSTOM_PACKAGES ''

# Key path (from the root of the android source)
ENV SIGN_BUILDS false

# Move the resulting zips to $ZIP_DIR/$codename instead of $ZIP_DIR/
ENV ZIP_SUBDIR false

# Apply the signature spoofing patch
# Valid values are "no", "yes" (for the original MicroG's patch) and "restricted" (to grant the
# permission only to the privileged apps)
ENV SIGNATURE_SPOOFING "no"

# Generate delta files (saved in $ZIP_DIR/delta)
ENV BUILD_DELTA false

# Create Volume entry points
############################

VOLUME $SRC_DIR
VOLUME $CCACHE_DIR
VOLUME $ZIP_DIR
VOLUME $LMANIFEST_DIR
VOLUME $DELTA_DIR
VOLUME $KEYS_DIR

# Copy required files and fix permissions
#####################

COPY src/* /root/

# Create missing directories
############################

RUN mkdir -p $SRC_DIR
RUN mkdir -p $CCACHE_DIR
RUN mkdir -p $ZIP_DIR
RUN mkdir -p $LMANIFEST_DIR
RUN mkdir -p $DELTA_DIR
RUN mkdir -p $KEYS_DIR

# Fix permissions
#################

RUN chmod 0755 /root/*

# Install build dependencies
############################

RUN sed -i 's/main$/main universe/' /etc/apt/sources.list
RUN apt-get -qq update
RUN apt-get -qqy upgrade

RUN apt-get install -y bc bison build-essential ccache cron curl flex \
      g++-multilib gcc-multilib git gnupg gperf imagemagick lib32ncurses5-dev \
      lib32readline6-dev lib32z1-dev libesd0-dev liblz4-tool libncurses5-dev \
      libsdl1.2-dev libssl-dev libwxgtk3.0-dev libxml2 libxml2-utils lzop \
      openjdk-8-jdk pngcrush rsync schedtool squashfs-tools wget xsltproc zip \
      zlib1g-dev

RUN curl https://storage.googleapis.com/git-repo-downloads/repo > /usr/local/bin/repo
RUN chmod a+x /usr/local/bin/repo

# Download and build delta tools
################################
RUN cd /root/ && \
        mkdir delta && \
        git clone https://github.com/omnirom/android_packages_apps_OpenDelta.git OpenDelta && \
        cd OpenDelta/jni && \
        gcc -o /root/delta/zipadjust zipadjust.c zipadjust_run.c -lz && \
        cd xdelta3* && \
        chmod +x configure && \
        ./configure && \
        make && \
        cp xdelta3 /root/OpenDelta/server/minsignapk.jar /root/OpenDelta/server/opendelta.sh /root/delta/ && \
        rm -rf /root/OpenDelta && \
        chmod +x /root/delta/opendelta.sh && \
        sed -i -e 's/^\s*HOME=.*/HOME=\/root/' /root/delta/opendelta.sh && \
        sed -i -e 's/^\s*FILE_MATCH=.*/FILE_MATCH=lineage-\*.zip/' /root/delta/opendelta.sh && \
        sed -i -e 's/^\s*PATH_CURRENT=.*/PATH_CURRENT=$SRC_DIR\/out\/target\/product\/$DEVICE/' /root/delta/opendelta.sh && \
        sed -i -e 's/^\s*PATH_LAST=.*/PATH_LAST=$SRC_DIR\/delta_last\/$DEVICE/' /root/delta/opendelta.sh && \
        sed -i -e 's/^\s*KEY_X509=.*/KEY_X509=$KEYS_DIR\/releasekey.x509.pem/' /root/delta/opendelta.sh && \
        sed -i -e 's/^\s*KEY_PK8=.*/KEY_PK8=$KEYS_DIR\/releasekey.pk8/' /root/delta/opendelta.sh && \
        sed -i -e 's/publish/$DELTA_DIR/g' /root/delta/opendelta.sh

# Set the work directory
########################
WORKDIR $SRC_DIR

# Allow redirection of stdout to docker logs
############################################

RUN ln -sf /proc/1/fd/1 /var/log/docker.log

# Set the entry point to init.sh
###########################################

ENTRYPOINT /root/init.sh
