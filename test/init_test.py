import sys
from itertools import product

sys.path.append("/root")
import build
import init
import os


def mock_build() -> None:
    print("mock build")


# No keys exist
def test_no_keys_exist(monkeypatch, tmp_path):
    key_dir = tmp_path / "srv" / "keys"
    key_dir.mkdir(parents=True)
    root_scripts_dir = tmp_path / "root" / "user_scripts"
    monkeypatch.setenv("SIGN_BUILDS", "true")
    monkeypatch.setenv("KEYS_DIR", str(key_dir))
    monkeypatch.setattr(build, "build", mock_build)
    initialize = init.Init()
    # Override to avoid interference with other tests
    initialize.root_scripts = str(root_scripts_dir)

    # Run init
    initialize.do()

    # Check that keys exist
    for k, e in product(initialize.key_names, initialize.key_exts):
        path = initialize.key_dir.joinpath(k).with_suffix(e)
        assert path.exists()


# All keys and proper key symlinks already exist
def test_all_keys_exist(monkeypatch, tmp_path):
    key_dir = tmp_path / "srv" / "keys"
    key_dir.mkdir(parents=True)
    root_scripts_dir = tmp_path / "root" / "user_scripts"
    monkeypatch.setenv("SIGN_BUILDS", "true")
    monkeypatch.setenv("KEYS_DIR", str(key_dir))
    monkeypatch.setattr(build, "build", mock_build)
    initialize = init.Init()
    # Override to avoid interference with other tests
    initialize.root_scripts = str(root_scripts_dir)

    # Make all keys
    for k in initialize.key_names:
        initialize.generate_key(k)

    # Make sym links
    for a, e in product(initialize.key_aliases, initialize.key_exts):
        src = initialize.key_dir.joinpath("releasekey").with_suffix(e)
        dst = initialize.key_dir.joinpath(a).with_suffix(e)
        dst.symlink_to(src)

    # Run init
    initialize.do()

    # Check that keys exist
    for k, e in product(initialize.key_names, initialize.key_exts):
        path = initialize.key_dir.joinpath(k).with_suffix(e)
        assert path.exists()


# Only "old" keys exist (keys needed before LineageOS 20)
def test_old_keys_exist(monkeypatch, tmp_path):
    key_dir = tmp_path / "srv" / "keys"
    key_dir.mkdir(parents=True)
    root_scripts_dir = tmp_path / "root" / "user_scripts"
    monkeypatch.setenv("SIGN_BUILDS", "true")
    monkeypatch.setenv("KEYS_DIR", str(key_dir))
    monkeypatch.setattr(build, "build", mock_build)
    initialize = init.Init()
    # Override to avoid interference with other tests
    initialize.root_scripts = str(root_scripts_dir)

    # Make all keys
    for k in initialize.key_names:
        if k not in initialize.new_key_names:
            initialize.generate_key(k)

    # Run init
    initialize.do()

    # Check that all keys exist
    for k, e in product(initialize.key_names, initialize.key_exts):
        path = initialize.key_dir.joinpath(k).with_suffix(e)
        assert path.exists()


# Bad sym links exist
def test_bad_links_exist(monkeypatch, tmp_path):
    key_dir = tmp_path / "srv" / "keys"
    key_dir.mkdir(parents=True)
    root_scripts_dir = tmp_path / "root" / "user_scripts"
    monkeypatch.setenv("SIGN_BUILDS", "true")
    monkeypatch.setenv("KEYS_DIR", str(key_dir))
    monkeypatch.setattr(build, "build", mock_build)
    initialize = init.Init()

    # Override to avoid interference with other tests
    initialize.root_scripts = str(root_scripts_dir)

    # Make keys
    for k in initialize.key_names:
        initialize.generate_key(k)

    # Make sym links to wrong target (platform instead of releasekey)
    for a, e in product(initialize.key_aliases, initialize.key_exts):
        src = initialize.key_dir.joinpath("platform").with_suffix(e)
        dst = initialize.key_dir.joinpath(a).with_suffix(e)
        dst.symlink_to(src)

    # Run init
    initialize.do()


# Non-root file exist in userscripts directory
def test_non_root_files(monkeypatch, tmp_path):
    user_scripts_dir = tmp_path / "srv" / "userscripts"
    user_scripts_dir.mkdir(parents=True)
    root_scripts_dir = tmp_path / "root" / "user_scripts"
    monkeypatch.setenv("SIGN_BUILDS", "false")
    monkeypatch.setenv("USERSCRIPTS_DIR", str(user_scripts_dir))
    monkeypatch.setattr(build, "build", mock_build)
    initialize = init.Init()
    # Override to avoid interference with other tests
    initialize.root_scripts = str(root_scripts_dir)
    os.umask(0o000)
    file7 = user_scripts_dir / "file677.sh"
    file7.touch(mode=0o677)
    file6 = user_scripts_dir / "file666.sh"
    file6.touch(mode=0o666)
    file3 = user_scripts_dir / "file633.sh"
    file3.touch(mode=0o633)
    file3 = user_scripts_dir / "file622.sh"
    file3.touch(mode=0o622)
    initialize.do()
