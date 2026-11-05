# Notes — Step 2: signing, safe upgrades and disaster recovery

Status: **implementation staged, not production-certified**. Source baseline before changes:
`main@d5f301838a0dcca270edcfd9babef19455fa0985`, `0.56.3+74`.
No key material is stored in Git, no released APK has been re-signed by this work.

## 1. Production signing vs CI artifacts

PR/push builds still produce **debug-signed** release-mode binaries. The CI labels their
release artifact names `CI-ONLY-NOT-FOR-PRODUCTION` and writes
`build/release-evidence/SIGNING_STATUS.txt`. Do not install these over an app with
valuable data and do not submit them to Play.

A manually dispatched workflow on `main` may enable
`production_signed: true`. The workflow then **fails closed** if any required
secret is missing, copies a keystore to an ephemeral runner path with restricted
permissions, configures Gradle from environment variables, checks the APK/AAB
signature fingerprints and rejects `CN=Android Debug`. Keys, passwords and raw
keystore bytes must never be uploaded or logged.

Configure these GitHub Actions secrets **outside the repository**:

| Secret | Meaning |
| --- | --- |
| `NOTES_ANDROID_KEYSTORE_BASE64` | Base64 encoding of the approved existing release/upload keystore |
| `NOTES_ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `NOTES_ANDROID_KEY_ALIAS` | Alias for the authorized signing key |
| `NOTES_ANDROID_KEY_PASSWORD` | Alias private-key password |
| `NOTES_ANDROID_CERT_SHA256` | 64-character hex SHA-256 of the authorized certificate |

The expected certificate is a **public identifier**; compare it with the
preexisting install/update chain before configuring the secret. No new random
keystore is an acceptable substitute for an already-installed app signature.

**Distinguish channels:** AABs submitted to Play App Signing use an **upload key**,
which can be distinct from the **app signing certificate delivered to devices**.
An APK directly signed with the upload key cannot necessarily update a
Play-installed build. A separately distributed APK must be signed by the
certificate authorized for that install path and must have a higher
`versionCode`. The workflow does not infer compatibility from the package name.

Before a release attempt:
1. Identify the installed package (currently CI uses `it.notes.ecosystem.lymlyc`),
   its cert SHA-256, versionCode, and any Play App Signing certificate.
2. Recover an authorized original signing key or explicitly follow a verified
   Play-managed rotation procedure. Do **not** silently create a replacement.
3. Establish a verified and restorable backup of **synthetic test data**.
4. Dispatch `Flutter Port CI` on `main` with `production_signed=true` using
   protected secrets; verify the exact-head CI, certificate evidence and hashes.
5. Test an in-place update of a **synthetic-data install** with matching signer,
   without uninstalling it. Verify note, task, attachment, canvas and sidecar
   identity before/after.
6. Only then consider a release candidate. If no matching private key exists,
   **in-place update is blocked**; design an export/restore migration verified
   on a device instead. Never tell users to uninstall before completing backup.

## 2. Restore safety gate

Disaster recovery already validates archive whitelist, manifest hashes,
attachments, schema, and references **before writes**. Its primary SQLite
database has a transaction, but the multiple sidecar stores are restored
sequentially and therefore **not globally atomic**.

Step 2 extracts a reusable validated recovery snapshot builder and requires a
**user-selected, externally saved pre-restore recovery ZIP** after confirmation
and *before the first persistent mutation*. Cancel or failure to save aborts
the operation. The exported snapshot is decoded in-memory for integrity first.

**External read-back verification:** after Save As, a separate file picker asks
the user to select the saved ZIP; Notes checks the entire external file
byte-for-byte against the generated snapshot, and aborts without writing when
the picker is cancelled, the file is unreadable, truncated or differs. This
checks storage-provider write completion and avoids treating a returned URI as
proof of persistence. The gate has deterministic unit regressions in
`test/recovery_safety_test.dart`. A cancelled ordinary backup export no longer
reports success.

**Limitations:** the file picker's successful return is not yet a verified
read-back from the external document provider; abrupt power loss can interrupt
cross-store restore, and automatic rollback across sidecars is **not**
implemented. Never claim zero-loss or `DEVICE_VERIFIED` on these grounds.
Preserve the safety archive if recovery fails; reopening the same backup is
not guaranteed to repair every partial state without verification.

## 3. Regression and device acceptance

Pure tests: `test/disaster_recovery_test.dart`,
`test/recovery_safety_gate_test.dart`, `test/templates_backup_knowledge_test.dart`,
`test/sync_compatibility_test.dart`, and
`tool/test_release_signing_config.py`.

Real-device scenarios remain **NOT RUN**:

| ID | Scenario | Required evidence |
| --- | --- | --- |
| UPG-01 | Upgrade between two signed versions with same certificate and increasing versionCode | `apksigner` cert match, installed version, before/after note and file hashes |
| UPG-02 | Same package with different signing certificate | Android rejects update **without uninstall** and without data change |
| UPG-03 | App process killed during backup export or restore | Existing archive/DB are recoverable; partial restores clearly surfaced |
| REC-01 | Cancel pre-restore safety export | No mutations of any note, task, project, asset, or sidecar |
| REC-02 | Corrupted/oversized ZIP and altered asset digest | Reject before any persistent write |
| REC-03 | Restore with live notes, attachments, drawing, deleted notes, task metadata, shared-space ACL | Validate stable IDs and all references on device |
| REC-04 | Simulated interrupted multi-store restore, restart and recovery with safety archive | Restore recovery and report orphan/collision checks; do not call this atomic |
| REC-05 | User exports safety ZIP via Android SAF and independently reimports it | Evidence the saved file is readable and hashes match |

Use only synthetic fixtures, never upload personal notes or keystore material.
Separate status: `CI PASS`, `DEVICE PASS`, `PLAY RELEASE`. This step **does
not** certify external storage, OEM behaviors, Play or compatibility with
historical debug-signed builds.

Tracking: [#71](https://github.com/riccardopinato/Notes-Ecosistema/issues/71),
[#72](https://github.com/riccardopinato/Notes-Ecosistema/issues/72),
and roadmap [#60](https://github.com/riccardopinato/Notes-Ecosistema/issues/60).

## CI remediation (same Step 2 PR)

The first CI run on PR #74 reported a false inability to extract the APK
certificate SHA-256 digest. The apksigner parser now normalizes whitespace and
colon-separated hex output and fails closed if no unique 64-digit fingerprint is
present. Expected digest matching and rejection of debug certificates on the
production-signing path remain mandatory. The exact-head rerun must pass before
merging; this change does not certify an actual protected release signer.
