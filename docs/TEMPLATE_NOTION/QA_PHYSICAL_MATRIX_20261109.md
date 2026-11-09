# Template QA — Notes Book Tracker + catalog

**Baseline:** `main@f057c81c92532cd22b504116c14ccef8a2ad6612` (PR #96/#97 integrated). QA additions in separate PR. Factory `d4ed1185d36d419228fba6b57a979cde308bd321`.

## Source / CI assertions

- `template_pilot_regression_test.dart`: cancel/empty title/emoji/optional section must return exactly zero or one `TemplateContent` through `TemplatesScreen.onUse`. This test is not a persisted-note physical test.
- Same Book Tracker payload survives `BackupCodec.encode/decode` without altering body/title/tags.
- Existing `template_step4_catalog_widget_test.dart` exercises Catalogo vs I miei without any purchase action.
- Run exact-HEAD `verify-web`, `verify`, `build-web`, then main-push gate; always cite the SHA, not a different historical green result.

## Manual browser / device acceptance — NOT VERIFIED

| ID | Preconditions / execution | PASS criteria |
|---|---|---|
| N-01 | Fresh account/local notes: Catalogo → Book Tracker → Annulla | No record inserted |
| N-02 | Create a Book Tracker with emoji title and turn off Da leggere | Exactly one editable Note, chosen sections, no duplicate |
| N-03 | Edit created note, close/reopen application, reload browser | Same note, title, tags and content preserved |
| N-04 | Save backup; restore to isolated test profile | Content and references preserved; no overwrite of another account |
| N-05 | Switch account A→B→A (only if app supports separate profiles) | No cross-account Book Tracker bleed or stale callback |
| N-06 | 320dp and 2× text scaling; keyboard, screen reader | Preview, cancel and confirm accessible without clipping |
| N-07 | Offline/reconnect in supported browser/device | Local content remains; no surprise server writes |

**Record required:** exact source SHA, test build/artifact identity if native, device/browser and OS, scenario IDs, observed result, screenshots/log reference and PASS/FAIL/BLOCKED. Browser preview ≠ Android native backup proof.

**Privacy / product:** PersonalTemplates and the canonical Note writer remain the only owners. No third-party template assets, silent sync, purchases or new database.
