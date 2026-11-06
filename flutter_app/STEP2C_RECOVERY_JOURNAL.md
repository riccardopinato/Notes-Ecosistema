# Step 2C — Durable recovery journal (issue #75)

**State:** implementation candidate; physical Android SAF/process-death acceptance NOT VERIFIED.
**Baseline:** App Factory Core v27 / Golden Index v28 @ `3481a8190a5db5965bb22f84832094268d05be98`.
**Notes base:** `main@1a30a2c780dddc57fa03c6da8237bcdd147b8877`.
**Independent signing issue:** #71 remains OPEN; this work does not produce a production-signed APK.

## Algorithm

1. Decode and fully inspect the requested DisasterRecovery ZIP before any mutation.
2. Confirm destructive restore; acquire the Flutter Shared Live Sync pause and disable its Android native scheduler.
3. Create a complete safety ZIP from existing Notes state, export it, require explicit external re-selection and byte-for-byte readback.
4. Persist the same safety ZIP in private application-support storage using a flushed temporary file and an integrity-checkable SHA-256 marker. On Android, call a restricted native `fsyncDirectory` bridge **after the snapshot rename and again after the marker rename**; writes begin **only after both native directory barriers succeed**. Unsupported targets fail closed.
5. Apply imported CAS assets, main SQLite, Properties, Knowledge, Derivatives, Shared Spaces (including private invitation history), Projects, Study, Documents, Import Provenance and Automations through the existing canonical exact-restore APIs.
6. On exception, attempt immediate replay of the original archive; if that replay also fails, leave the marker and snapshot intact.
7. At next launch, keep all app controls and platform callbacks unavailable until any pending snapshot can be replayed and the marker removed. The Dart Live Sync entry point refuses to run whenever the journal marker remains.
8. Never delete pre-restore CAS assets inside the transaction. Automatic attachment garbage collection is deliberately excluded from the restore commit.

The explicit local journal is a *redoable rollback*, not a cross-SQLite atomic transaction. Writes are idempotent only insofar as each store's exact restore implementation remains repeatable. Native background jobs scheduled outside the running Flutter process remain a hardware/instrumentation acceptance concern.

## Tests added

- Journal persists and can be reopened, with injected directory-durability barriers for unit fixtures.
- Second restore cannot overwrite a pending undo snapshot.
- Missing, truncated or modified journal snapshot/manifest blocks recovery.
- Fault injection for eleven sequential simulated phases exercises rollback.
- A failed rollback retains the pending marker and retries after restart.
- A completed operation never spuriously replays the pre-restore snapshot.
- Failing either directory-durability barrier refuses to authorize writes; a marker left after the second failure remains recoverable.
- Shared Spaces snapshots preserve private invitation history.

The fault-injection test above validates the **coordinator**, not the actual SQLite/SAF implementations. Store-by-store instrumentation and Android process-kill testing are still required.

## Remaining issue #75 acceptance

- [ ] Flutter exact-head analyze/tests/build Web and APK/AAB CI.
- [ ] Real SQLite/SharedPreferences/asset store fault injection after every concrete store step.
- [ ] Android SAF: physical saved ZIP readback, low storage, process kill/power loss, restart, account switch, sync race and deferred native worker.
- [ ] Real-device Android durability validation of `Os.fsync` on the app-support `restore_journal` directory; unsupported OEM/filesystems must fail closed.
- [ ] End-to-end parity evidence for IDs, revisions, tombstones, permissions, media hashes, project/study/document sidecars.
- [ ] Real-device signoff with synthetic data. Only then consider closing #75.

If a journal cannot be read or replayed, Notes must remain in a blocking recovery screen. Users must retain their external safety ZIP; reinstalling/uninstalling is not a workaround. Web browsing remains available, but destructive multi-store restore is disabled there until a Web-specific durable journal exists.
