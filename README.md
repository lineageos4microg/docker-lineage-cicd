# docker-lineage-cicd

Docker microservice for LineageOS Continuous Integration and Continuous Deployment

See [the wiki](https://github.com/lineageos4microg/docker-lineage-cicd/wiki) for updated documentation

# Web Site text

The following should be published on [the LineageOS for microG website](https://lineage.microg.org/). It is included here until the website can be updated


## How do I install the LineageOS for MicroG ROM?
See https://github.com/lineageos4microg/l4m-wiki/wiki/Installation

## Troubleshooting and support

The LineageOS for MicroG project is not in a position to offer much by way of technical support:

- the number of active volunteer maintainers / contributors is very small, and we spend what time we have trying to ensure that the process of making regular builds keeps going. We can generally investigate problems with the build tools, but not with the ROM itself;
- we don't have access to any devices for testing / debugging

The [project issue tracker][issue-tracker] is mostly for tracking problems with the Docker build tool. It is ***not*** intended for tracking problems with ***installing*** or ***running*** the LineageOS for MicroG ROM. If you run into such problems, our advice is to work through the following steps to see if they help. (Make a backup of your user apps & data first):
- full power off and restart
- factory reset
- format data partition
- install the most recent LineageOS for MicroG build for your device, from [here](https://download.lineage.microg.org/) following the [LOS installation instructions](https://wiki.lineageos.org/devices/).
- install the latest official LineageOS build from [here](https://download.lineageos.org/devices/)

For ***any*** problems, with building, installing, or running LineageOS for MicroG, we recommend that you ask for help in [the XDA Forum thread](https://xdaforums.com/t/lineageos-for-microg.3700997/) or in device specific [XDA forum threads](https://xdaforums.com/). The LineageOS for MicroG forum thread is not maintained by us, but there are many knowledgeable contributors there, who build and run the LineageOS for MicroG ROM on a wide variety of devices.

## Builds for devices no longer supported by LineageOS

When LineageOS stop supporting a device the last LineageOS for MicroG build for that device is moved to a device-specific subdirectory of [https://download.lineage.microg.org/archive/](https://download.lineage.microg.org/archive/)

~Old builds will be kept here as long as possible, until we need to free up storage space on [the download server](https://download.lineage.microg.org)~

Due to lack of disk space, we have had to move these old builds to storage which is not publicly visible. If you need to download an old build, then please post in [our XDA Forum thread](https://xdaforums.com/t/lineageos-for-microg.3700997/) and we will find a way of making it available to you.


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

We build for the same devices as LineageOS using [their list of build targets](https://github.com/LineageOS/hudson/blob/main/lineage-build-targets) as the input to our build run.

We currently make builds monthly, starting on the first day of the month. The devices included in a build run are defined by the content of the [LOS target list](https://github.com/LineageOS/hudson/blob/main/lineage-build-targets) ***at the point the build run starts***. Our monthly build run takes 15-16 days to complete. You can see the current status of the build in [the dedicated matrix room](https://matrix.to/#/#microg-lineage-os-builds:matrix.domainepublic.net)

If builds for any devices fail during a build run, we will try the build again ***after the main build run has completed***. If you do not see a new build for your device when you expect it, please check whether the build failure was reported in the matrix room. If it was, there is no need to report it - we will deal with it! If the failure was not reported in the matrix room, then please report it in [our issue tracker][issue-tracker] or in [the XDA Forums thread](https://xdaforums.com/t/lineageos-for-microg.3700997/)


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
[issue-tracker]: https://github.com/lineageos4microg/docker-lineage-cicd/issues
