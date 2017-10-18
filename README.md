# docker-lineage-cicd

Docker microservice for LineageOS Continuous Integration and Continous Deployment

## Why

Because I always believe that even advanced technologies should be available to everyone. This is a tentative to offer everyone the possibility to build his own images of LineageOS, when he wants, how he wants. You don't have to wait anymore for build bots. No more scene drama. Just build and enjoy your favourite Android ROM.

## Why Docker?

Because I'm a big fan of isolating everything if possible. I don't want to reinstall my OS or triage with dirty packages, just because today I need somethng, and tomorrow I'll need something else.

## Requirements

- At least Dual Core CPU (Higher is better)
- At least 6GB RAM (Higher is better)
- At least 250GB HDD Space (Higher is better)

### Android propretary binaries

By default when you build Android from scratch you need to pull the Binaries of your interested device via ADB. Although via this Docker is not possible to do so (would imply having all the devices connected to that machine and ideally know how to switch from one to the other before pulling). Therefore, I highly suggest to download this manifest (https://github.com/TheMuppets/manifests) inside your mapped `/srv/local_manifests` folder.

## How it works

This docker will autobuild any device list given for a specified branch every midnight at 02:00 UTC. In the end, any built ZIP will be moved to the relative volume mapped directory to `/srv/zips`.

> **IMPORTANT:** Remember to use VOLUME mapping. By default Docker creates container with max 10GB of Space. If you will not map volumes, the docker will just break during Source syncronization!

**NOTE:** `/home/user/local_manifests/` may contain multiple XMLs, since all the files will be then copied inside `.repo/local_manifests/`

## Configuration

You can configure the Docker by passing custom environment variables to it. See the [Dockerfile](Dockerfile#L11) for more details.

## How to use

### Simple mode
build cm14.1 LineageOS for `hammerhead` with default settings
```
docker run \
    --restart=always \
    -d \
    -e "USER_NAME=John Doe" \
    -e "USER_MAIL=john.doe@awesome.email" \
    -e "DEVICE_LIST=hammerhead" \
    -v "/home/user/ccache:/srv/ccache" \
    -v "/home/user/source:/srv/src" \
    -v "/home/user/zips:/srv/zips" \
    lineageos4microg/docker-lineage-cicd
```

### Advanced mode
build cm-13.0 LineageOS for `hammerhead` and `bullhead`.
Instead of scheduling the execution, build it now and exit.
For each device, create a subdir `device_codename` in /home/user/zips and move the builds there.
```
docker run \
    -d \
    -e "USER_NAME=John Doe" \
    -e "USER_MAIL=john.doe@awesome.email" \
    -e "BRANCH_NAME=cm-13.0" \
    -e "DEVICE_LIST=hammerhead,bullhead" \
    -e "CRONTAB_TIME=now" \
    -e "ZIP_SUBDIR=true" \
    -v "/home/user/ccache:/srv/ccache" \
    -v "/home/user/source:/srv/src" \
    -v "/home/user/zips:/srv/zips" \
    lineageos4microg/docker-lineage-cicd
```

### Expert mode
build cm-14.1 LineageOS for a device that doesn't exist inside the main project, but comes from a special manifest (has to be created inside `/home/user/local_manifests/`). For each device, create a subdir `device_codename` in /home/user/zips and move the builds there. Start the builds every Sunday at 10:00 UTC.
Finally provide a custom OTA URL for this ROM so users can update using built-in OTA Updater.
```
docker run \
    --restart=always \
    -d \
    -e "USER_NAME=John Doe" \
    -e "USER_MAIL=john.doe@awesome.email" \
    -e "BRANCH_NAME=cm-14.1" \
    -e "DEVICE_LIST=n80xx" \
    -e "OTA_URL=http://cool.domain/api" \
    -e "CRONTAB_TIME=0 10 * * Sun" \
    -e "ZIP_SUBDIR=true" \
    -v "/home/user/ccache:/srv/ccache" \
    -v "/home/user/source:/srv/src" \
    -v "/home/user/zips:/srv/zips" \
    -v "/home/user/local_manifests:/srv/local_manifests" \
    lineageos4microg/docker-lineage-cicd
```

### Custom mode
You can also apply some modifications to the LineageOS code before building it. This example is the build script used for [this LineageOS fork](https://lineageos.corna.info/), which has integrated microG apps, F-Droid (with F-Droid Privileged Extension) and OpenDelta (from the OmniROM project, for delta updates).
```
docker run \
    --name=lineage-$(date +%Y%m%d_%H%M) \
    -d \
    -e "USER_NAME=John Doe" \
    -e "USER_MAIL=john.doe@awesome.email" \
    -e "WITH_SU=false" \
    -e "RELEASE_TYPE=microG" \
    -e "DEVICE_LIST=thea,falcon,onyx,bacon,Z00L" \
    -e "CRONTAB_TIME=now" \
    -e "SIGNATURE_SPOOFING=restricted" \
    -e "CUSTOM_PACKAGES=GmsCore GsfProxy FakeStore FDroid FDroidPrivilegedExtension com.google.android.maps.jar MozillaNlpBackend NominatimNlpBackend OpenDelta" \
    -e "SIGN_BUILDS=true" \
    -e "CLEAN_OUTDIR=false" \
    -e "CLEAN_AFTER_BUILD=true" \
    -e "ZIP_SUBDIR=true" \
    -e "LOGS_SUBDIR=true" \
    -e "BUILD_DELTA=true" \
    -e "DELETE_OLD_ZIPS=3" \
    -e "DELETE_OLD_DELTAS=10" \
    -e "DELETE_OLD_LOGS=10" \
    -e "OPENDELTA_BUILDS_JSON=builds.json" \
    -v "/home/user/ccache:/srv/ccache" \
    -v "/home/user/source:/srv/src" \
    -v "/home/user/public/full:/srv/zips" \
    -v "/home/user/local_manifests:/srv/local_manifests" \
    -v "/home/user/keys:/srv/keys" \
    -v "/home/user/public/delta:/srv/delta" \
    -v "/home/user/logs:/srv/logs" \
    lineageos4microg/docker-lineage-cicd
```
with the following XML in local_manifests
```
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project path="prebuilts/prebuiltapks" name="lineageos4microg/android_prebuilts_prebuiltapks" remote="github" revision="master" />
  <project path="packages/apps/OpenDelta" name="lineageos4microg/android_packages_apps_OpenDelta" remote="github" revision="android-7.1" />
</manifest>
```

The keys in /home/build/keys can be generated with
```
subject='/C=US/ST=California/L=Mountain View/O=Android/OU=Android/CN=Android/emailAddress=android@android.com'
mkdir keys
for x in releasekey platform shared media; do \
    /home/user/source/development/tools/make_key keys/$x "$subject"; \
done
for c in cyngn{-priv,}-app testkey; do
  for e in pk8 x509.pem; do
    ln -s releasekey.$e keys/$c.$e;
  done;
done
```
