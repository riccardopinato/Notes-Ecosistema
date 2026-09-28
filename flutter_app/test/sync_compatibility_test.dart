import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/planner.dart';
import 'package:notes_ecosistema/src/domain/sync.dart';

void main() {
  test('SyncCodec v6 preserves task metadata and Markdown body', () {
    final task = TaskDetails.empty().copyWith(
      due: '2026-10-01',
      priority: 3,
      reminderAt: 1790870400000,
      reminderTime: '18:00',
      reminderZone: 'Europe/Rome',
    );
    final document = SyncDocument(
      id: '11111111-1111-1111-1111-111111111111',
      title: 'Attività',
      body: '## Note\n\nCorpo esatto',
      collection: 'Lavoro',
      favorite: true,
      createdAt: 10,
      updatedAt: 20,
      pinned: true,
      archived: false,
      tags: const ['urgente'],
      taskJson: task.encode(),
    );

    final encoded = SyncCodec.encode(document);
    final decoded = SyncCodec.decode(encoded);

    expect(encoded.split('\n').first, startsWith('<!-- notes-ecosystem '));
    expect(decoded, document);
    expect(decoded.body, '## Note\n\nCorpo esatto');
    expect(
      TaskDetails.decode(decoded.taskJson!).reminderZone,
      'Europe/Rome',
    );
    expect(
      SyncCodec.filename(document.id),
      '${SyncCodec.hash(document.id)}.md',
    );
  });

  test('Sync decisions match three-way merge contract', () {
    const base = SyncDocument(
      id: 'n',
      title: 'Base',
      body: 'A',
      favorite: false,
      createdAt: 1,
      updatedAt: 1,
      pinned: false,
      archived: false,
      tags: [],
    );
    const local = SyncDocument(
      id: 'n',
      title: 'Local',
      body: 'A',
      favorite: false,
      createdAt: 1,
      updatedAt: 2,
      pinned: false,
      archived: false,
      tags: [],
    );
    const remote = SyncDocument(
      id: 'n',
      title: 'Remote',
      body: 'A',
      favorite: false,
      createdAt: 1,
      updatedAt: 3,
      pinned: false,
      archived: false,
      tags: [],
    );

    expect(decideSync(base, base, base), SyncDecision.same);
    expect(decideSync(base, base, remote), SyncDecision.download);
    expect(decideSync(base, local, base), SyncDecision.upload);
    expect(decideSync(base, local, remote), SyncDecision.conflict);
  });

  test('concurrent local edits are preserved before remote overwrite', () {
    const expected = SyncDocument(
      id: 'n',
      title: 'Prima',
      body: 'A',
      favorite: false,
      createdAt: 1,
      updatedAt: 2,
      pinned: false,
      archived: false,
      tags: [],
    );
    const current = SyncDocument(
      id: 'n',
      title: 'Modifica durante sync',
      body: 'B',
      favorite: false,
      createdAt: 1,
      updatedAt: 4,
      pinned: false,
      archived: false,
      tags: [],
    );
    const remote = SyncDocument(
      id: 'n',
      title: 'Remota',
      body: 'C',
      favorite: false,
      createdAt: 1,
      updatedAt: 3,
      pinned: false,
      archived: false,
      tags: [],
    );

    expect(
      shouldPreserveConcurrentLocal(
        expectedLocal: expected,
        currentLocal: current,
        remote: remote,
      ),
      isTrue,
    );
    expect(
      shouldPreserveConcurrentLocal(
        expectedLocal: expected,
        currentLocal: expected,
        remote: remote,
      ),
      isFalse,
    );
    expect(
      shouldPreserveConcurrentLocal(
        expectedLocal: expected,
        currentLocal: remote,
        remote: remote,
      ),
      isFalse,
    );
  });

  test('SyncDocument can be built from legacy Note', () {
    const note = Note(
      id: 'n',
      title: 'Pagina',
      body: 'Body',
      favorite: false,
      createdAt: 1,
      updatedAt: 2,
      pinned: false,
      archived: false,
      tags: ['tag'],
    );
    final document = SyncDocument.fromNote(note, 'Book');
    expect(document.collection, 'Book');
    expect(document.tags, ['tag']);
  });

  test('delete versus offline edit is a conflict, never last-write-wins', () {
    const base = SyncDocument(
      id: 'life',
      title: 'Base',
      body: 'A',
      favorite: false,
      createdAt: 1,
      updatedAt: 10,
      pinned: false,
      archived: false,
      tags: [],
    );
    const deleted = SyncDocument(
      id: 'life',
      title: 'Base',
      body: 'A',
      favorite: false,
      createdAt: 1,
      updatedAt: 20,
      deletedAt: 20,
      pinned: false,
      archived: false,
      tags: [],
    );
    const offlineEdit = SyncDocument(
      id: 'life',
      title: 'Edited offline',
      body: 'B',
      favorite: false,
      createdAt: 1,
      updatedAt: 30,
      pinned: false,
      archived: false,
      tags: [],
    );

    expect(
      decideSync(base, deleted, offlineEdit),
      SyncDecision.conflict,
    );
    expect(
      decideSync(base, offlineEdit, deleted),
      SyncDecision.conflict,
    );
  });

  test('restore after a synced tombstone is an explicit upload', () {
    const tombstone = SyncDocument(
      id: 'life',
      title: 'Deleted',
      body: 'A',
      favorite: false,
      createdAt: 1,
      updatedAt: 20,
      deletedAt: 20,
      pinned: false,
      archived: false,
      tags: [],
    );
    const restored = SyncDocument(
      id: 'life',
      title: 'Restored',
      body: 'A',
      favorite: false,
      createdAt: 1,
      updatedAt: 30,
      pinned: false,
      archived: false,
      tags: [],
    );

    expect(
      decideSync(tombstone, restored, tombstone),
      SyncDecision.upload,
    );
  });
}
