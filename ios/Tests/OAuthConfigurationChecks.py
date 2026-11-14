import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile

source = pathlib.Path(__file__).resolve().parents[1] / "Scripts" / "configure_oauth.py"
with tempfile.TemporaryDirectory() as temporary:
    root = pathlib.Path(temporary)
    (root / "Scripts").mkdir()
    (root / "MochyMusicApp").mkdir()
    script = root / "Scripts" / source.name
    shutil.copyfile(source, script)
    target = root / "MochyMusicApp" / "Info.plist"
    target.write_bytes(plistlib.dumps({"CFBundleIdentifier": "app.mochy.music.ios"}))
    env = dict(os.environ, GOOGLE_OAUTH_CLIENT_ID="")
    subprocess.run([sys.executable, str(script)], env=env, check=True)
    result = plistlib.loads(target.read_bytes())
    assert result["GoogleOAuthClientID"] == "" and "CFBundleURLTypes" not in result
    env["GOOGLE_OAUTH_CLIENT_ID"] = "123-example.apps.googleusercontent.com"
    subprocess.run([sys.executable, str(script)], env=env, check=True)
    result = plistlib.loads(target.read_bytes())
    assert result["CFBundleURLTypes"][0]["CFBundleURLSchemes"] == ["com.googleusercontent.apps.123-example"]
    before = target.read_bytes()
    env["GOOGLE_OAUTH_CLIENT_ID"] = "not-a-client-id"
    invalid = subprocess.run([sys.executable, str(script)], env=env, capture_output=True)
    assert invalid.returncode != 0 and target.read_bytes() == before
print("PASS: absent OAuth configuration, reversed callback scheme and invalid client rejection")
