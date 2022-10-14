import build
import init
import os
from itertools import product


def test_key_gen(monkeypatch):
    def mock_build() -> None:
        print("mock build")

    monkeypatch.setenv("SIGN_BUILDS", "true")
    monkeypatch.setattr(build, "build", mock_build)

    init.init()

    # Confirm all keys are generated
    key_names = ["releasekey", "platform", "shared", "media", "networkstack"]
    key_exts = [".pk8", ".x509.pem"]
    for k, e in product(key_names, key_exts):
        path = os.path.join("/srv/keys", k + e)
        assert os.path.exists(path)
