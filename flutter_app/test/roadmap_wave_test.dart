import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/attachments.dart';
import 'package:notes_ecosistema/src/domain/blocks.dart';
import 'package:notes_ecosistema/src/domain/disaster_recovery.dart';
import 'package:notes_ecosistema/src/domain/document_workspace.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/open_export.dart';
import 'package:notes_ecosistema/src/domain/study.dart';
import 'package:notes_ecosistema/src/domain/sync.dart';
import 'package:notes_ecosistema/src/domain/visual_documents.dart';

void main() {
  Note note({
    String id = 'note-1',
    String title = 'Fonte',
    String body = 'Contenuto sorgente',
    int updatedAt = 10,
  }) =>
      Note(
        id: id,
        title: title,
        body: body,
        favorite: false,
        createdAt: 1,
        updatedAt: updatedAt,
        pinned: false,
        archived: false,
        tags: const [],
      );

  test('disaster recovery archive verifies components and CAS assets', () {
    final asset = Uint8List.fromList([1, 2, 3, 4]);
    final key = '${sha256.convert(asset)}.pdf';
    final encoded = DisasterRecoveryArchive.encode(
      components: {
        'workspace': {
          'version': 1,
          'notes': const [],
        },
        'properties': {'version': 1},
      },
      assets: {key: asset},
      exportedAt: 123,
    );

    final decoded = DisasterRecoveryArchive.decode(encoded);
    expect(decoded.exportedAt, 123);
    expect(decoded.components['workspace']?['version'], 1);
    expect(decoded.assets[key], asset);
  });

  test('disaster recovery rejects unsafe archive paths', () {
    final archive = Archive()
      ..add(ArchiveFile.string('../escape.txt', 'nope'))
      ..add(
        ArchiveFile.string(
          'manifest.json',
          '{"format":"notes-ecosystem-disaster-recovery",'
              '"version":1,"exportedAt":1,"entries":{}}',
        ),
      );
    final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    expect(
      () => DisasterRecoveryArchive.decode(bytes),
      throwsA(isA<FormatException>()),
    );
  });

  test('block reconciliation preserves IDs across text edits', () {
    final initial = BlockEditorCodec.parse(
      'note-1',
      '# Titolo\n\nPrimo testo',
      now: 10,
    );
    final reconciled = BlockEditorCodec.reconcile(
      'note-1',
      initial,
      '# Titolo\n\nTesto modificato',
      now: 20,
    );

    expect(reconciled, hasLength(initial.length));
    expect(reconciled[0].id, initial[0].id);
    expect(reconciled[1].id, initial[1].id);
    expect(reconciled[1].text, 'Testo modificato');
    expect(reconciled[1].updatedAt, 20);
  });

  test('Study keeps historical source evidence and detects live changes', () {
    final source = note();
    final item = StudyRules.fromNote(
      id: 'learning-1',
      note: source,
      prompt: 'Domanda',
      answer: 'Risposta',
      now: 20,
    );

    expect(item.sourceSnapshot, source.body);
    expect(StudyRules.sourceChanged(item, source), isFalse);
    expect(
      StudyRules.sourceChanged(
        item,
        note(body: 'Fonte cambiata', updatedAt: 30),
      ),
      isTrue,
    );
  });

  test('Study scheduler is replaceable and queue limits review debt', () {
    const scheduler = SimpleStudyScheduler();
    const current = ReviewState(
      itemId: 'learning-1',
      dueAt: 100,
      intervalDays: 3,
      ease: 2.5,
      repetitions: 2,
      lapses: 0,
    );
    final next = scheduler.next(
      current,
      StudyRating.good,
      reviewedAt: 1000,
    );
    expect(next.dueAt, greaterThan(1000));
    expect(next.repetitions, 3);
  });

  test('document OCR keeps original and corrected text separate', () {
    const layer = DocumentOcrLayer(
      noteId: 'note-1',
      assetKey:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf',
      page: 2,
      originalText: 'originale',
      correctedText: 'corretto',
      sourceFingerprint:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      updatedAt: 10,
    );
    DocumentWorkspaceRules.validateOcr(layer);
    expect(layer.searchableText, 'corretto');
    expect(layer.originalText, 'originale');
  });

  test('document annotation anchors page and normalized region', () {
    const item = DocumentAnnotation(
      id: 'annotation-1',
      noteId: 'note-1',
      assetKey:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf',
      page: 3,
      kind: DocumentAnnotationKind.highlight,
      x: 0.1,
      y: 0.2,
      width: 0.4,
      height: 0.1,
      text: 'citazione',
      createdAt: 1,
      updatedAt: 1,
    );
    DocumentWorkspaceRules.validateAnnotation(item);
    expect(item.anchor, contains('page=3'));
    expect(item.anchor, contains('annotation=annotation-1'));
  });

  test('hard purge does not silently resurrect a previously synced note', () {
    final base = SyncDocument.fromNote(note(), null);
    expect(
      decideMissingLocal(base, base),
      MissingLocalSyncDecision.propagatePurge,
    );
    final edited = SyncDocument.fromNote(
      note(body: 'Modifica offline remota', updatedAt: 30),
      null,
    );
    expect(
      decideMissingLocal(base, edited),
      MissingLocalSyncDecision.preserveRemoteThenPurge,
    );
    expect(
      decideMissingLocal(null, edited),
      MissingLocalSyncDecision.downloadRemote,
    );
  });

  test('open export contains readable objects, structured metadata and media',
      () {
    final asset = Uint8List.fromList([9, 8, 7]);
    final key = Attachments.key(asset, AttachmentType.pdf);
    final exported = OpenWorkspaceExport.encode(
      notes: [
        note(body: '[Documento](notes-asset://$key)'),
      ],
      assets: {key: asset},
      properties: {
        'version': 1,
        'definitions': const [],
        'values': const [],
      },
    );
    final archive = ZipDecoder().decodeBytes(exported, verify: true);
    final names = archive.map((entry) => entry.name).toSet();
    expect(names, contains('manifest.json'));
    expect(names, contains('README.md'));
    expect(names, contains('objects/00001.md'));
    expect(names, contains('assets/$key'));
    expect(names, contains('structured/properties.json'));
  });

  test('Sketchbook and Whiteboard share only the proven stroke primitive', () {
    const inkPoint = InkPoint(1, 2, 900);
    const boardPoint = BoardPoint(3, 4, 800);
    expect(inkPoint, isA<VisualPoint>());
    expect(boardPoint, isA<VisualPoint>());

    final ink = InkStroke(
      color: 1,
      width: 2,
      marker: false,
      points: const [inkPoint],
    );
    final board = BoardStroke(
      color: 1,
      width: 2,
      marker: false,
      points: const [boardPoint],
    );
    expect(ink, isA<VisualStroke<InkPoint>>());
    expect(board, isA<VisualStroke<BoardPoint>>());
  });
}
