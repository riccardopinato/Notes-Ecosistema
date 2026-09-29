#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import pathlib
import sys
import urllib.request

REVISION = "b274efcb211a9eef48c9a88da4b43bd569696a39"
EXPECTED_SHA256 = "5e0a5daaadca1fbe1c518110bee6bbb1cc97a5e53a16a1e964d0af0186eac60a"
EXPECTED_BYTES = 1663992
URL = (
    "https://huggingface.co/Cactus-Compute/needle3/resolve/"
    f"{REVISION}/android-arm64/libneedle.a"
)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fetch_needle_android_runtime.py <output-file>", file=sys.stderr)
        return 2

    target = pathlib.Path(sys.argv[1])
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(target.suffix + ".tmp")

    request = urllib.request.Request(
        URL,
        headers={"User-Agent": "Notes-Ecosistema-build/0.56.3"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        with temporary.open("wb") as output:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                output.write(chunk)

    data = temporary.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if len(data) != EXPECTED_BYTES:
        temporary.unlink(missing_ok=True)
        raise SystemExit(
            f"Needle runtime size mismatch: {len(data)} != {EXPECTED_BYTES}"
        )
    if digest != EXPECTED_SHA256:
        temporary.unlink(missing_ok=True)
        raise SystemExit(
            f"Needle runtime SHA-256 mismatch: {digest} != {EXPECTED_SHA256}"
        )

    temporary.replace(target)
    print(
        f"Needle Android ARM64 runtime verified: {len(data)} bytes sha256={digest}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
