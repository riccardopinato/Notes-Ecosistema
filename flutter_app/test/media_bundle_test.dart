import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/attachments.dart';
import 'package:notes_ecosistema/src/domain/backup.dart';
import 'package:notes_ecosistema/src/domain/media_bundle.dart';
import 'package:notes_ecosistema/src/domain/note.dart';

void main() {
  Note note({
    required String id,
    required String title,
    required String body,
  }) =>
      Note(
        id: id,
        title: title,
        body: body,
        favorite: false,
        createdAt: 1,
        updatedAt: 2,
        pinned: false,
        archived: false,
        tags: const [],
      );

  test('media bundle roundtrip keeps verified attachment bytes', () {
    final bytes = Uint8List.fromList('hello attachment'.codeUnits);
    final key = Attachments.key(bytes, AttachmentType.text);
    final body = Attachments.append('', key, 'hello.txt');
    final snapshot = BackupSnapshot(
      notes: [note(id: 'n1', title: 'Test', body: body)],
      collections: const [],
      drafts: const [],
    );

    final zip = MediaBundle.encodeLoaded(snapshot, {key: bytes});
    final preview = MediaBundle.decode(zip);

    expect(preview.snapshot.notes.single.id, 'n1');
    expect(preview.snapshot.notes.single.body, body);
    expect(preview.assets.keys, contains(key));
    expect(preview.assets[key], orderedEquals(bytes));
    expect(preview.assetBytes, bytes.length);
  });

  test('media bundle refuses missing referenced assets', () {
    final bytes = Uint8List.fromList('missing'.codeUnits);
    final key = Attachments.key(bytes, AttachmentType.text);
    final snapshot = BackupSnapshot(
      notes: [
        note(
          id: 'n1',
          title: 'Missing',
          body: Attachments.append('', key, 'missing.txt'),
        ),
      ],
      collections: const [],
      drafts: const [],
    );

    expect(
      () => MediaBundle.encodeLoaded(snapshot, const {}),
      throwsFormatException,
    );
  });

  test('media bundle also includes attachment refs from drafts', () {
    final bytes = Uint8List.fromList('draft'.codeUnits);
    final key = Attachments.key(bytes, AttachmentType.text);
    final snapshot = BackupSnapshot(
      notes: const [],
      collections: const [],
      drafts: [
        BackupDraft(
          id: 'd1',
          title: 'Draft',
          body: '[draft](notes-asset://$key)',
          updatedAt: 1,
          tags: const [],
        ),
      ],
    );

    expect(MediaBundle.referencedKeys(snapshot), {key});
    final zip = MediaBundle.encodeLoaded(snapshot, {key: bytes});
    final decoded = MediaBundle.decode(zip);
    expect(decoded.snapshot.drafts.single.id, 'd1');
  });

  test('media bundle v2 preserves complete sidecar payloads', () {
    final snapshot = BackupSnapshot(
      notes: [note(id: 'n1', title: 'Sidecar', body: 'Body')],
      collections: const [],
      drafts: const [],
    );
    final zip = MediaBundle.encodeLoaded(
      snapshot,
      const {},
      properties: const {
        'version': 1,
        'definitions': [],
        'values': [],
      },
      knowledge: const {
        'version': 1,
        'sources': [],
        'relations': [],
        'syncedBlocks': [],
      },
      derivatives: const {
        'version': 1,
        'derivatives': [],
      },
    );
    final preview = MediaBundle.decode(zip);
    expect(preview.properties['version'], 1);
    expect(preview.knowledge['version'], 1);
    expect(preview.derivatives['version'], 1);
  });
}
