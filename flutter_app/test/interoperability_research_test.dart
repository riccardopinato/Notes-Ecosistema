import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/markdown_interop.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/research.dart';

void main() {
  test('Markdown workspace export stays portable and re-importable', () {
    const note = Note(
      id: '11111111-1111-4111-8111-111111111111',
      title: 'Ricerca Alpha',
      body: 'Testo **Markdown**.',
      favorite: false,
      createdAt: 1,
      updatedAt: 2,
      pinned: false,
      archived: false,
      tags: ['research'],
    );
    final bytes = MarkdownWorkspaceBundle.encode([note]);
    final decoded = MarkdownWorkspaceBundle.decode(bytes);

    expect(decoded, hasLength(1));
    expect(decoded.single.title, 'Ricerca Alpha');
    expect(decoded.single.body, 'Testo **Markdown**.');
    expect(decoded.single.sourceId, note.id);
  });

  test('external changes never overwrite a dirty local document silently', () {
    final externalOnly = ExternalChangeResolver.resolve(
      base: 'base',
      local: 'base',
      external: 'remote',
    );
    expect(externalOnly.decision, ExternalChangeDecision.takeExternal);
    expect(externalOnly.text, 'remote');

    final conflict = ExternalChangeResolver.resolve(
      base: 'base',
      local: 'local edits',
      external: 'remote edits',
    );
    expect(conflict.decision, ExternalChangeDecision.conflict);
    expect(conflict.text, contains('local edits'));
    expect(conflict.text, contains('remote edits'));
  });

  test('research sources render navigable Markdown footnotes', () {
    const source = ResearchSource(
      id: 'source',
      noteId: 'note',
      title: 'Paper',
      url: 'https://example.com/paper',
      author: 'Autore',
      publishedAt: '2026',
      createdAt: 1,
      updatedAt: 1,
    );
    expect(
      source.footnote(2),
      '[^src2]: Autore — Paper — 2026 — https://example.com/paper',
    );
  });

  test('relation rollups aggregate labels deterministically', () {
    final rollup = RelationRollup.fromRelations(const [
      NoteRelation(
        id: '1',
        sourceId: 'a',
        targetId: 'b',
        label: 'related',
        updatedAt: 1,
      ),
      NoteRelation(
        id: '2',
        sourceId: 'a',
        targetId: 'c',
        label: 'related',
        updatedAt: 1,
      ),
      NoteRelation(
        id: '3',
        sourceId: 'a',
        targetId: 'd',
        label: 'supports',
        updatedAt: 1,
      ),
    ]);
    expect(rollup.total, 3);
    expect(rollup.byLabel['related'], 2);
    expect(rollup.byLabel['supports'], 1);
  });

  test('synced block keeps a canonical marker and resolves only for rendering', () {
    const id = '11111111-1111-4111-8111-111111111111';
    final marker = SyncedBlockCodec.reference(id);
    const block = SyncedBlock(id: id, markdown: '**Condiviso**', updatedAt: 1);
    expect(marker, '{{notes-synced:$id}}');
    expect(
      SyncedBlockCodec.resolve('Prima\n\n$marker\n\nDopo', {id: block}),
      'Prima\n\n**Condiviso**\n\nDopo',
    );
  });
}
