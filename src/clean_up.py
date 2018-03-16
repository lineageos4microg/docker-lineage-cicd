#!/usr/bin/env python
# -*- coding: utf-8 -*-

# clean_up.py - Remove old Android builds or delta files
# Copyright (C) 2017-2018 Niccolò Izzo <izzoniccolo@gmail.com>
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


ROM_NAME = "lineage"

def clean_path(path, builds_to_keep, current_version, old_builds_to_keep,
               current_codename):
    files = []
    scandir = path[:-1] if path[-1] == "/" else path

    for (dirpath, dirnames, filenames) in walk(scandir):
        files.extend([dirpath+"/"+f for f in filenames])

    files_re = compile(ROM_NAME + "-[\d,.]+-[\d]+-[\w]+-[\w]+[.,\w]+")
    build_files = [f for f in files if files_re.match(basename(f))]
    build_re = compile(ROM_NAME + "-[\d,.]+-[\d]+-[\w]+-[\w]+")
    builds = {}

    # builds = {codename: {buildname: (date, [path, ...]), ...}, ...}
    for f in build_files:
        build_name = build_re.search(f).group(0)
        token_list = build_name.split("/")[-1].split("-")
        version = token_list[1]
        codename = token_list[4]
        build_hash = (version, codename)
        date = datetime.strptime(token_list[2], "%Y%m%d")
        path = f

        if build_hash not in builds:
            builds[build_hash] = {build_name: (date, [path])}
        elif build_name not in builds[build_hash]:
            builds[build_hash][build_name] = (date, [path])
        else:
            builds[build_hash][build_name][1].append(path)

    # Clean up old builds
    for build_hash, build in builds.items():
        build_list = list(build.values())
        build_list.sort(key=lambda b: b[0])
        n_builds = len(build_list)

        if not current_codename or build_hash[1] == current_codename:
            if current_version:
                if current_version == build_hash[0]:
                    keep_num = builds_to_keep
                else:
                    keep_num = old_builds_to_keep
            else:
                keep_num = builds_to_keep

            if n_builds > keep_num:
                for b in build_list[0:n_builds-keep_num]:
                    list(map(remove, b[1]))


def main():
    parser = ArgumentParser(description='Clean up old builds.')
    parser.add_argument('paths', metavar='PATH', type=str, nargs='+',
                        help='a path to be cleaned')
    parser.add_argument('-n', metavar='N_BUILDS', type=int, nargs='?',
                        default=3, help='select the number of builds to keep')
    parser.add_argument('-V', metavar="VERSION", type=str, nargs='?',
                        help='current LineageOS version: if specified, '
                        'N_BUILDS of version VERSION will be kept, while for '
                        'the others N_BUILDS_OLD will be used')
    parser.add_argument('-N', metavar='N_BUILDS_OLD', type=int, nargs='?',
                        default=1, help='select the number of builds to keep '
                        'when not of the specified version')
    parser.add_argument('-c', metavar='CODENAME', type=str, nargs='?',
                        help='clean only CODENAME zips')
    args = parser.parse_args()
    for path in args.paths:
        clean_path(path, args.n, args.V, args.N, args.c)


if __name__ == "__main__":
    main()
