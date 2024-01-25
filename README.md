# docker-lineage-cicd

Docker microservice for LineageOS Continuous Integration and Continuous Deployment

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

## What does Docker build

Docker will produce two files in the `zips` directory:
1. The main ROM zip file e.g. `lineage-20.0-20230702-microG-<device-name>.zip`. This file can be flashed from recovery as described in the next section.
2. A `-image.zip` file e.g. `lineage-20.0-20230702-microG-<device-name>-images.zip`, containing a custom recovery image and any other images needed or mentioned in the LineageOS installation instructions.

## How can I build LineageOS?

Before you start, make sure you have the latest version of our Docker image:
```
docker pull lineageos4microg/docker-lineage-cicd
```

The requirements for building LineageOS for MicroG are roughly the same as for [building LineageOS](https://wiki.lineageos.org/devices/sunfish/build):
- A relatively recent x86_64 computer:
  - Linux, macOS, or Windows - these instructions are only tested using Ubuntu 20.04 LTS, so we recommend going with that.
  - A reasonable amount of RAM (16 GB to build up to lineage-17.1, 32 GB or more for lineage-18.1 and up). The less RAM you have, the longer the build will take. Enabling ZRAM can be helpful. If builds fail because of lack of memory, you can sometimes get over the problem by increasing the amount of swap, but this will be at the expense of slower build times.
  - A reasonable amount of Storage (~300 GB for lineage-18.1 and up). You might require more free space for enabling ccache, building for multiple devices, or if you choose to mirror the LineageOS sources (see below). Using SSDs results in considerably faster build times than traditional hard drives.

- A decent internet connection and reliable electricity. :)
- Some familiarity with basic Android operation and terminology. It may be useful to know some basic command line concepts such as cd, which stands for “change directory”, the concept of directory hierarchies, and that in Linux they are separated by /, etc.

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

#### GMS / microG

To include microG (or possibly the actual Google Mobile Services) in your build,
LineageOS expects certain Makefiles in `vendor/partner_gms` and variable
`WITH_GMS` set to `true`.

[This][android_vendor_partner_gms] repo contains the common packages included for
official lineageos4microg builds. To include it in your build, create an XML
(the name is irrelevant, as long as it ends with `.xml`) in the
`/home/user/manifests` folder with this content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <project path="vendor/partner_gms" name="lineageos4microg/android_vendor_partner_gms" remote="github" revision="master" />
</manifest>
```

#### Additional custom apps

If you wish to add other apps to your ROM, you can include a repository with
source code or prebuilt APKs. For prebuilt apks, see the [android_vendor_partner_gms][android_vendor_partner_gms]
repository for examples on how the `Android.mk` file should look like.

Include the repo with another manifest file like this:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project name="your-github-user/your-repo" path="prebuilts/my-custom-apps" remote="github" revision="master" />
</manifest>
```

And when starting the build, set the `CUSTOM_PACKAGES` variable to a list of app names
(defined by `LOCAL_MODULE` in `Android.mk`) separated by spaces.

#### Signature spoofing

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
FAKE_SIGNATURE permission must be included in the build as system apps
(e.g. as part of GMS or `CUSTOM_PACKAGES`)


#### Proprietary files

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

#### Over the Air updates

To enable OTA for you builds, you need to run a server that speaks the protocol
understood by the [LineageOS updater app][updater] and provide the URL to this
server as `OTA_URL` variable for the build.

One implementation is [LineageOTA][lineageota], which is also available as Docker
image. Follow these steps to prepare your builds for OTA:

* Run the Docker image `julianxhokaxhiu/lineageota`
  * Port 80 exposed to the internet (might want to add an HTTPS reverse proxy)
  * The `/srv/zips` directory/volume of the CICD image mounted at
    `/var/www/html/builds/full` (can be read-only)
* Set environment variables when building
  * `ZIP_SUBDIR` to `false`
  * `OTA_URL` to the address of the OTA server, with `/api` appended

If you don't setup a OTA server you won't be able to update the device from the
updater app (but you can still update it manually with the recovery of course).

#### Signing

By default, builds are signed with the Android test keys. If you want to sign
your builds with your own keys (**highly recommended**):

 * `SIGN_BUILDS (false)`: set to `true` to sign the builds with the keys
    contained in `/srv/keys`; if no keys are present, a new set will be generated

#### Settings to control 'switchable' build steps

Some of the the steps in the build process (e.g `repo sync`, `mka`) can take a long time to complete. When working on a build, it may be desirable to skip some of the steps. The following environment variables (and their default values) control whether or not each step is performed
```
# variables to control whether or not tasks are implemented
ENV INIT_MIRROR true
ENV SYNC_MIRROR true
ENV RESET_VENDOR_UNDO_PATCHES true
ENV CALL_REPO_INIT true
ENV CALL_REPO_SYNC true
ENV CALL_GIT_LFS_PULL false
ENV APPLY_PATCHES true
ENV PREPARE_BUILD_ENVIRONMENT true
ENV CALL_BREAKFAST true
ENV CALL_MKA true
ENV ZIP_UP_IMAGES false
ENV MAKE_IMG_ZIP_FILE false
```

To `switch` an operation, change the default value of the the variable in a `-e clause` in the `docker run` command e.g.
` -e "CALL_REPO-SYNC=false" \`

The `ZIP_UP_IMAGES` and `MAKE_IMG_ZIP_FILE` variables control how the `.img` files created by the buid are handled:
- by default, the `img` files are copied - unzipped - to the `zips` directory
- if `ZIP_UP_IMAGES` is set `true`, the images are zipped and the resulting `...images.zip` is copied to the `zips` directory
- if `MAKE_IMG_ZIP_FILE` is set `true`, a flashsable `...-img.zip` file is created, which can be installed using `fastboot flash` or `fastboot update`


#### Other settings

Other useful settings are:

 * `CCACHE_SIZE (50G)`: change this if you want to give more (or less) space to
    ccache
 * `WITH_SU (false)`: set to `true` to embed `su` in the build (note that, even
    when set to `false`, you can still enable root by flashing the
    [su installable ZIP][los-extras]). This is only for lineage version 16 and below.
 * `RELEASE_TYPE (UNOFFICIAL)`: change the release type of your builds
 * `BUILD_TYPE (userdebug)`: type of your builds, see [Android docs](https://source.android.com/docs/setup/build/building#choose-a-target)
 * `BUILD_OVERLAY (false)`: normally each build is done on the source tree, then
    the tree is cleaned with `mka clean`. If you want to be sure that each build
    is isolated from the others, set `BUILD_OVERLAY` to `true` (longer build
    time). Requires `--cap-add=SYS_ADMIN`.
 * `LOCAL_MIRROR (false)`: change this to `true` if you want to create a local
    mirror of the LineageOS source (> 200 GB)
 * `CRONTAB_TIME (now)`: instead of building immediately and exit, build at the
    specified time (uses standard cron format)
 * `ZIP_SUBDIR (true)`: Move the resulting zips to $ZIP_DIR/$codename instead of $ZIP_DIR/
 * `PARALLEL_JOBS`: Limit the number of parallel jobs to run (`-j` for `repo sync` and `mka`).
   By default, the build system should match the number of parallel jobs to the number of cpu
   cores on your machine. Reducing this number can help keeping it responsive for other tasks.
 * `RETRY_FETCHES`: Set the number of retries for the fetch during `repo sync`. By default, this value is unset (default `repo sync` retry behavior).
   Positive values greater than 0 are allowed.

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

### Build for river (lineage-18.1, officially supported), test keys, no patches

```sh
docker run \
    -e "BRANCH_NAME=lineage-18.1" \
    -e "DEVICE_LIST=river" \
    -v "/home/user/lineage:/srv/src" \
    -v "/home/user/zips:/srv/zips" \
    -v "/home/user/logs:/srv/logs" \
    -v "/home/user/cache:/srv/ccache" \
    lineageos4microg/docker-lineage-cicd
```

### Build for bacon (lineage-17.1, officially supported), custom keys, restricted signature spoofing with integrated microG and FDroid

```sh
docker run \
    -e "BRANCH_NAME=lineage-17.1" \
    -e "DEVICE_LIST=bacon" \
    -e "SIGN_BUILDS=true" \
    -e "SIGNATURE_SPOOFING=restricted" \
    -e "WITH_GMS=true" \
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
and must be provided e.g. through [android_vendor_partner_gms][android_vendor_partner_gms].


### Build for four devices on lineage-17.1 and lineage-18.1 (officially supported), custom keys, restricted signature spoofing with integrated microG and FDroid, custom OTA server

```sh
docker run \
    -e "BRANCH_NAME=lineage-17.1,lineage-18.1" \
    -e "DEVICE_LIST_LINEAGE_17_1=bacon,oneplus2" \
    -e "DEVICE_LIST_LINEAGE_18_1=river,lake" \
    -e "SIGN_BUILDS=true" \
    -e "SIGNATURE_SPOOFING=restricted" \
    -e "WITH_GMS=true" \
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

```xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project name="dev-harsh1998/android_device_lenovo_a6000" path="device/lenovo/a6000" remote="github" />
  <project name="dev-harsh1998/android_device_lenovo_msm8916-common" path="device/lenovo/msm8916-common" remote="github" />
  <project name="dev-harsh1998/kernel_lenovo_msm8916" path="kernel/lenovo/a6000" remote="github" />
  <project name="dev-harsh1998/proprietary-vendor_lenovo" path="vendor/lenovo" remote="github" />
  <project name="LineageOS/android_device_qcom_common" path="device/qcom/common" remote="github" />
</manifest>
```

We also want to include microG so, like before, create an XML (for
example `/home/user/manifests/microg.xml`) with this content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <project path="vendor/partner_gms" name="lineageos4microg/android_vendor_partner_gms" remote="github" revision="master" />
</manifest>
```

We also set `INCLUDE_PROPRIETARY=false`, as the proprietary blobs are already
provided by the repo
https://github.com/dev-harsh1998/prorietary_vendor_lenovo (so we
don't have to include the TheMuppets repo).

Now we can just run the build like it was officially supported:

```sh
docker run \
    -e "BRANCH_NAME=lineage-15.1" \
    -e "DEVICE_LIST=a6000" \
    -e "SIGN_BUILDS=true" \
    -e "SIGNATURE_SPOOFING=restricted" \
    -e "WITH_GMS=true" \
    -e "INCLUDE_PROPRIETARY=false" \
    -v "/home/user/lineage:/srv/src" \
    -v "/home/user/zips:/srv/zips" \
    -v "/home/user/logs:/srv/logs" \
    -v "/home/user/cache:/srv/ccache" \
    -v "/home/user/keys:/srv/keys" \
    -v "/home/user/manifests:/srv/local_manifests" \
    lineageos4microg/docker-lineage-cicd
```

# Web Site text

The following should be published on [the LineageOS for microG website](https://lineage.microg.org/). It is included here until the website can be updated


## How do I install the LineageOS for MicroG ROM

Follow the LineageOS installation instructions for your device, which can be accessed from the [LineageOS Devices wiki pages](https://wiki.lineageos.org/devices/). If the LineageOS installation instructions require or refer to any `.img` files, these images can be obtained by unzipping the `-images.zip` file mentioned in the previous section.

### 'Clean' and 'dirty' flashing

A 'clean' flash is when the data partition is wiped and/or formatted before the ROM is installed. This will remove all user-installed apps and data. It is sometimes referred to as a 'fresh installation'.

A 'dirty flash' is when the data partition ***is not*** wiped and/or formatted before the ROM is installed. Normally this will result in all user-installed apps and data still being present after the installation.

Newer versions of the LineageOS for MicroG ROM can usually be 'dirty flashed' over older versions ***with the same Android version***.

Dirty flashing is ***sometimes*** possible over
- older versions of the LineageOS for MicroG ROM ***with an earlier** Android version***;
- the official LineageOS ROM (without microG)

In both these cases, problems may be encountered with app permissions, both for user-installed apps and for the pre-installed apps. These problems can sometimes be fixed by manually changing the app permissions.

If you are 'dirty' flashing, it is a good idea to backup your user-installed apps and data in case the 'dirty' flash fails.

## Troubleshooting and support

The LineageOS for MicroG project is not in a position to offer much by way of technical support:

- the number of active volunteer maintainers / contributors is very small, and we spend what time we have trying to ensure that the process of making regular builds keeps going. We can generally investigate problems with the build tools, but not with the ROM itself;
- we don't have access to any devices for testing / debugging

The [project issue tracker](https://github.com/lineageos4microg/docker-lineage-cicd/issues) is mostly for tracking problems with the Docker build tool. It is ***not*** intended for tracking problems with ***installing*** or ***running*** the LineageOS for MicroG ROM. If you run into such problems, our advice is to work through the following steps to see if they help. (Make a backup of your user apps & data first):
- full power off and restart
- factory reset
- format data partition
- install the most recent LineageOS for MicroG build for your device, from [here](https://download.lineage.microg.org/) following the [LOS installation instructions](https://wiki.lineageos.org/devices/).
- install the latest official LineageOS build from [here](https://download.lineageos.org/devices/)

For ***any*** problems, with building, installing, or running LineageOS for MicroG, we recommend that you ask for help in [the XDA Forum thread](https://xdaforums.com/t/lineageos-for-microg.3700997/) or in device specific [XDA forum threads](https://xdaforums.com/). The LineageOS for MicroG forum thread is not maintained by us, but there are many knowledgeable contributors there, who build and run the LineageOS for MicroG ROM on a wide variety of devices.


## LineageOS for microG: Project Scope & Objectives

As the website says, the LineageOS for microG project is a

> LineageOS unofficial fork with built-in microG gapps implementation

The prime objectives of the project are to:
- deliver regular builds of the project for all the phones and tablets[1] currently supported officially by LOS;
- create and maintain the source code, tools, and computing resources needed:
    - to make the builds;
    - to make the builds available for download, for manual and OTA installation.

Another - less central - objective is to allow other projects and individuals to use our source code and tools (though not currently our computing resources) to make and maintain their own builds:
- of L4M, 'vanilla' LOS, and / or other LOS-based custom ROMs;
- for other devices, whether or not supported officially.

### Upstreams

The project has two main 'upstream` projects:
- LineageOS ([website](https://lineageos.org/), [github repos](https://github.com/LineageOS))
- MicroG ([website](https://microg.org/), [github repos](https://github.com/microg))

Like LineageOS, the project also uses 'TheMuppets` [github](https://github.com/TheMuppets/) and [gitlab](https://gitlab.com/the-muppets) repos as the source for device-specific vendor binary blobs.

The main work of the project is to integrate the upstream components and build them into the ROM images we make available.

### Project Github repositories

The project has two main public repositories on GitHub:
-  [`docker-lineage-cicd`]( https://github.com/lineageos4microg/docker-lineage-cicd)
 The Docker image used by the project to make the regular builds, along with a [`README.md`](https://github.com/lineageos4microg/docker-lineage-cicd#readme) explaining how it can be used. The Docker images is rebuilt and pushed to [DockerHub](https://hub.docker.com/r/lineageos4microg/docker-lineage-cicd/) automatically when changes are pushed to the `master` branch
- [`android_vendor_partner_gms`](https://github.com/lineageos4microg/android_vendor_partner_gms)
The pre-built components from MicroG, along with makefiles for easy integration in the Android build system. The pre-built components are pulled automatically from the MicroG releases.

### Project deliverables

1. The device-specific ROM zip files.
2. Device-specific `-images.zip` files containing any `.img` files that are needed for installing or updating the ROM zip file (e.g. `boot.img`,  `recovery.img`).
3. The Docker image used to make the builds, including the (limited) documentation in the `README.md`.

The ROM zips and other device-specific files are made available in sub-directories on [the download server](https://download.lineage.microg.org/).

The Docker image is pushed to [DockerHub](https://hub.docker.com/r/lineageos4microg/docker-lineage-cicd/).

#### Build Targets and Frequency

We build for the same devices as LineageOS using [their list of build targets](https://github.com/LineageOS/hudson/blob/master/lineage-build-targets) as the input to our build run.

We currently make builds monthly, starting on the first day of the month. The devices included in a build run are defined by the content of the [LOS target list](https://github.com/LineageOS/hudson/blob/master/lineage-build-targets) ***at the point the build run starts***. Our monthly build run takes 15-16 days to complete. You can see the current status of the build in [the dedicated matrix room](https://matrix.to/#/#microg-lineage-os-builds:matrix.domainepublic.net) 

If builds for any devices fail during a build run, we will try the build again ***after the main build run has completed***. If you do not see a new build for your device when you expect it, please check whether the build failure was reported in the matrix room. If it was, there is no need to report it - we will deal with it! If the failure was not reported in the matrix room, then please report it in [our issue tracker](https://github.com/lineageos4microg/docker-lineage-cicd/issues) or in [the XDA Forums thread](https://xdaforums.com/t/lineageos-for-microg.3700997/)


### Project Scope

The following items are explicitly ***not*** within the scope of the project
- Changes to, or forks of, upstream components, except where necessary for the correct operation of the integrated components. At present, this means only [the signature spoofing patches](https://github.com/lineageos4microg/docker-lineage-cicd/tree/master/src/signature_spoofing_patches) that are needed for the correct operation of the MicroG software components (see Note 1)
- Maintaining, supporting or documenting the  tools or binary files, needed for ***installation*** of our ROMs. This is within the scope of the LineageOS upstream, which either builds and makes available the necessary tools and files,  or links to other projects (e.g. TWRP) which provide them

### Project Status

The project is currently in a fairly stable state:
- we are (mostly) achieving our objective of delivering monthly builds
- the only essential work that is ongoing is to
    - monitor the delivery process,  to fix any problems that may occur, and to make any changes that are needed to ensure that the problems do not recur
    - to make any changes needed when upstreams make changes. In particular, when LineageOS introduces support for a new Android version and / or drops support for older Android versions

The project is therefore - in the opinion of the currently active maintainers - essentially 'feature complete' and in 'maintenance' mode. The only change that we believe might significantly improve the project is to support other classes of Android devices, specifically
- `Minimal` & `Android TV` devices (see Note 2)
- [`Treble-capable`](https://www.xda-developers.com/list-android-devices-project-treble-support/) devices which are not officially supported by LOS.  [As has recently been suggested](https://github.com/lineageos4microg/docker-lineage-cicd/issues/462) building for the `lineage_gsi` target would make our builds available for and usable on these devices.


### Issue Reporting & Tracking

Our public github repos both have issue trackers, where any github user can create new issues. They are primarily intended for
- tracking problems with the components owned by the repos, i.e.  the Docker image, and ***our integration of*** the microG components.
- asking questions about how to use the components
- suggesting improvements to those components e.g.
    - ways in which the docker image could be changed to make the build process more efficient, or less error-prone
    - how our limited documentation (primarily the `README.md`) could be improved

They are not intended for
- problems 'owned' by the upstream projects (see Note 3) e.g  incorrect functionality, or requests for new or different functionality in
    - apps which are 'built-in' to LineageOS
    - microG components (unless the incorrect functionality is  caused by our integration of those components)
- problems which are out of scope (see above)
- providing support for users of our ROMs (see below)
- requests for new features in our components (see Note 4). As mentioned above, we believe the project is 'feature complete', and the project does not have the time and / or resources to expand its scope, even if we thought such expansion was desirable. We will consider any such feature requests (when / if we have the time to do so), but the answer is likely to be negative.

One area where we know improvements can be made is in showing the progress (or lack of progress) in addressing reported issues:
- currently an issue is either 'Open' or 'Closed'
- no indication of whether 'Open' issues will be fixed or not
- no visibility of the priority of open issues, or when or in what order they will be addressed
- no indication of whether 'Closed' issues were fixed or not before closure

Some gradual changes are in hand to address this.

### User Support

The project and the currently active maintainers do not have the time or resources to provide 'official' support for users of our ROMs. Fortunately, support and 'self-help' is available from the user community, in particular in the [LineageOS for microG' XDA Forums thread](https://xdaforums.com/t/lineageos-for-microg.3700997/).

Upstream projects have their own channels for supporting users.

### Notes
1. ***If*** such changes are needed, we will try to provide patches or Pull Requests to the upsteam components. We will only maintain our changes ourselves if the upstreams will not accept our changes
2. L4M ***does not*** currently support building for `Minimal` or `Android TV` devices, even when those devices are supported by LOS
3. This class of problem usually includes ***device-specific*** issues: we have no device-specific code, it all comes from upstream
4. Any new issues or feature requests are more likely to be received positively if they are accompanied by code changes (in patches or - preferred - in Pull Requests) to fix the issue or implement the change. However, such changes will not be accepted just ***because*** code changes are provided.


[docker-ubuntu]: https://docs.docker.com/engine/install/ubuntu/
[docker-debian]: https://docs.docker.com/engine/install/debian/
[docker-centos]: https://docs.docker.com/engine/install/centos/
[docker-fedora]: https://docs.docker.com/engine/install/fedora/
[docker-win]: https://docs.docker.com/desktop/install/windows-install/
[docker-mac]: https://docs.docker.com/desktop/install/mac-install/
[docker-toolbox]: https://docs.docker.com/desktop/
[docker-helloworld]: https://docs.docker.com/get-started/#test-docker-installation
[los-branches]: https://github.com/LineageOS/android/branches
[signature-spoofing]: https://github.com/microg/GmsCore/wiki/Signature-Spoofing
[microg]: https://microg.org/
[signature-spoofing-patches]: src/signature_spoofing_patches/
[blobs-pull]: https://wiki.lineageos.org/devices/bacon/build#extract-proprietary-blobs
[blobs-extract]: https://wiki.lineageos.org/extracting_blobs_from_zips.html
[blobs-themuppets]: https://github.com/TheMuppets/manifests
[blobs-the-muppets]: https://gitlab.com/the-muppets/manifest
[lineageota]: https://github.com/julianxhokaxhiu/LineageOTA
[updater]: https://github.com/LineageOS/android_packages_apps_Updater
[los-extras]: https://download.lineageos.org/extras
[dockerfile]: Dockerfile
[android_vendor_partner_gms]: https://github.com/lineageos4microg/android_vendor_partner_gms
[a6000-xda]: https://xdaforums.com/t/eol-rom-8-1-0_r43-f2fs-lineageos-15-1-arm-stable-final-android-go.3733747/
[a6000-device-tree-deps]: https://github.com/dev-harsh1998/android_device_lenovo_a6000/blob/lineage-15.1/lineage.dependencies
[a6000-common-tree-deps]: https://github.com/dev-harsh1998/android_device_lenovo_msm8916-common/blob/lineage-15.1/lineage.dependencies
