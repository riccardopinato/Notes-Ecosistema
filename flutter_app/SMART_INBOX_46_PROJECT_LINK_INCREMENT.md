# Notes — Smart Inbox #46, Cantiere C: canonical project-link action

**Baseline:** `abbcab3b59bb67462238ad047fd619935a9acc0b` · **Scope:** increment 2 of issue #46 / CAP-0148. The previously shipped checklist→Task writer + Undo and tag→canonical-editor-draft remain unchanged.

## Workflow shipped by this branch
1. Read up to three source-backed suggestions from canonical, currently-visible private notes (already present).
2. Show original source excerpt, coded reason and explicit checklist/tag selections (already present), plus a list of **active private** Project Workspaces.
3. User explicitly chooses a project and taps **Link / Collega**. Cancel never writes. Labels exist in EN/IT/ES/FR/DE/PT.
4. Before the canonical `project_items` writer: reject unloaded/duplicate/archived/deleted source, staleness in the DB and visible workspace, shared-ownership/role ambiguity, missing/archived/shared project, already existing link, account switch and unavailable recovery gate.
5. Call existing `ProjectWorkspaceController.attach` / `ProjectStore.attach` and verify the resulting canonical link. Do not create a second task, note, project or provenance store. The canonical link connects projectId to the exact source noteId.
6. Offer bounded single-action Undo; it detaches only an unchanged link with the same owner and active private project. No automatic project mutation without consent.
7. Keep destructive cross-account/shared linking **blocked**; supporting shared roles requires an explicit role/ACL gate and regression evidence, not optimism.

## Source/test evidence in PR
- `flutter_app/lib/src/domain/smart_inbox_project_action.dart` — bounded source validation/eligible targets/Undo predicates.
- `flutter_app/test/smart_inbox_project_action_test.dart` — inaccessible/archived/deleted/private projects, source revisions and Undo.
- `flutter_app/lib/src/screens/home_screen.dart` — explicit project selection and six-locale confirmation/feedback.
- `flutter_app/lib/src/app.dart` — private-only canonical writer / transient receipt.
- Existing `smart_inbox_checklist_action.dart` and associated tests are preserved.

## Outstanding acceptance before closing #46
- [ ] True atomic cross-store final ACL/revision comparison at the project attach transaction boundary or an equivalent serialization guarantee; current pre-commit revalidation is not globally atomic with a concurrent sync process.
- [ ] Private tag edits are currently committed **by the canonical editor after a draft preview**, not by a standalone one-tap Smart Inbox writer; evaluate whether this satisfies the full CAP-0148 contract.
- [ ] End-to-end widget regression (three suggestions, empty selection, account switch, identity reset, shared role, async race, undo after external modification), all six locales on real UI.
- [ ] Exact-head CI and code review. No physical Android acceptance claimed.
- [ ] Final source reference/ACL evidence and source-to-writer provenance review before issue #46 closure.

**Coordination:** Home/navigation design PR #79 is documentation only and will not change `home_screen.dart` or `app.dart` until this branch is reconciled. Toolchain PR #80 edits only workflows/lockfile.
