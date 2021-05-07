#!/usr/bin/env python3

# Docker wrapper script
# Copyright (c) 2021 Fjen <fjen@neboola.de>
# Copyright (C) 2021 Gerion Entrup <gerion.entrup@flump.de>
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

"""Build Lineage OS with MicroG without Docker."""

import argparse
import functools
import logging
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Iterator, Dict


def get_docker_cmd(docker_file: str) -> Iterator[str]:
    """Extract commands from Dockerfile."""
    with open(docker_file) as f:
        prev_lines = ""
        for line in f:
            if line.startswith("#") or not line.strip():
                # ignore comments / empty lines
                pass
            elif line.endswith("\\\n"):
                # save multi line commands
                prev_lines += line.strip().rstrip("\\")
            else:
                yield prev_lines + line.strip()
                prev_lines = ""


def with_prefix(prefix: str, path: str) -> str:
    """Add prefix to path"""
    return str(Path(prefix + path).absolute())


def main() -> None:
    parser = argparse.ArgumentParser(
        prog=sys.argv[0],
        description=sys.modules[__name__].__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--docker-file",
        "-d",
        help="docker file that should be converted",
        default="./Dockerfile",
    )
    parser.add_argument(
        "--prefix",
        "-p",
        help="set prefix path (all build files will reside in this folder)",
        default="./build",
    )
    parser.add_argument(
        "--env",
        "-e",
        help="set an environment variable",
        metavar="KEY=VALUE",
        action="append",
        default=[],
    )
    parser.add_argument(
        "--verbose",
        "-v",
        help="output more log messages",
        action="store_true",
        default=False,
    )

    args = parser.parse_args()
    with_p = functools.partial(with_prefix, args.prefix)

    logging.basicConfig(
        format="%(asctime)s %(name)s: %(message)s",
        level=logging.INFO if args.verbose else logging.WARNING,
    )

    env: Dict[str, str] = dict()
    env["PREFIX"] = str(Path(args.prefix).absolute())
    env["HOME"] = os.environ.get("HOME", "/")
    for env_var in args.env:
        key, value = env_var.split("=")
        env[key] = value

    workdir = "/"
    for cmd in get_docker_cmd(args.docker_file):
        cmd, *values = cmd.split(maxsplit=2)
        if cmd == "ENV" and values[0] not in env:
            # set environment
            env_value = values[1].strip("\"'")
            if values[0].endswith("_DIR"):
                env_value = with_p(env_value)
            env[values[0]] = env_value
        elif cmd == "RUN" and values[0] == "mkdir":
            # execute mkdirs
            subprocess.Popen(" ".join(values), env=env, shell=True).wait()
        elif cmd == "COPY":
            # copy files
            # FIXME: change to dirs_exists_ok=true with Python 3.8 instead of
            # removing the entire subtree
            shutil.rmtree(with_p(values[1]), ignore_errors=True)
            shutil.copytree(values[0], with_p(values[1]))
        elif cmd == "WORKDIR":
            # set workdir to env value if referenced, static otherwise
            workdir = env.get(values[0].lstrip("$"), values[0])
        elif cmd == "ENTRYPOINT":
            # start build
            cmd = with_p(values[0])
            pretty_env = "\n".join([f"{x}={y}" for x, y in sorted(env.items())])
            logging.info("Starting build process.")
            logging.info(f"Command: {cmd}")
            logging.info(f"Environment:\n{pretty_env}")
            logging.info(f"Working directory: {workdir}")
            subprocess.Popen(
                cmd, cwd=workdir, env={**os.environ, **env}, shell=True
            ).wait()


if __name__ == "__main__":
    main()
