# Notes Web browser storage — Chromium QA (11 November 2026)

This testing lane runs **the production WebWorkspaceStore and shared_preferences_web browser storage adapter** inside a **QA-only Flutter Web target**, served from an isolated local origin in Chromium on GitHub Actions. It never connects to a user account and does not touch the public Pages origin, any real Notes workspace, or production journals.

Workflow: `.github/workflows/browser-storage-qa.yml`
Harness: `flutter_app/lib/web_storage_qa_entry.dart`
Browser assertions: `tool/browser_workspace_smoke.py`
Sanitized evidence artifact: `notes-browser-storage-qa/browser-workspace.json`.

## Intended cases

| ID | Scenario | Proof |
|---|---|---|
| NBR-01 | clean origin | blank startup |
| NBR-02 | save | localStorage slot acknowledged |
| NBR-03 | reload | synthetic note survives page reload |
| NBR-04 | export | JSON schema, title and SHA-256 integrity |
| NBR-05 | import | verified backup into separate clean browser profile |
| NBR-06 | import-reopen | content persists after import/reload |
| NBR-07 | tampered backup | checksum rejection and unchanged journal |
| NBR-08 | corrupt newest journal | fallback to last valid slot |
| NBR-09 | corrupt both slots | fail-closed, no automatic overwrite |
| NBR-10 | explicit recovery | valid backup restores after both-slot damage |
| NBR-11 | stale second tab | stale save rejected, first tab preserved |
| NBR-12 | oversize | quota guard preserves previously acknowledged content |

## Boundaries

- Browser tests are **actual Chromium + localStorage**, not only `SharedPreferences.setMockInitialValues`, but test the **storage adapter** through a dedicated harness, not the production `web_preview.dart` editor, dialogs, accessibility or file picker.
- They do not certify full browser UI, persistence under sudden power failure, native Android, simultaneous race atomicity or storage eviction. Those remain manual/user/browser QA gates.
- Do not claim PASS for any case until a workflow on the exact commit reports success and the artifact identifies the expected cases.
- No client secrets, images, real notes, personal data, PWA device login or production backup are used.
- App Factory pinned baseline: `ee72dbb1b0de2cd71bc4aac42c350853c6915159` (Master 27/Golden Index 29).
