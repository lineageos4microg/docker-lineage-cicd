#!/bin/bash

# Slimmed-down Docker build script
# Copyright (c) 2017 Julian Xhokaxhiu
# Copyright (C) 2017-2018 Nicola Corna <nicola@corna.info>
# Copyright (C) 2024 Pete Fotheringham <petefoth@e.email>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>


# Outline
# - Call `begin.sh`
# - Handle parameters and environment variables
#      -  CLEAN_OUTDIR
#      -  PARALLEL_JOBS
#      -  RETRY_FETCHES
# - handle manifests
# - Sync mirror
# - Branch-specific stuff
# -  main sync and build loop For each device in `$DEVICE_LIST`
#     - setup build overlay
#     - `repo init`
#     - `repo sync`
#     - Call `before.sh`
#     - `breakfast` - in case of failure, call
#         - `post-build.sh`
#         - `do_cleanup`
#     - `mka`
#     - move artefacts to `ZIPDIR`
#         - ROM zip file
#         - `.img` files
#         - create the checksum files
#         - Remove old zips and logs
#     - call `post-build.sh`
#     - call `do_cleanup`
# - call `end.sh`
