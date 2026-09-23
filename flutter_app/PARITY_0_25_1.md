# Flutter Final Parity & Release Prep 0.25.1

Branch audited: `flutter-port`  
Reference line: Kotlin `main` 0.25.x  
Rule: Kotlin `main` remains untouched until the Flutter release gate is green.

## Parity matrix

| Kotlin 0.25 area | Flutter 0.25.1 implementation | Status |
| --- | --- | --- |
| Room v8 notes/collections/drafts/revisions/content_blocks | `legacy_notes_database.dart` with Room identity compatibility | Parity |
| Notes editor, Markdown, checklist, tags, collections | `editor_screen.dart`, `editing.dart` | Parity |
| Local draft recovery + debounce + save/discard protection | Flutter editor + v8 drafts table | Parity |
| Revision history, preview and restore-as-draft | Flutter editor + v8 revisions table | Parity |
| Universal Block Editor | `blocks.dart`, `universal_block_editor.dart` | Parity |
| Library scopes, filters, order, bulk actions | `library.dart`, `notes_screen.dart` | Parity |
| Saved searches create/apply/rename/delete | SharedPreferences v1 codec + Notes UI | Parity |
| Diary | `diary.dart`, `diary_screen.dart` | Parity |
| Planner Agenda/Day/Week/Month | `planner.dart`, `planner_screen.dart` | Parity |
| Kanban/productivity | Planner Kanban/status workflow | Parity+ |
| Persistent Focus/Pomodoro | `focus.dart`, `focus_screen.dart` | Parity+ |
| Task reminders | Android WorkManager + Flutter reminder bridge | Parity |
| Reminder open/snooze deep action | Android intents + Flutter action bridge | Parity |
| Notification permission/settings fallback | Flutter settings + Android system settings bridge | Parity |
| Smart Capture OCR/document scan | ML Kit Flutter plugins | Parity |
| Safe web capture | `smart_capture.dart` public-destination checks + HTML extraction | Parity |
| Android share-in capture | Flutter Quick Capture bridge | Parity |
| Dynamic/pinned Quick Capture shortcuts | Android override + Flutter settings | Parity |
| Home Quick Capture widget | Android AppWidget override | Parity |
| Sketchbook | `visual_documents.dart`, `sketch_screen.dart` | Parity |
| Whiteboard/Mind Map | `visual_documents.dart`, `whiteboard_screen.dart` | Parity |
| Sketch/Whiteboard PNG export | Flutter RepaintBoundary export | Parity |
| Sketch/Whiteboard Android share | Native FileProvider chooser bridge | Parity |
| Attachments image/audio/file | content-addressed SHA-256 store | Parity |
| Camera and voice attachments | image_picker/record + attachment store | Parity |
| Attachment open/share | Android FileProvider bridge | Parity |
| Orphan attachment cleanup | `AttachmentStore.cleanup` + Settings action | Parity |
| JSON backup v6 | `backup.dart` | Kotlin-compatible |
| Complete media backup ZIP | `media_bundle.dart` | Parity |
| Safe media restore | manifest/path/size/SHA validation before install | Parity |
| GitHub Sync notes + attachments | `github_sync_service.dart` | Parity |
| Secure GitHub token | Android Keystore bridge | Parity |
| Quick Settings sync tile | Android TileService + Flutter bridge | Parity |
| Dark mode preference | SharedPreferences + Flutter theme | Parity |
| Templates/Knowledge tools | Flutter domain/screens/widgets | Parity |

## Backup invariants

The complete media bundle keeps `backup.json` compatible with Kotlin format v6 and stores immutable assets by SHA-256 key. Import rejects duplicate/unknown ZIP paths, missing assets, hash mismatches, oversized files, oversized expanded archives and unsupported manifest versions.

As on the Kotlin line, saved searches, local revision history and the currently running Focus timer are device-local state and are not exported by the logical backup.

## Release gate

0.25.1 is ready to replace the Kotlin application line only after the latest `flutter-port` CI completes all of these successfully:

1. format
2. analyze
3. unit/compatibility tests
4. debug APK
5. release APK split per ABI with R8
6. APK size report
7. release artifact upload

The split release APKs are the distribution-size optimization; no feature is removed to obtain the reduction.

## Post-gate

After a green release gate, preserve the Kotlin implementation as a legacy branch/tag and promote the Flutter line to the default development line. Shared Spaces belongs to 0.26 and is intentionally outside this parity release.
