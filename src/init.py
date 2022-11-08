from os import getenv
import shutil
import subprocess
from pathlib import Path
from itertools import product
from build import build
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


def init() -> None:
    # Copy the user scripts
    root_scripts = "/root/user_scripts"
    user_scripts = getvar("USERSCRIPTS_DIR")
    shutil.copytree(user_scripts, root_scripts)

    # Delete non-root files
    to_delete = []
    for path in Path(root_scripts).rglob("*"):
        if path.isdir(path):
            continue

        # Check if not owned by root
        if path.owner != "root":
            logging.warning("File not owned by root. Removing %s", path)
            to_delete.append(path)
            continue

        # Check if non-root can write (group or other)
        perm = oct(path.stat().st_mode)
        group_write = perm[-2] > "4"
        other_write = perm[-1] > "4"
        if group_write or other_write:
            logging.warning("File writable by non root users. Removing %s", path)
            to_delete.append(path)

    for f in to_delete:
        f.unlink()

    # Initialize CCache if it will be used
    use_ccache = getvar("USE_CCACHE") == "1"
    if use_ccache:
        size = getvar("CCACHE_SIZE")
        subprocess.run(["ccache", "-M", size], check=True, stderr=subprocess.STDOUT)

    # Initialize Git user information
    subprocess.run(
        ["git", "config", "--global", "user.name", getvar("USER_NAME")], check=True
    )
    subprocess.run(
        ["git", "config", "--global", "user.email", getvar("USER_MAIL")], check=True
    )

    sign_builds = getvar("SIGN_BUILDS").lower() == "true"
    if sign_builds:
        key_dir = Path(getvar("KEYS_DIR"))
        key_names = ["releasekey", "platform", "shared", "media", "networkstack"]
        key_exts = [".pk8", ".x509.pem"]
        key_aliases = ["cyngn-priv-app", "cyngn-app", "testkey"]

        # Generate keys if directory empty
        if not list(key_dir.glob("*")):
            logging.info("SIGN_BUILDS = true but empty $KEYS_DIR, generating new keys")
            key_subj = getvar("KEYS_SUBJECT")
            for k in key_names:
                logging.info("Generating %s..." % k)
                make_key(str(key_dir.joinpath(k)), key_subj)

        # Check that all expected key files exist
        for k, e in product(key_names, key_exts):
            path = key_dir.joinpath(k).with_suffix(e)
            if not path.exists():
                raise AssertionError('Expected key file "%s" does not exist' % path)

        # Create releasekey aliases
        for a, e in product(key_aliases, key_exts):
            src = key_dir.joinpath("releasekey").with_suffix(e)
            dst = key_dir.joinpath(a).with_suffix(e)
            dst.symlink_to(src)

    cron_time = getvar("CRONTAB_TIME")
    if cron_time == "now":
        build()
    else:
        scheduler = BlockingScheduler()
        scheduler.add_job(
            func=build,
            trigger=CronTrigger.from_crontab(cron_time),
            misfire_grace_time=None,  # Allow job to run as long as it needs
            coalesce=True,
            max_instances=1,  # Allow only one concurrent instance
        )

        # Run forever
        scheduler.start()


if __name__ == "__main__":

    logging.basicConfig(
        stream=sys.stdout,
        level=logging.INFO,
        format="[%(asctime)s] %(levelname)s %(message)s",
        datefmt="%c %Z",
    )

    init()
