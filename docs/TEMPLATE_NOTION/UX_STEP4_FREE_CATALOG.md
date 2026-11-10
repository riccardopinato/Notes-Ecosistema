# Notes-Ecosistema — Template catalog UX Step4

- Scope: use native `TemplatesScreen` as the **free catalog** and separate its built-in models from the existing **I miei** list of personal templates. This is not a paid template store, SKU listing, installation manager or entitlements feature.
- The Book Tracker still uses the exact Step3 `PageTemplates.bookTracker` and `onUse` canonical writer; other built-in models and personal template ownership remain unchanged.
- "I miei" is based on existing `PersonalTemplates.catalog`; no purchase history is implied and no extra persistence/sync is created.
- UI uses Flutter Material controls already present in Notes; step4 widget test verifies navigation and no accidental content writes.
- No imports, sources, media, CSV, or assets from third-party Notion templates. No paywall, payment intent, cloud, schema change, background delivery, account migration or CAP/Golden.
- Required before certification: exact-head tests/analyze/Web, verify current note create/edit/backup/account cases, accessibility at 320dp/text scale, and device QA. Device runtime, Store and billing **NOT VERIFIED**.
- Factory baseline `d4ed1185d36d419228fba6b57a979cde308bd321` (Master v27, Golden Index v29).


## Incremental Free catalog repair — 10 November 2026

- Correct existing built-in Notes templates so newlines are actual Dart `\n` escapes rather than literal backslash-n sequences. All default Meeting/Project/Study/Weekly Review and Daily bodies render editable headings/paragraphs without leaking escape text.
- Search applies to **all** free catalog entries, not only Book Tracker, and shows an explicit no-results state. Personal template catalog, Book Tracker dialog, onUse writer, persistence, backup and existing entitlements remain unchanged.
- Focused test `flutter_app/test/template_catalog_search_regression_test.dart`: newline fidelity, catalog filter, no accidental writes on search, one explicit use.
- No premium packs, Store, schema, provider, new copy of third-party assets, billing or new dependency. Exact-head CI and browser/device acceptance remain separate.
