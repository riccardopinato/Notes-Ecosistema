# Production Audit 0.31

## Scope

MAXI STEP 0.31 is a stability, performance and production-readiness pass over
the Flutter application, Android bridge, SQLite access, GitHub sync, Shared
Spaces, background WorkManager integration and release CI.

Baseline: 0.30.0+38.

The pass intentionally avoids feature expansion and database schema changes.
The canonical SQLite/Room v8 compatibility contract remains unchanged.

## Highest-risk issue fixed: concurrent sync overwrite

Both GitHub sync engines previously made decisions from a local snapshot that
could become stale while network requests or asset downloads were running.

A local edit made after the snapshot but before a remote apply could therefore
be overwritten.

0.31 now:

- reads the relevant local SyncDocument immediately before decisions;
- re-reads it again before applying a remote document;
- preserves a changed local document as a conflict/local copy;
- records a normal GitHub conflict instead of replacing a concurrent edit;
- tests the concurrent-edit preservation rule.

This applies to both general GitHub Sync and Shared Spaces Live Sync.

## SQLite and workspace performance

The database layer now provides a targeted per-note SyncDocument query and a
lightweight ID-only sync query.

Hot-path improvements:

- saving one note no longer reloads every note and collection;
- favorite, pin, archive, trash and reminder snooze use targeted reloads;
- stale asynchronous full refreshes cannot overwrite newer state;
- block replacement uses one SQLite batch;
- backup-copy import uses one SQLite batch;
- bulk edit performs one consistency SELECT and one batched write instead of
  up to 500 SELECT + UPDATE pairs;
- general GitHub Sync no longer materializes every local SyncDocument merely
  to obtain IDs.

Full workspace refresh remains for operations that genuinely change many rows
or receive remote note content.

## Shared Spaces performance and reliability

0.31 reduces unnecessary network and disk churn while preserving manual sync
semantics.

- foreground resume triggers a silent sync when the last sync is old enough;
- resume sync is throttled to 30 seconds and respects retry backoff;
- authenticated GitHub identity is reused for up to 10 minutes;
- a changed GitHub config/token invalidates that identity cache immediately;
- manual sync always forces identity verification;
- full remote Shared Space discovery is reused for up to 5 minutes;
- manual sync always forces discovery;
- the normal 90-second content sync remains unchanged;
- duplicate GitHub branch-head verification requests were removed;
- an already-canonical GitHub identity is not re-persisted every sync;
- identical Shared Spaces snapshots are not written back to SharedPreferences;
- the workspace is refreshed only when a Shared sync actually downloaded data
  or created conflict copies;
- the activity cache is rewritten only when activity changed;
- marking activity read writes only read state, not the entire activity cache.

Remote activity is also rejected if an event claims a different spaceId than
the remote space.json containing it.

## Background WorkManager hardening

The Android background watcher now:

- advances its seen cursor even when notifications are disabled, avoiding a
  stale notification backlog when permission is granted later;
- treats permanent GitHub 4xx configuration/auth failures differently from
  transient network/server failures;
- verifies that the repository remains private and writable;
- exposes last check, last successful check and the last background error to
  the Flutter UI.

No foreground service was introduced.

## UI hot paths

- Shared Spaces builds a note lookup map once instead of repeatedly scanning
  the full note list for every space/content ID.
- Search avoids parsing Markdown checklists unless the active filter/type
  actually needs checklist information.
- Planner decodes TaskDetails once per planning pass and reuses the decoded
  metadata while sorting/indexing.
- Home caches the Focus SharedPreferences read across rebuilds.

## Attachment storage

Atomic attachment writes now clean their temporary file in a finally block.
Old incoming temp files are cleaned best-effort after one hour when the store
opens or cleanup runs.

This prevents interrupted writes from slowly consuming attachment storage.

## Activity/cache validation

Shared Activity cache validation now:

- rejects more than 30 cached spaces;
- rejects malformed non-map event rows with a controlled FormatException;
- keeps the existing 200-event-per-space bound.

## Lifecycle audit

Controllers/timers inspected in Editor, Sketch, Whiteboard, Focus, Smart
Capture and Universal Block Editor are disposed/cancelled by their owning
widgets. No permanent background Flutter timer/service was added.

## Release/CI hardening

The production workflow now:

- uses a real non-mutating dart-format gate;
- normalized the historical Dart source tree once, then restored CI to
  read-only/fail-fast mode;
- uses --no-pub after the explicit dependency step;
- enables Android release minification and resource shrinking;
- builds release APKs with Dart obfuscation and split debug info;
- uploads obfuscation symbols separately for crash symbolication;
- derives the release artifact version from pubspec instead of hardcoding it;
- enforces a 38 MiB budget on the arm64 release APK;
- continues to build the web preview even when GitHub Pages deployment is not
  enabled for the repository.

The 0.30 arm64 baseline measured by CI was approximately 34.3 MB. The 0.31
release must remain below the explicit 38 MiB gate.

## Deliberate non-changes

The following were reviewed but intentionally not changed in 0.31:

- SQLite schema/version and Room identity hash;
- 80 MiB bounded in-memory ZIP backup/import implementation;
- WorkManager 15-minute Android periodic minimum;
- 90-second foreground Shared content sync cadence;
- ML Kit scanner/OCR, image picker, recording and Markdown dependencies,
  because they are actively used product features rather than dead weight;
- CRDT/OT, realtime presence and WebSockets, which require a different
  collaboration architecture.

## Production acceptance criteria

0.31 is accepted only when the final main commit passes:

- canonical Dart format;
- flutter analyze;
- all Flutter tests;
- Android debug APK compilation;
- Android release split-per-ABI compilation with R8/resource shrinking;
- arm64 size regression gate;
- release APK artifact upload;
- obfuscation symbol artifact upload;
- web preview build.
