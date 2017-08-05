#!/usr/bin/env python

# Copyright (C) 2017 Nicola Corna <nicola@corna.info>
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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

from sys import argv
from argparse import ArgumentParser
import os
import json

if __name__ == "__main__":
    parser = ArgumentParser(description='Generate an OpenDelta\'s builds.json '
                                        'file')
    parser.add_argument('path', metavar='PATH', type=str, help='the directory '
                        'containing the zips')
    parser.add_argument('-o', "--output", type=str, help='output file; '
                        'if unspecified, print to stdout')
    args = parser.parse_args()

    data = {}
    builddirs = ['./' + s for s in os.listdir(args.path)]
    for builddir in builddirs:
        try:
            builds = os.listdir(os.path.join(args.path, builddir))
            data[builddir] = [dict() for x in range(len(builds))]
            for i in range(0, len(builds)):
                data[builddir][i]["filename"] = builds[i]
                data[builddir][i]["timestamp"] = int(os.path.getmtime(
                    os.path.join(args.path, builddir, builds[i])))
        except OSError:
            pass

    if args.output:
        with open(args.output, "w") as f:
            f.write(json.dumps(data, separators=(',',':')))
    else:
        print(json.dumps(data, separators=(',',':')))
