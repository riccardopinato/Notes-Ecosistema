# Study Sprint Studio — Step 9: admission assessment, safe draft and QA

**Date:** 2026-11-10. **Factory baseline:** App-Factory-Core `ee72dbb1b0de2cd71bc4aac42c350853c6915159`, Master v27, Golden Index v29.

## Decision / product boundaries

**SOURCE PREPARATION ADMITTED; PRODUCT / COMMERCIAL ADMISSION NOT VERIFIED.**
The existing Notes app has no dedicated `docs/PRODUCT_BIBLE.md` today; `README.md`, `ROADMAP.md` and `docs/ARCHITETTURA.md` remain current sources of product/architecture authority. This step must not invent a replacement Product Bible or override them.

- Original, user-authored study workflow. Noncommercial concept preview stays in Catalogo; existing free `PageTemplates.study` and Book Tracker stay unchanged. Explain distinct value from the Free study template before admission.
- `catalog_status=research_candidate` and `rights_status=first_party_pending_review` are **unchanged**. No SKU, purchase, subscription, Plus entitlement, release or actual template installation.
- New `StudySprintDraftPlan.prepareForEditor(userConfirmed: ...)` is a **pure adapter** to existing `TemplateContent`, with explicit confirmation, strict field lengths, CRLF/LF normalization, zero-to-eight guard (reject 0 or more than 8) and original Markdown. It does not invoke `TemplatesScreen.onUse`, `WorkspaceController`, Task or sync. No new data store or write path.
- The future, separately gated activation must pass the validated result through `TemplatesScreen.onUse` → `_openTemplateDraft` → existing editable Note editor. **Opening editor must not persist**. Save uses the existing editor writer. Confirm cancel, account scope, save failure/retry and backup parity before enabling any create action.

## Automated QA added, pending exact-head CI

- `flutter_app/test/study_sprint_responsive_qa_test.dart`: widths 320 / 360 / 600, text scaling 1x / 2x, full navigation and simulated confirmation, no Flutter exception.
- `flutter_app/test/study_sprint_draft_plan_test.dart`: explicit consent required, no implicit Tasks, strict eight-topic cap, CRLF and rejected inputs.
- Reuse existing `study_sprint_concept_preview_test.dart` / `study_sprint_newline_regression_test.dart` and existing backup/compatibility tests; they do **not** prove a new saved Study Sprint note.
- Action controls use `Wrap` rather than a fixed Row for 320dp + large text; simulation completion is announced as a semantics live region.

## Manual/physical QA — NOT VERIFIED

| Scenario | Expected |
|---|---|
| N-01 — Android 320dp, font 200%, screen reader | No clipped actions or unreachable controls; meaningful focus order |
| N-02 — Web 360/600/1280dp, keyboard-only Tab/Enter/Space | All controls reachable; visible focus and correct semantics |
| N-03 — IT/EN/ES/FR/DE/PT and dark/light | Complete localized UI; **currently incomplete** in concept labels/input text |
| N-04 — cancel / reopen | Zero actual Note/Task writes; no persistent simulation |
| N-05 — future editor handoff, failure and retry | No automatic write, only one canonical Note on explicit save |
| N-06 — A→B→A, backup/export/import, device restore | No stale cross-account writes; original user content unchanged |

**Gate:** after CI green, review of scope and first-party rights, separate explicit approval to enable a real editor action. No Android physical/AppLab runtime, Store or distribution claim is made here.
