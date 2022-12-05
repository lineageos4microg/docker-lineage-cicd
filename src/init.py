from os import getenv
import shutil
import subprocess
from pathlib import Path
from itertools import product
import build
from apscheduler.schedulers.blocking import BlockingScheduler
from apscheduler.triggers.cron import CronTrigger
import logging
import sys


def getvar(var: str) -> str:
    val = getenv(var)
    if val == "" or val is None:
        raise ValueError('Environment variable "%s" has an invalid value.' % var)
    return val


def make_key(key_path: str, key_subj: str) -> None:
    subprocess.run(
        ["/root/make_key", key_path, key_subj],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=True,
        input="\n".encode(),
    )


class Init:
    def __init__(self) -> None:
        self.root_scripts = "/root/user_scripts"
        self.user_scripts = getvar("USERSCRIPTS_DIR")
        self.use_ccache = getvar("USE_CCACHE").lower() in ["1", "true"]
        self.sign_builds = getvar("SIGN_BUILDS").lower() == "true"
        if self.sign_builds:
            self.key_dir = Path(getvar("KEYS_DIR"))
        if self.use_ccache:
            self.ccache_size = getvar("CCACHE_SIZE")
        self.cron_time = getvar("CRONTAB_TIME")
        self.git_username = getvar("USER_NAME")
        self.git_email = getvar("USER_MAIL")
        self.key_subj = getvar("KEYS_SUBJECT")
        self.key_names = [
            "releasekey",
            "platform",
            "shared",
            "media",
            "networkstack",
            "sdk_sandbox",
            "bluetooth",
        ]
        self.key_exts = [".pk8", ".x509.pem"]
        self.key_aliases = ["cyngn-priv-app", "cyngn-app", "testkey"]
        # New keys needed as of LOS20
        self.new_key_names = [
            "sdk_sandbox",
            "bluetooth",
        ]

        logging.basicConfig(
            stream=sys.stdout,
            level=logging.INFO,
            format="[%(asctime)s] %(levelname)s %(message)s",
            datefmt="%c %Z",
        )

    def generate_key(self, key_name: str) -> None:
        logging.info("Generating %s..." % key_name)
        make_key(str(self.key_dir.joinpath(key_name)), self.key_subj)

    def do(self) -> None:
        # Copy the user scripts
        shutil.copytree(self.user_scripts, self.root_scripts)

        # Delete non-root files
        to_delete = []
        for path in Path(self.root_scripts).rglob("*"):
            if path.is_dir():
                continue

            # Check if not owned by root
            if path.owner() != "root":
                logging.warning("File not owned by root. Removing %s", path)
                to_delete.append(path)
                continue

            # Check if non-root can write (group or other)
            perm = oct(path.stat().st_mode)
            modes_with_write = ["2", "3", "6", "7"]
            group_write = perm[-2] in modes_with_write
            other_write = perm[-1] in modes_with_write
            if group_write or other_write:
                logging.warning("File writable by non root users. Removing %s", path)
                to_delete.append(path)

        for f in to_delete:
            f.unlink()

        # Initialize CCache if it will be used
        if self.use_ccache:
            subprocess.run(
                ["ccache", "-M", self.ccache_size], check=True, stderr=subprocess.STDOUT
            )

        # Initialize Git user information
        subprocess.run(
            ["git", "config", "--global", "user.name", self.git_username], check=True
        )
        subprocess.run(
            ["git", "config", "--global", "user.email", self.git_email], check=True
        )

        if self.sign_builds:
            # Generate keys if directory empty
            if not list(self.key_dir.glob("*")):
                logging.info(
                    "SIGN_BUILDS = true but empty $KEYS_DIR, generating new keys"
                )
                for k in self.key_names:
                    self.generate_key(k)

            # Check that all expected key files exist.  If a LOS20 key does not exist, create it.
            for k, e in product(self.key_names, self.key_exts):
                path = self.key_dir.joinpath(k).with_suffix(e)
                if not path.exists():
                    if k in self.new_key_names:
                        self.generate_key(k)
                    else:
                        raise AssertionError(
                            'Expected key file "%s" does not exist' % path
                        )

            # Create releasekey aliases
            for a, e in product(self.key_aliases, self.key_exts):
                src = self.key_dir.joinpath("releasekey").with_suffix(e)
                dst = self.key_dir.joinpath(a).with_suffix(e)
                if dst.exists():
                    if dst.resolve() != src.resolve():
                        logging.warning(
                            "File %s being replaced by symlink pointing to %s"
                            % (str(dst), str(src))
                        )
                        dst.unlink()
                        dst.symlink_to(src)
                else:
                    dst.symlink_to(src)

        if self.cron_time == "now":
            build.build()
        else:
            scheduler = BlockingScheduler()
            scheduler.add_job(
                func=build.build,
                trigger=CronTrigger.from_crontab(self.cron_time),
                misfire_grace_time=None,  # Allow job to run as long as it needs
                coalesce=True,
                max_instances=1,  # Allow only one concurrent instance
            )

            # Run forever
            scheduler.start()


if __name__ == "__main__":
    initialize = Init()
    initialize.do()
