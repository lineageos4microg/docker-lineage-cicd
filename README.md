# docker-lineage-cicd

Docker microservice for LineageOS Continuous Integration and Continous Deployment

## Why Docker?

A fair number of dependencies is needed to build LineageOS, plus a Linux system
(and a discrete knowledge of it). With Docker we give you a minimal Linux build
system with all the tools and scripts already integrated, easing considerably
the creation of your own LineageOS build.

Moreover Docker runs also on Microsoft Windows and Mac OS, which means that
LineageOS can be built on such platforms without requiring a dual boot system
or a manual set up of a Virtual Machine.

## How do I install Docker?

The official Docker guides are well-written:
 * Linux ([Ubuntu][docker-ubuntu], [Debian][docker-debian],
    [CentOS][docker-centos] and [Fedora][docker-fedora] are officially
    supported)
 * [Windows 10/Windows Server 2016 64bit][docker-win]
 * [Mac OS El Capitan 10.11 or newer][docker-mac]

If your Windows or Mac system doesn't satisfy the requirements (or if you have
Oracle VirtualBox installed, you can use [Docker Toolbox][docker-toolbox].
Docker Toolbox is not described in this guide, but it should be very similar to
the standard Docker installation.

Once you can run the [`hello-world` image][docker-helloworld] you're ready to
start!

## How can I build LineageOS?

This Docker image contains a great number of settings, to allow you to fully
customize your LineageOS build. Here you can find all of them, with the default
values between the brackets.

TL;DR - go to the [Examples](#examples)

### Fundamental settings

The two fundamental settings are:

 * `BRANCH_NAME (lineage-16.0)`: LineageOS branch, see the branch list
    [here][los-branches] (multiple comma-separated branches can be specified)
 * `DEVICE_LIST`: comma-separated list of devices to build

Running a build with only these two set will create a ZIP file almost identical
to the LineageOS official builds, just signed with the test keys.

When multiple branches are selected, use `DEVICE_LIST_<BRANCH_NAME>` to specify
the list of devices for each specific branch (see [the examples](#examples)).

### Signature spoofing

There are two options for the [signature spoofing patch][signature-spoofing]
required for [microG][microg]:
 * "Original" [patches][signature-spoofing-patches]
 * Restricted patches

With the "original" patch the FAKE_SIGNATURE permission can be granted to any
user app: while it may seem handy, this is considered dangerous by a great
number of people, as the user could accidentally give this permission to rogue
apps.

A more strict option is the restricted patch, where the FAKE_SIGNATURE
permission can be obtained only by privileged system apps, embedded in the ROM
during the build process.

The signature spoofing patch can be optionally included with:

 * `SIGNATURE_SPOOFING (no)`: `yes` to use the original patch, `restricted` for
    the restricted one, `no` for none of them

If in doubt, use `restricted`: note that packages that requires the
FAKE_SIGNATURE permission must be embedded in the build by adding them in

 * `CUSTOM_PACKAGES`

Extra packages can be included in the tree by adding the corresponding manifest
XML to the local_manifests volume.

### Proprietary files

Some proprietary files are needed to create a LineageOS build, but they're not
included in the LineageOS repo for legal reasons. You can obtain these blobs in
three ways:

 * by [pulling them from a running LineageOS][blobs-pull]
 * by [extracting them from a LineageOS ZIP][blobs-extract]
 * by downloading them from TheMuppets [GitHub][blobs-themuppets] and
   [GitLab][blobs-the-muppets] repositories (unofficial)

The third way is the easiest one and is enabled by default; if you're OK with
that just move on, otherwise set `INCLUDE_PROPRIETARY (true)` to `false` and
manually provide the blobs (not explained in this guide).

### OTA

If you have a server and you want to enable [OTA updates][lineageota] you have
to provide the URL of your server during the build process with:

 * `OTA_URL`

If you don't setup a OTA server you won't be able to update the device from the
updater app (but you can still update it manually with the recovery of course).

### Signing

By default, builds are signed with the Android test keys. If you want to sign
your builds with your own keys (**highly recommended**):

 * `SIGN_BUILDS (false)`: set to `true` to sign the builds with the keys
    contained in `/srv/keys`; if no keys are present, a new set will be generated

### Other settings

Other useful settings are:

 * `CCACHE_SIZE (50G)`: change this if you want to give more (or less) space to
    ccache
 * `WITH_SU (false)`: set to `true` to embed `su` in the build (note that, even
    when set to `false`, you can still enable root by flashing the
    [su installable ZIP][los-extras])
 * `RELEASE_TYPE (UNOFFICIAL)`: change the release type of your builds
 * `BUILD_OVERLAY (false)`: normally each build is done on the source tree, then
    the tree is cleaned with `mka clean`. If you want to be sure that each build
    is isolated from the others, set `BUILD_OVERLAY` to `true` (longer build
    time). Requires `--cap-add=SYS_ADMIN`.
 * `LOCAL_MIRROR (false)`: change this to `true` if you want to create a local
    mirror of the LineageOS source (> 200 GB)
 * `CRONTAB_TIME (now)`: instead of building immediately and exit, build at the
    specified time (uses standard cron format)
 * `BOOT_IMG (false)`: copy the build boot.img into the zips folder. This is useful
    as you may need to flash it first if your device doesn't support custom recoveries

The full list of settings, including the less interesting ones not mentioned in
this guide, can be found in the [Dockerfile][dockerfile].

## Volumes

You also have to provide Docker some volumes, where it'll store the source, the
resulting builds, the cache and so on. The volumes are:

 * `/srv/src`, for the LineageOS sources
 * `/srv/zips`, for the output builds
 * `/srv/logs`, for the output logs
 * `/srv/ccache`, for the ccache
 * `/srv/local_manifests`, for custom manifests (optional)
 * `/srv/userscripts`, for the user scripts (optional)

When `SIGN_BUILDS` is `true`

 * `/srv/keys`, for the signing keys

When `BUILD_OVERLAY` is `true`

 * `/srv/tmp`, for temporary files

When `LOCAL_MIRROR` is `true`:

 * `/srv/mirror`, for the LineageOS mirror

## Examples

### Build for bacon (lineage-16.0, officially supported), test keys, no patches

```
docker run \
    -e "BRANCH_NAME=lineage-16.0" \
    -e "DEVICE_LIST=bacon" \
    -v "/home/user/lineage:/srv/src" \
    -v "/home/user/zips:/srv/zips" \
    -v "/home/user/logs:/srv/logs" \
    -v "/home/user/cache:/srv/ccache" \
    lineageos4microg/docker-lineage-cicd
```

### Build for angler (lineage-15.1, officially supported), custom keys, restricted signature spoofing with integrated microG and FDroid

```
docker run \
    -e "BRANCH_NAME=lineage-15.1" \
    -e "DEVICE_LIST=angler" \
    -e "SIGN_BUILDS=true" \
    -e "SIGNATURE_SPOOFING=restricted" \
    -e "CUSTOM_PACKAGES=GmsCore GsfProxy FakeStore MozillaNlpBackend NominatimNlpBackend com.google.android.maps.jar FDroid FDroidPrivilegedExtension " \
    -v "/home/user/lineage:/srv/src" \
    -v "/home/user/zips:/srv/zips" \
    -v "/home/user/logs:/srv/logs" \
    -v "/home/user/cache:/srv/ccache" \
    -v "/home/user/keys:/srv/keys" \
    -v "/home/user/manifests:/srv/local_manifests" \
    lineageos4microg/docker-lineage-cicd
```

If there are already keys in `/home/user/keys` they will be used, otherwise a
new set will be generated before starting the build (and will be used for every
subsequent build).

The microG and FDroid packages are not present in the LineageOS repositories,
and must be provided through an XML in the `/home/user/manifests`.
[This][prebuiltapks] repo contains some of the most common packages for these
kind of builds: to include it create an XML (the name is irrelevant, as long as
it ends with `.xml`) in the `/home/user/manifests` folder with this content:

```
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project name="lineageos4microg/android_prebuilts_prebuiltapks" path="prebuilts/prebuiltapks" remote="github" revision="master" />
</manifest>
```

### Build for four devices on lineage-15.1 and lineage-16.0 (officially supported), custom keys, restricted signature spoofing with integrated microG and FDroid, custom OTA server

```
docker run \
    -e "BRANCH_NAME=lineage-15.1,lineage-16.0" \
    -e "DEVICE_LIST_LINEAGE_15_1=angler,oneplus2" \
    -e "DEVICE_LIST_LINEAGE_16_0=bacon,dumpling" \
    -e "SIGN_BUILDS=true" \
    -e "SIGNATURE_SPOOFING=restricted" \
    -e "CUSTOM_PACKAGES=GmsCore GsfProxy FakeStore MozillaNlpBackend NominatimNlpBackend com.google.android.maps.jar FDroid FDroidPrivilegedExtension " \
    -e "OTA_URL=https://api.myserver.com/" \
    -v "/home/user/lineage:/srv/src" \
    -v "/home/user/zips:/srv/zips" \
    -v "/home/user/logs:/srv/logs" \
    -v "/home/user/cache:/srv/ccache" \
    -v "/home/user/keys:/srv/keys" \
    -v "/home/user/manifests:/srv/local_manifests" \
    lineageos4microg/docker-lineage-cicd
```

### Build for a6000 (not officially supported), custom keys, restricted signature spoofing with integrated microG and FDroid

As there is no official support for this device, we first have to include the
sources in the source tree through an XML in the `/home/user/manifests` folder;
from [this][a6000-xda] thread we get the links of:

 * Device tree: https://github.com/dev-harsh1998/android_device_lenovo_a6000
 * Common Tree: https://github.com/dev-harsh1998/android_device_lenovo_msm8916-common
 * Kernel: https://github.com/dev-harsh1998/kernel_lenovo_msm8916
 * Vendor blobs: https://github.com/dev-harsh1998/proprietary-vendor_lenovo

Then, with the help of lineage.dependencies from the
[device tree][a6000-device-tree-deps] and the
[common tree][a6000-common-tree-deps] we create an XML
`/home/user/manifests/a6000.xml` with this content:

```
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project name="dev-harsh1998/android_device_lenovo_a6000" path="device/lenovo/a6000" remote="github" />
  <project name="dev-harsh1998/android_device_lenovo_msm8916-common" path="device/lenovo/msm8916-common" remote="github" />
  <project name="dev-harsh1998/kernel_lenovo_msm8916" path="kernel/lenovo/a6000" remote="github" />
  <project name="dev-harsh1998/proprietary-vendor_lenovo" path="vendor/lenovo" remote="github" />
  <project name="LineageOS/android_device_qcom_common" path="device/qcom/common" remote="github" />
</manifest>
```

We also want to include our custom packages so, like before, create an XML (for
example `/home/user/manifests/custom_packages.xml`) with this content:

```
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project name="lineageos4microg/android_prebuilts_prebuiltapks" path="prebuilts/prebuiltapks" remote="github" revision="master" />
</manifest>
```

We also set `INCLUDE_PROPRIETARY=false`, as the proprietary blobs are already
provided by the repo
https://github.com/dev-harsh1998/prorietary_vendor_lenovo (so we
don't have to include the TheMuppets repo).

Now we can just run the build like it was officially supported:

```
docker run \
    -e "BRANCH_NAME=lineage-15.1" \
    -e "DEVICE_LIST=a6000" \
    -e "SIGN_BUILDS=true" \
    -e "SIGNATURE_SPOOFING=restricted" \
    -e "CUSTOM_PACKAGES=GmsCore GsfProxy FakeStore MozillaNlpBackend NominatimNlpBackend com.google.android.maps.jar FDroid FDroidPrivilegedExtension " \
    -e "INCLUDE_PROPRIETARY=false" \
    -v "/home/user/lineage:/srv/src" \
    -v "/home/user/zips:/srv/zips" \
    -v "/home/user/logs:/srv/logs" \
    -v "/home/user/cache:/srv/ccache" \
    -v "/home/user/keys:/srv/keys" \
    -v "/home/user/manifests:/srv/local_manifests" \
    lineageos4microg/docker-lineage-cicd
```


[docker-ubuntu]: https://docs.docker.com/install/linux/docker-ce/ubuntu/
[docker-debian]: https://docs.docker.com/install/linux/docker-ce/debian/
[docker-centos]: https://docs.docker.com/install/linux/docker-ce/centos/
[docker-fedora]: https://docs.docker.com/install/linux/docker-ce/fedora/
[docker-win]: https://docs.docker.com/docker-for-windows/install/
[docker-mac]: https://docs.docker.com/docker-for-mac/install/
[docker-toolbox]: https://docs.docker.com/toolbox/overview/
[docker-helloworld]: https://docs.docker.com/get-started/#test-docker-installation
[los-branches]: https://github.com/LineageOS/android/branches
[signature-spoofing]: https://github.com/microg/android_packages_apps_GmsCore/wiki/Signature-Spoofing
[microg]: https://microg.org/
[signature-spoofing-patches]: src/signature_spoofing_patches/
[blobs-pull]: https://wiki.lineageos.org/devices/bacon/build#extract-proprietary-blobs
[blobs-extract]: https://wiki.lineageos.org/extracting_blobs_from_zips.html
[blobs-themuppets]: https://github.com/TheMuppets/manifests
[blobs-the-muppets]: https://gitlab.com/the-muppets/manifest
[lineageota]: https://github.com/julianxhokaxhiu/LineageOTA
[los-extras]: https://download.lineageos.org/extras
[dockerfile]: Dockerfile
[prebuiltapks]: https://github.com/lineageos4microg/android_prebuilts_prebuiltapks
[a6000-xda]: https://forum.xda-developers.com/lenovo-a6000/development/rom-lineageos-15-1-t3733747
[a6000-device-tree-deps]: https://github.com/dev-harsh1998/android_device_lenovo_a6000/blob/lineage-15.1/lineage.dependencies
[a6000-common-tree-deps]: https://github.com/dev-harsh1998/android_device_lenovo_msm8916-common/blob/lineage-15.1/lineage.dependencies
