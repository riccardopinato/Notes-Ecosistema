# ML10 / CAP-0116 — Notes Duplicate Review pilot
Date: 2026-11-04
Scope: bounded **read-only**, exact-content and near-lexical duplicate review, NOT full issue #48.

## Source provenance
- App-Factory-Core source `f5dad948dcc1096864cd4b9db84b9f0d86c9cb03`, `reference_engines/lib/src/local_ml_candidates.dart`; first-party MinHash 64 / 16 bands of 4 + Jaccard reference, exact-source Core CI https://github.com/riccardopinato/App-Factory-Core/actions/runs/41833497699.
- Scoped port: `flutter_app/lib/src/domain/note_duplicate_review.dart`, `flutter_app/test/note_duplicate_review_test.dart`.
- Consumer: `flutter_app/lib/src/screens/notes_screen.dart`, user-clicked **Similar notes**, 6 localized labels, two source previews, explicit open canonical editor; **no model runtime**, network, permissions, persistent local index, merge, delete or write.
- Input MUST be the caller's current account/ACL-authorized notes. Domain code only filters archived/deleted/task/visual and does not implement user role/ACL.
- CPU: bounded <=300 active notes and <=4000 chars per note, results <=30; uses `compute()` so large comparisons do not stall the UI on native Flutter.
- Jaccard bigrams are a lexical overlap signal; **LSH can miss near-duplicates**, and boilerplate may create false positives. Cannot be used for deletion/merge decision.

## Proof and omissions
- Deterministic ties/shuffles, hidden/deleted exclusion, stale revision, removed source, duplicate ID, max corpus, isolate transfer tests in `note_duplicate_review_test.dart`.
- Pre-open revalidation checks ID uniqueness, current source revision/content/tags/collection and active visibility. Canonical editor still controls final save ACL.
- **PENDING:** independent edit+merge with attachment diff, conflict resolution and reversible restore, cross-account membership switching while dialog is already open, secondary role permission enforcement, real corpus precision/recall and 100/300 mobile p50/p95 measurements, device test.
- No E4 hardware, E5 Golden promotion or issue #48 closure is implied. Keep Golden index/registry unchanged.

## Review acceptance
Run Flutter format/analyze/test + APK/web exact-head CI and review. On successful merge, update central capability evidence as partial only; app issue #48 remains open for explicit merge/undo and ACL gates.
