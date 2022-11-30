import sys
from itertools import product
from pathlib import Path

sys.path.append("/root")
import build
import init


def test_key_gen(monkeypatch):
    def mock_build() -> None:
        print("mock build")

    monkeypatch.setenv("SIGN_BUILDS", "true")
    monkeypatch.setattr(build, "build", mock_build)

    initialize = init.Init()
    initialize.do()

    # Confirm all keys are generated
    for k, e in product(initialize.key_names, initialize.key_exts):
        path = Path("/srv/keys").joinpath(k).with_suffix(e)
        assert path.exists()
