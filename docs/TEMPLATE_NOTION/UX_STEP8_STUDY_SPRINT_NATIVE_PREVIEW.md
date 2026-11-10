# Study Sprint Studio — Native Flutter preview (bounded)

Scope approved for implementation on 10 November 2026: a **read-only, interactive concept preview** for an original study template. Provisional UX approval remains revisable and is **not** a product, purchase or Premium distribution authorization.

- Entry point: existing `TemplatesScreen` Catalogo, separate card tagged **Concept · non acquistabile**.
- Runtime: `StudySprintConceptPreview`, 4 steps (discover, configure, preview, simulate) with manual source, up to eight topics, personal questions and review checkboxes.
- Data: local, ephemeral controllers only. **No call to `onUse`, Note writer, Task writer, cloud, notification, paywall or SKU**; leaving the screen loses the simulation.
- No external Notion assets or imported third-party content.
- UI copy uses an IT/EN/ES/FR/DE/PT concept label and introductory text. Existing app template forms still have bilingual/Italian labels; full l10n/accessibility certification is **NOT VERIFIED**.
- `flutter_app/test/study_sprint_concept_preview_test.dart`: traverses steps, requires explicit confirmation even for simulation and asserts `onUse` is never called.
- Existing Free and Personal templates, `PageTemplates` and `PersonalTemplates` remain untouched.
- All paid-template manifests remain `research_candidate`; no write adapter, versioned receipt, entitlement, billing, release or Golden promotion.

Next gated phase (not implemented here): product admission, value distinct from Free Studio, user-editable Note adapter through the canonical writer, idempotent receipt + owner/revision checks, backup/restore, account switch, error rollback, responsive 320dp, and exact-head Flutter CI/physical QA. Do not describe this preview as an installed template.
