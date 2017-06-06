#!/usr/bin/env python
# -*- coding: utf-8 -*-

# clean_up.py - Remove old Android builds or delta files
# Copyright (C) 2017 Niccolò Izzo <izzoniccolo@gmail.com>
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

from os import walk, remove
from os.path import basename
from re import compile
from datetime import datetime
from argparse import ArgumentParser


def clean_path(path, builds_to_keep):
    files = []
    scandir = path[:-1] if path[-1] == "/" else path
    for (dirpath, dirnames, filenames) in walk(scandir):
        files.extend([dirpath+"/"+f for f in filenames])
    files_re = compile("lineage-[\d,.]+-[\d]+-[\w]+-[\w]+[.,\w]+")
    build_files = [f for f in files if files_re.match(basename(f))]
    build_re = compile("lineage-[\d,.]+-[\d]+-[\w]+-[\w]+")
    builds = {}
    # builds = {codename: {buildname: (date, [path, ...]), ...}, ...}
    for f in build_files:
        build_name = build_re.search(f).group(0)
        token_list = build_name.split("/")[-1].split("-")
        codename = token_list[4]
        date = datetime.strptime(token_list[2], "%Y%m%d")
        path = f
        if codename not in builds:
            builds[codename] = {build_name: (date, [path])}
        elif build_name not in builds[codename]:
            builds[codename][build_name] = (date, [path])
        else:
            builds[codename][build_name][1].append(path)
    # Clean up old builds
    for codename, build in builds.items():
        build_list = list(build.values())
        build_list.sort(key=lambda b: b[0])
        n_builds = len(build_list)
        if n_builds > builds_to_keep:
            for b in build_list[0:n_builds-builds_to_keep]:
                list(map(remove, b[1]))


def main():
    parser = ArgumentParser(description='Clean up old builds.')
    parser.add_argument('paths', metavar='PATH', type=str, nargs='+',
                        help='a path to be cleaned')
    parser.add_argument('-n', metavar='N_BUILDS', type=int, nargs='?',
                        default=3, help='select the number of builds to keep')
    args = parser.parse_args()
    for path in args.paths:
        clean_path(path, args.n)


if __name__ == "__main__":
    main()
