"""Configure an optional native Google OAuth client without storing credentials in Git."""
import os
import pathlib
import plistlib

path = pathlib.Path(__file__).resolve().parents[1] / "MochyMusicApp" / "Info.plist"
with path.open("rb") as stream:
    info = plistlib.load(stream)
client = os.environ.get("GOOGLE_OAUTH_CLIENT_ID", "").strip()
if client and (not client.endswith(".apps.googleusercontent.com") or any(c.isspace() for c in client)):
    raise SystemExit("GOOGLE_OAUTH_CLIENT_ID must be an iOS OAuth client ID")
info["GoogleOAuthClientID"] = client
if client:
    scheme = ".".join(reversed(client.split(".")))
    info["CFBundleURLTypes"] = [{"CFBundleURLName": "Google OAuth", "CFBundleURLSchemes": [scheme]}]
else:
    info.pop("CFBundleURLTypes", None)
with path.open("wb") as stream:
    plistlib.dump(info, stream, sort_keys=False)
print("Google OAuth callback configured" if client else "Google OAuth not configured; local features remain available")
