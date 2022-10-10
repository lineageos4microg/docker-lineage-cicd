import datetime
import glob
import os
import pathlib
import shutil
import subprocess
import tempfile


def getvar(var: str) -> str:
    val = os.getenv(var)
    if val == "" or val is None:
        raise ValueError('Environment variable "%s" has an invalid value.' % var)
    return val


def prepend_date(msg: str) -> str:
    date = datetime.datetime.now().astimezone().strftime("%c %Z")
    return "[%s] %s" % (date, msg)


def print_with_date(msg: str) -> None:
    print(prepend_date(msg))


def main() -> None:
    # Copy the user scripts
    root_scripts = "/root/user_scripts"
    user_scripts = getvar("USERSCRIPTS_DIR")
    shutil.copytree(user_scripts, root_scripts)

    # Delete non-root files
    to_delete = []
    for filename in glob.iglob(os.path.join(root_scripts, "**/**"), recursive=True):
        if os.path.isdir(filename):
            continue

        # Check if not owned by root
        f = pathlib.Path(filename)
        if f.owner != "root":
            print_with_date("File not owned by root. Removing %s", filename)
            to_delete.append(filename)
            continue

        # Check if non-root can write (group or other)
        perm = oct(os.stat(filename).st_mode)
        group_write = perm[-2] > "4"
        other_write = perm[-1] > "4"
        if group_write or other_write:
            print_with_date("File writable by non root users. Removing %s", filename)
            to_delete.append(filename)

    for f in to_delete:
        os.remove(f)

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
        key_dir = getvar("KEYS_DIR")
        key_names = ["releasekey", "platform", "shared", "media", "networkstack"]
        key_exts = [".pk8", ".x509.pem"]

        # Generate keys if directory empty
        if len(os.listdir(key_dir)) == 0:
            print_with_date(
                "SIGN_BUILDS = true but empty $KEYS_DIR, generating new keys"
            )
            keys_subj = getvar("KEYS_SUBJECT")
            for k in key_names:
                print_with_date("Generating %s..." % k)
                subprocess.run(
                    ["/root/make_key", os.path.join(key_dir, k), keys_subj],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=True,
                    input="\n".encode(),
                )

        # Check that all expected key files exist
        for k in key_names:
            for e in key_exts:
                path = os.path.join(key_dir, k + e)
                if not os.path.exists(path):
                    raise AssertionError(
                        prepend_date('Expected key file "%s" does not exist' % path)
                    )

        for alias in ["cyngn-priv-app", "cyngn-app", "testkey"]:
            for e in key_exts:
                subprocess.run(
                    [
                        "ln",
                        "-sf",
                        os.path.join(key_dir, "releasekey" + e),
                        os.path.join(key_dir, alias + e),
                    ],
                    check=True,
                )

    cron_time = getvar("CRONTAB_TIME")
    if cron_time == "now":
        subprocess.run(["/root/build.sh"], check=True)
    else:
        # Initialize the cronjob
        cron_lines = []
        cron_lines.append("SHELL=/bin/bash\n")
        for k, v in os.environ:
            if k == "_" or v == "":
                continue
            cron_lines.append("%s=%s\n", k, v)
        cron_lines.append(
            "\n%s /usr/bin/flock -n /var/lock/build.lock /root/build.sh >> /var/log/docker.log 2>&1\n"
            % cron_time,
        )
        with tempfile.NamedTemporaryFile() as fp:
            fp.writelines(cron_lines)
            subprocess.run("crontab", fp.name, check=True)


if __name__ == "__main__":
    main()
