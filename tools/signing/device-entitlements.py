#!/usr/bin/env python3
"""Retain profile defaults, but claim the application's exact Keychain group."""
import plistlib
import subprocess
import sys
from pathlib import Path

profile = plistlib.loads(subprocess.check_output([
    # Same sandbox-compatible CMS decoding fallback used by rules_apple.
    "/usr/bin/openssl", "smime", "-inform", "der", "-verify", "-noverify", "-in", sys.argv[1],
], stderr=subprocess.PIPE))
entitlements = dict(profile["Entitlements"])
entitlements["application-identifier"] = "$(AppIdentifierPrefix)$(CFBundleIdentifier)"
entitlements["keychain-access-groups"] = ["$(AppIdentifierPrefix)$(CFBundleIdentifier)"]
# A complete device signature also needs its profile's team identity.
entitlements["com.apple.developer.team-identifier"] = profile["TeamIdentifier"][0]
Path(sys.argv[2]).write_bytes(plistlib.dumps(entitlements))
