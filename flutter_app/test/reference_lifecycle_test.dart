import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/knowledge.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/project_workspace.dart';
import 'package:notes_ecosistema/src/domain/reference_lifecycle.dart';
import 'package:notes_ecosistema/src/domain/research.dart';

void main() {
  const noteId = '11111111-1111-1111-1111-111111111111';
  const otherId = '22222222-2222-2222-2222-222222222222';
  const blockId = '33333333-3333-3333-3333-333333333333';

  Note note({
    String id = noteId,
    String title = 'Titolo',
    int updatedAt = 10,
    int? deletedAt,
  }) =>
      Note(
        id: id,
        title: title,
        body: '',
        favorite: false,
        createdAt: 1,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        pinned: false,
        archived: false,
        tags: const [],
      );

  test('internal link survives rename because identity is ID based', () {
    final link = Knowledge.links(
      '[Titolo](notes://note/$noteId)',
    ).single;
    final renamed = note(title: 'Titolo rinominato', updatedAt: 20);

    final resolution = ReferenceLifecycle.internalLink(link, [renamed]);

    expect(resolution.state, ReferenceLifecycleState.resolved);
    expect(resolution.value?.title, 'Titolo rinominato');
    expect(resolution.canOpen, isTrue);
  });

  test('trash, restore and permanent delete have distinct states', () {
    final trashed = ReferenceLifecycle.noteById(
      id: noteId,
      notes: [note(deletedAt: 30)],
      kind: ReferenceKind.internalLink,
    );
    expect(trashed.state, ReferenceLifecycleState.deleted);
    expect(trashed.canOpen, isFalse);

    final restored = ReferenceLifecycle.noteById(
      id: noteId,
      notes: [note(updatedAt: 40)],
      kind: ReferenceKind.internalLink,
    );
    expect(restored.state, ReferenceLifecycleState.resolved);
    expect(restored.canOpen, isTrue);

    final purged = ReferenceLifecycle.noteById(
      id: noteId,
      notes: const [],
      kind: ReferenceKind.internalLink,
    );
    expect(purged.state, ReferenceLifecycleState.sourceMissing);
  });

  test('version-aware adapters can distinguish stale sources', () {
    final resolution = ReferenceLifecycle.noteById(
      id: noteId,
      notes: [note(updatedAt: 50)],
      kind: ReferenceKind.internalLink,
      expectedUpdatedAt: 40,
    );

    expect(resolution.state, ReferenceLifecycleState.stale);
    expect(resolution.canOpen, isTrue);
  });

  test('duplicate IDs are reported as ambiguous instead of guessed', () {
    final resolution = ReferenceLifecycle.noteById(
      id: noteId,
      notes: [
        note(title: 'A'),
        note(title: 'B'),
      ],
      kind: ReferenceKind.internalLink,
    );

    expect(resolution.state, ReferenceLifecycleState.ambiguous);
    expect(resolution.value, isNull);
  });

  test('relation lifecycle resolves the opposite endpoint', () {
    const relation = NoteRelation(
      id: 'relation-1',
      sourceId: noteId,
      targetId: otherId,
      label: 'related',
      updatedAt: 10,
    );

    final active = ReferenceLifecycle.relationOther(
      relation: relation,
      currentNoteId: noteId,
      notes: [note(), note(id: otherId, title: 'Altra')],
    );
    expect(active.otherNoteId, otherId);
    expect(active.target.state, ReferenceLifecycleState.resolved);

    final deleted = ReferenceLifecycle.relationOther(
      relation: relation,
      currentNoteId: noteId,
      notes: [
        note(),
        note(id: otherId, title: 'Altra', deletedAt: 20),
      ],
    );
    expect(deleted.target.state, ReferenceLifecycleState.deleted);
  });

  test('synced block distinguishes resolved, stale and missing', () {
    const block = SyncedBlock(
      id: blockId,
      markdown: 'Contenuto',
      updatedAt: 30,
    );
    final blocks = {blockId: block};

    expect(
      ReferenceLifecycle.syncedBlock(id: blockId, blocks: blocks).state,
      ReferenceLifecycleState.resolved,
    );
    expect(
      ReferenceLifecycle.syncedBlock(
        id: blockId,
        blocks: blocks,
        expectedUpdatedAt: 20,
      ).state,
      ReferenceLifecycleState.stale,
    );
    expect(
      ReferenceLifecycle.syncedBlock(
        id: '44444444-4444-4444-4444-444444444444',
        blocks: blocks,
      ).state,
      ReferenceLifecycleState.sourceMissing,
    );
  });

  test('project links keep canonical notes and hide lifecycle-inactive targets',
      () {
    final links = [
      const ProjectItemLink(
        projectId: 'project-1',
        noteId: noteId,
        position: 0,
        addedAt: 1,
        updatedAt: 1,
      ),
      const ProjectItemLink(
        projectId: 'project-1',
        noteId: otherId,
        position: 1,
        addedAt: 1,
        updatedAt: 1,
      ),
    ];

    final items = ProjectWorkViews.project(
      notes: [
        note(),
        note(id: otherId, deletedAt: 20),
      ],
      links: links,
    );

    expect(items.map((item) => item.note.id), [noteId]);
  });

  test('shared-space content references reuse the same note lifecycle contract',
      () {
    final resolution = ReferenceLifecycle.noteById(
      id: noteId,
      notes: [note(deletedAt: 20)],
      kind: ReferenceKind.sharedSpaceContent,
    );

    expect(resolution.kind, ReferenceKind.sharedSpaceContent);
    expect(resolution.state, ReferenceLifecycleState.deleted);
  });

  test('backlinks remain derived from canonical note links', () {
    final source = note(
      id: otherId,
      title: 'Fonte',
    ).copyWith(body: '[Target](notes://note/$noteId)');
    final backlinks = [source]
        .where(
          (item) => Knowledge.links(item.body).any((link) => link.id == noteId),
        )
        .toList(growable: false);

    expect(backlinks.single.id, otherId);
  });
}
