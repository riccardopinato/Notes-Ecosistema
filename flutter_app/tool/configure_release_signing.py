#!/usr/bin/env python3
"""Configure an explicit Android release signingConfig; never persist secrets.

Used only by a manually-dispatched workflow on main with external keystore.
Ordinary PR CI must not invoke this script. The generated Gradle project is
ephemeral; private key material must never be written to the repository.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

DEBUG_CONFIG = 'signingConfig = signingConfigs.getByName("debug")'
PRODUCTION_CONFIG = 'signingConfig = signingConfigs.getByName("notesProduction")'
ANDROID_MARKER = "android {\n"

# Read passwords only during Gradle configuration via the process environment.
SIGNING_CONFIG = """    signingConfigs {
        create("notesProduction") {
            storeFile = file(System.getenv("NOTES_SIGNING_KEYSTORE_FILE")
                ?: error("Release keystore path missing"))
            storePassword = System.getenv("NOTES_SIGNING_STORE_PASSWORD")
                ?: error("Release store password missing")
            keyAlias = System.getenv("NOTES_SIGNING_KEY_ALIAS")
                ?: error("Release key alias missing")
            keyPassword = System.getenv("NOTES_SIGNING_KEY_PASSWORD")
                ?: error("Release key password missing")
        }
    }
"""


def configure_gradle(content: str) -> str:
    if content.count(DEBUG_CONFIG) != 1 or content.count(ANDROID_MARKER) < 1:
        raise ValueError("Unexpected generated Android build: fail closed")
    if PRODUCTION_CONFIG in content or 'create("notesProduction")' in content:
        raise ValueError("Production signing already configured; refusing to stack")
    content = content.replace(ANDROID_MARKER, ANDROID_MARKER + SIGNING_CONFIG, 1)
    return content.replace(DEBUG_CONFIG, PRODUCTION_CONFIG, 1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("gradle_file", type=Path)
    args = parser.parse_args()
    if os.environ.get("GITHUB_REF") != "refs/heads/main":
        raise SystemExit("Production signing requires the main branch")
    names = (
        "NOTES_SIGNING_KEYSTORE_FILE",
        "NOTES_SIGNING_STORE_PASSWORD",
        "NOTES_SIGNING_KEY_ALIAS",
        "NOTES_SIGNING_KEY_PASSWORD",
    )
    if any(not os.environ.get(name) for name in names):
        raise SystemExit("Missing signing credentials: fail closed")
    keyfile = Path(os.environ["NOTES_SIGNING_KEYSTORE_FILE"])
    if not keyfile.is_file() or keyfile.stat().st_size < 128:
        raise SystemExit("Missing or invalid keystore file")
    source = args.gradle_file.read_text(encoding="utf-8")
    result = configure_gradle(source)
    args.gradle_file.write_text(result, encoding="utf-8")
    print("Explicit production signingConfig configured (no secrets logged).")


if __name__ == "__main__":
    main()
