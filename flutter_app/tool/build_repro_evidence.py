#!/usr/bin/env python3
"""Deterministic public build evidence; compare independent same-SHA runs.

Does not create an Android dependency lock or claim identical APK bytes.
Hashes pinned toolchain/template/lock and normalized Gradle runtime inventory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

SCHEMA = 1
EXPECTED_TEMPLATE = {
    "android/gradle/wrapper/gradle-wrapper.properties",
    "android/settings.gradle.kts",
}
_HEX = re.compile(r"^[0-9a-f]{64}$")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def template_hashes(text: str) -> dict[str, str]:
    output: dict[str, str] = {}
    for line in text.splitlines():
        values = line.strip().split()
        if len(values) != 2 or not _HEX.fullmatch(values[0]):
            raise ValueError("INVALID_ANDROID_TEMPLATE_DIGEST")
        digest, path = values
        if path not in EXPECTED_TEMPLATE or path in output:
            raise ValueError("ANDROID_TEMPLATE_PATH_MISMATCH")
        output[path] = digest
    if set(output) != EXPECTED_TEMPLATE:
        raise ValueError("ANDROID_TEMPLATE_DIGEST_INCOMPLETE")
    return dict(sorted(output.items()))


def runtime_inventory(report: str) -> list[str]:
    # Ignore Gradle task durations/runner paths. Keep each resolved entry,
    # including version override arrows, so transitive drift remains visible.
    entries = set()
    for line in report.splitlines():
        if "--- " not in line:
            continue
        entry = line.split("--- ", 1)[1].strip()
        for suffix in (" (*)", " (c)", " (n)"):
            entry = entry.replace(suffix, "")
        if entry:
            entries.add(entry)
    if not entries:
        raise ValueError("EMPTY_GRADLE_RUNTIME_INVENTORY")
    return sorted(entries)


def make_manifest(
    flutter_version: bytes,
    lockfile: bytes,
    android_template: bytes,
    gradle_report: bytes,
) -> dict[str, object]:
    if not flutter_version.strip() or not lockfile.strip():
        raise ValueError("MISSING_FLUTTER_OR_PUBSPEC_LOCK")
    try:
        version_text = flutter_version.decode("utf-8")
        inventory = runtime_inventory(gradle_report.decode("utf-8"))
        template = template_hashes(android_template.decode("utf-8"))
    except UnicodeDecodeError as error:
        raise ValueError("NON_UTF8_BUILD_EVIDENCE") from error
    if "Flutter 3.47.9" not in version_text.splitlines()[0]:
        raise ValueError("FLUTTER_VERSION_PIN_MISMATCH")
    return {
        "schema": SCHEMA,
        "flutter_version": version_text.splitlines()[0],
        "flutter_output_sha256": sha256(flutter_version),
        "pubspec_lock_sha256": sha256(lockfile),
        "android_template_sha256": template,
        "gradle_runtime_inventory_sha256": sha256(
            ("\n".join(inventory) + "\n").encode("utf-8")
        ),
        "gradle_runtime_distinct_entries": len(inventory),
    }


def compare_manifests(left: dict, right: dict) -> list[str]:
    mandatory = {
        "schema",
        "flutter_version",
        "flutter_output_sha256",
        "pubspec_lock_sha256",
        "android_template_sha256",
        "gradle_runtime_inventory_sha256",
        "gradle_runtime_distinct_entries",
    }
    if set(left) != mandatory or set(right) != mandatory:
        raise ValueError("INVALID_MANIFEST_KEYS")
    if left["schema"] != SCHEMA or right["schema"] != SCHEMA:
        raise ValueError("INVALID_MANIFEST_SCHEMA")
    return sorted(key for key in mandatory if left[key] != right[key])


def main() -> None:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="action", required=True)
    generate = commands.add_parser("generate")
    generate.add_argument("--flutter-version", type=Path, required=True)
    generate.add_argument("--lockfile", type=Path, required=True)
    generate.add_argument("--android-template", type=Path, required=True)
    generate.add_argument("--gradle-report", type=Path, required=True)
    generate.add_argument("--output", type=Path, required=True)
    compare = commands.add_parser("compare")
    compare.add_argument("first", type=Path)
    compare.add_argument("second", type=Path)
    args = parser.parse_args()
    try:
        if args.action == "generate":
            manifest = make_manifest(
                args.flutter_version.read_bytes(),
                args.lockfile.read_bytes(),
                args.android_template.read_bytes(),
                args.gradle_report.read_bytes(),
            )
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(
                json.dumps(manifest, sort_keys=True, indent=2) + "\n",
                encoding="utf-8",
            )
            print("BUILD_EVIDENCE_GENERATED")
        else:
            first = json.loads(args.first.read_text(encoding="utf-8"))
            second = json.loads(args.second.read_text(encoding="utf-8"))
            drift = compare_manifests(first, second)
            if drift:
                raise ValueError("BUILD_DEPENDENCY_DRIFT: " + ", ".join(drift))
            print("BUILD_EVIDENCE_MATCH (not a bitwise APK or signing proof)")
    except (ValueError, OSError, json.JSONDecodeError) as error:
        parser.exit(2, f"BLOCKED: {error}\n")


if __name__ == "__main__":
    main()
