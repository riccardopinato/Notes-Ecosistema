#!/usr/bin/env python3
"""Fail-closed public-metadata check before attempting an in-place upgrade.

No keystore, secrets, APK mutation, installation or Play publishing here.
For Play, compare the Play App Signing certificate that signs delivered APKs,
not the upload-key certificate reported by an AAB.
"""
from __future__ import annotations

import argparse
import re
from dataclasses import dataclass

APP_ID = "it.notes.ecosystem.lymlyc"
_HEX = re.compile(r"^[a-fA-F0-9]{64}$")


@dataclass(frozen=True)
class UpgradeEvidence:
    installed_package: str
    candidate_package: str
    installed_cert: str
    candidate_cert: str
    installed_code: int
    candidate_code: int
    candidate_subject: str
    channel: str = "direct"
    play_app_signing_cert: str | None = None


def normalize_cert(value: str) -> str:
    normalized = value.replace(":", "").replace(" ", "").lower()
    if not _HEX.fullmatch(normalized):
        raise ValueError("INVALID_CERTIFICATE_SHA256")
    return normalized


def verify_upgrade(evidence: UpgradeEvidence) -> str:
    if evidence.installed_package != APP_ID or evidence.candidate_package != APP_ID:
        raise ValueError("APPLICATION_ID_MISMATCH")
    if evidence.installed_code <= 0 or evidence.candidate_code <= evidence.installed_code:
        raise ValueError("VERSION_CODE_NOT_INCREASING")
    if evidence.channel not in ("direct", "play"):
        raise ValueError("UNKNOWN_DISTRIBUTION_CHANNEL")

    installed = normalize_cert(evidence.installed_cert)
    candidate = normalize_cert(evidence.candidate_cert)
    if "android debug" in evidence.candidate_subject.lower():
        raise ValueError("DEBUG_CERTIFICATE_NOT_FOR_DISTRIBUTION")
    if evidence.channel == "direct":
        if evidence.play_app_signing_cert is not None:
            raise ValueError("UNEXPECTED_PLAY_CERTIFICATE")
        if installed != candidate:
            raise ValueError("INCOMPATIBLE_INSTALLED_CERTIFICATE")
        return "DIRECT_CERT_AND_VERSION_MATCH"

    # The Play upload key may be different from the key Google uses to sign
    # delivered APKs. Never use AAB signing alone as proof of update safety.
    if not evidence.play_app_signing_cert:
        raise ValueError("MISSING_PLAY_APP_SIGNING_CERTIFICATE")
    if installed != normalize_cert(evidence.play_app_signing_cert):
        raise ValueError("INCOMPATIBLE_PLAY_APP_SIGNING_CERTIFICATE")
    return "PLAY_DELIVERY_CERT_AND_VERSION_MATCH"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Preflight public certificate/version evidence (no install)"
    )
    parser.add_argument("--installed-package", required=True)
    parser.add_argument("--candidate-package", required=True)
    parser.add_argument("--installed-cert", required=True)
    parser.add_argument("--candidate-cert", required=True)
    parser.add_argument("--installed-code", type=int, required=True)
    parser.add_argument("--candidate-code", type=int, required=True)
    parser.add_argument("--candidate-subject", required=True)
    parser.add_argument("--channel", choices=["direct", "play"], required=True)
    parser.add_argument("--play-app-signing-cert")
    args = parser.parse_args()
    try:
        result = verify_upgrade(
            UpgradeEvidence(
                installed_package=args.installed_package,
                candidate_package=args.candidate_package,
                installed_cert=args.installed_cert,
                candidate_cert=args.candidate_cert,
                installed_code=args.installed_code,
                candidate_code=args.candidate_code,
                candidate_subject=args.candidate_subject,
                channel=args.channel,
                play_app_signing_cert=args.play_app_signing_cert,
            )
        )
    except ValueError as error:
        parser.exit(2, f"BLOCKED: {error}\n")
    print(f"PREFLIGHT_PASS: {result} — requires real-device data-preservation test")


if __name__ == "__main__":
    main()
