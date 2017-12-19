# docker-lineage-cicd

Docker microservice for LineageOS Continuous Integration and Continous Deployment

This branch contains a version suitable to build for multiple devices on different branches with the same Docker image: to do so it is necessary to download the full LineageOS mirror, about 200 GB. You probably want the more simple version in the master branch.

## Requirements

- At least Dual Core CPU (Higher is better)
- At least 6GB RAM (Higher is better)
- At least 500GB HDD Space (Higher is better)

### Android propretary binaries

By default when you build Android from scratch you need to pull the binaries of your interested device via ADB. When the INCLUDE_PROPRIETARY variable is set to true (default), the proprietary binaries are downloaded automatically from [TheMuppets repository](https://github.com/TheMuppets); if you want to provide your own binaries, set this variable to false and add a corresponding XML in the local_manifests volume.

## How it works

This docker will autobuild any device list given for a specified branch every midnight at 02:00 UTC. In the end, any built ZIP will be moved to the relative volume mapped directory to `/srv/zips`.

> **IMPORTANT:** Remember to use VOLUME mapping. By default Docker creates container with max 10GB of Space. If you will not map volumes, the docker will just break during Source syncronization!

**NOTE:** `/home/user/local_manifests/` may contain multiple XMLs, since all the files will be then copied inside `.repo/local_manifests/`

## Configuration

You can configure the Docker by passing custom environment variables to it. See the [Dockerfile](Dockerfile#L11) for more details.

## How to use

Specify the branches and the devices in the corresponding variables, separated by a comma.

This example is the build script used for [LineageOS for microG](https://lineage.microg.org), which has integrated microG apps and F-Droid (with F-Droid Privileged Extension).
```
docker run \
    --name=lineage-$(date +%Y%m%d_%H%M) \
    --cap-add=SYS_ADMIN \
    -d \
    -e "USER_NAME=John Doe" \
    -e "USER_MAIL=john.doe@awesome.email" \
    -e "WITH_SU=false" \
    -e "INCLUDE_PROPRIETARY=true" \
    -e "RELEASE_TYPE=microG" \
    -e "BRANCH_NAME=cm-13.0,cm-14.1" \
    -e "DEVICE_LIST_CM_13_0=$DEVICES_CM13_0" \
    -e "DEVICE_LIST_CM_14_1=$DEVICES_CM14_1" \
    -e "OTA_URL=https://api.lineage.microg.org" \
    -e "CRONTAB_TIME=now" \
    -e "SIGNATURE_SPOOFING=restricted" \
    -e "CUSTOM_PACKAGES=GmsCore GsfProxy FakeStore FDroid FDroidPrivilegedExtension MozillaNlpBackend NominatimNlpBackend com.google.android.maps.jar" \
    -e "SIGN_BUILDS=true" \
    -e "CLEAN_OUTDIR=false" \
    -e "CLEAN_AFTER_BUILD=true" \
    -e "ZIP_SUBDIR=true" \
    -e "LOGS_SUBDIR=true" \
    -e "DELETE_OLD_ZIPS=3" \
    -e "DELETE_OLD_LOGS=3" \
    -e "CCACHE_SIZE=540G" \
    -v "/home/user/cache:/srv/ccache" \
    -v "/home/user/mirror:/srv/mirror" \
    -v "/home/user/lineage:/srv/src" \
    -v "/home/user/zips:/srv/zips" \
    -v "/home/user/lineage_manifests:/srv/local_manifests" \
    -v "/home/user/lineage_keys:/srv/keys" \
    -v "/home/user/logs:/srv/logs" \
    -v "/home/user/tmp:/srv/tmp" \
    lineageos4microg/docker-lineage-cicd:multibranch
```
with the following XML in local_manifests
```
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project path="prebuilts/prebuiltapks" name="lineageos4microg/android_prebuilts_prebuiltapks" remote="github" revision="master" />
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
