# TEMPLATE UX — Maxi-step 3 / Notes Book Tracker

- Approved pilot scope: free single editable note (Da leggere/In lettura/Conclusi); no Books database, cover, ratings, progress engine or billing.
- Entry: Modelli > Libreria personale > Anteprima/Usa modello > Titolo / Includi Da leggere > Crea nota.
- Implementation: PageTemplates.bookTracker produces TemplateContent; TemplatesScreen delegates to its existing onUse callback and canonical Notes note writer. Created notes remain owned by standard Note/backup/account/lifecycle semantics.
- No external Notion assets or third-party copyrighted content.
- Verification required: Flutter analyze + focused tests + smoke creation/backup/account switch, small/large viewport and accessibility before production certification.
- Runtime on physical devices, idempotency across persistence failures, six-language localization and product release remain NOT VERIFIED until evidence is collected.
- App Factory baseline: d4ed1185d36d419228fba6b57a979cde308bd321.
