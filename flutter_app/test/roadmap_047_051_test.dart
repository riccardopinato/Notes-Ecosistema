import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/import_provenance.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/obsidian_migration.dart';
import 'package:notes_ecosistema/src/domain/stable_links.dart';
import 'package:notes_ecosistema/src/domain/unified_retrieval.dart';

void main() {
  Note note({
    String title = 'Alpha',
    String body = 'Base',
    int updatedAt = 2,
  }) =>
      Note(
        id: 'note-1',
        title: title,
        body: body,
        favorite: false,
        createdAt: 1,
        updatedAt: updatedAt,
        pinned: false,
        archived: false,
        tags: const ['work'],
      );

  test('P2.5 import provenance distinguishes external and local changes', () {
    const identity = ImportIdentity(
      source: 'markdown',
      sourceInstance: 'vault',
      externalId: 'alpha.md',
    );
    final baseline = note();
    final baseFingerprint = ImportProvenance.fingerprintNote(baseline);
    final record = ImportRecord(
      identity: identity,
      targetNoteId: baseline.id,
      externalFingerprint: baseFingerprint,
      localFingerprint: baseFingerprint,
      lastBatchId: 'batch',
      importedAt: 1,
      lastSeenAt: 1,
    );

    ImportDocument external(String body) => ImportDocument(
          identity: identity,
          title: 'Alpha',
          body: body,
          tags: const ['work'],
          externalFingerprint: ImportProvenance.fingerprint(
            title: 'Alpha',
            body: body,
            tags: const ['work'],
          ),
        );

    expect(
      ImportProvenance.resolve(
        document: external('Base'),
        record: record,
        local: baseline,
      ).decision,
      ImportDecision.unchanged,
    );
    expect(
      ImportProvenance.resolve(
        document: external('Remote'),
        record: record,
        local: baseline,
      ).decision,
      ImportDecision.update,
    );
    expect(
      ImportProvenance.resolve(
        document: external('Base'),
        record: record,
        local: note(body: 'Local'),
      ).decision,
      ImportDecision.keepLocal,
    );
    expect(
      ImportProvenance.resolve(
        document: external('Remote'),
        record: record,
        local: note(body: 'Local'),
      ).decision,
      ImportDecision.conflict,
    );
  });

  test('unified retrieval ranks exact title and collapses sidecar hits', () {
    final documents = [
      const RetrievalDocument(
        id: 'note:1',
        noteId: '1',
        kind: RetrievalKind.note,
        title: 'Progetto Alpha',
        text: 'specifica generale',
      ),
      const RetrievalDocument(
        id: 'ocr:1',
        noteId: '1',
        kind: RetrievalKind.ocr,
        title: 'Progetto Alpha',
        text: 'fattura alpha',
      ),
      const RetrievalDocument(
        id: 'note:2',
        noteId: '2',
        kind: RetrievalKind.note,
        title: 'Beta',
        text: 'alpha in fondo',
      ),
    ];

    final hits = UnifiedRetrieval.search('progetto alpha', documents);
    expect(hits.first.document.noteId, '1');
    expect(hits.where((hit) => hit.document.noteId == '1'), hasLength(1));
  });

  test('stable links round-trip canonical object identifiers', () {
    final uri = StableLinks.object('abc-123');
    expect(uri.toString(), 'notes://object/abc-123');
    final parsed = StableLinks.parse(uri.toString());
    expect(parsed?.kind, StableLinkKind.object);
    expect(parsed?.id, 'abc-123');
    expect(StableLinks.parse('https://example.com'), isNull);
  });

  test('Obsidian migration preserves frontmatter and resolves wikilinks', () {
    final archive = Archive()
      ..add(
        ArchiveFile.string(
          'Work/Alpha.md',
          '---\ntitle: Alpha\ntags: [work, idea]\ncustom: keep\n---\n'
          'Link a [[Beta|seconda nota]] e ![[img.png]].',
        ),
      )
      ..add(
        ArchiveFile.string(
          'Work/Beta.md',
          '# Beta\nContenuto.',
        ),
      )
      ..add(
        ArchiveFile(
          'Work/img.png',
          4,
          Uint8List.fromList([1, 2, 3, 4]),
        ),
      );
    final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    final vault = ObsidianMigration.decode(bytes);
    expect(vault.documents, hasLength(2));
    expect(vault.assets, hasLength(1));
    expect(vault.report.unknownFrontMatterFields, contains('custom'));

    final lookup = ObsidianMigration.noteLookup(const [
      (path: 'Work/Alpha.md', title: 'Alpha', id: 'a'),
      (path: 'Work/Beta.md', title: 'Beta', id: 'b'),
    ]);
    final assetLookup = ObsidianMigration.assetLookup(const [
      (
        path: 'Work/img.png',
        key:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png'
      ),
    ]);
    final alpha =
        vault.documents.firstWhere((document) => document.title == 'Alpha');
    final body = ObsidianMigration.resolveBody(
      document: alpha,
      noteIdsByKey: lookup,
      assetKeysByPath: assetLookup,
    );
    expect(body, contains('(notes://object/b)'));
    expect(body, contains('notes-asset://'));
    expect(body, contains('obsidian_path'));
  });
}
