import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/attachments.dart';
import 'package:notes_ecosistema/src/domain/backup.dart';
import 'package:notes_ecosistema/src/domain/blocks.dart';
import 'package:notes_ecosistema/src/domain/disaster_recovery.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/shared_spaces.dart';

void main() {
  Note note(String body) => Note(
        id: 'note-1',
        title: 'Recovery',
        body: body,
        favorite: false,
        createdAt: 1,
        updatedAt: 2,
        pinned: false,
        archived: false,
        tags: const ['backup'],
      );

  test('disaster recovery roundtrip preserves canonical IDs and blocks',
      () async {
    final asset = Uint8List.fromList('recovery-asset'.codeUnits);
    final key = Attachments.key(asset, AttachmentType.text);
    final body = Attachments.append('hello', key, 'a.txt');
    final snapshot = BackupSnapshot(
      notes: [note(body)],
      collections: const [],
      drafts: const [],
    );
    final block = ContentBlock(
      id: 'block-1',
      ownerId: 'note-1',
      position: 0,
      type: ContentBlockType.text,
      text: 'hello',
      createdAt: 1,
      updatedAt: 2,
    );
    final shared = SharedSpacesSnapshot(
      identity: SharedSpaces.newIdentity(),
      spaces: const [],
    );

    final bytes = DisasterRecoveryBundle.encodeLoaded(
      snapshot: snapshot,
      revisions: const [
        {
          'revisionId': 'rev-1',
          'noteId': 'note-1',
          'title': 'Old',
          'body': 'old',
          'collectionId': null,
          'savedAt': 1,
          'tagsJson': '[]',
        },
      ],
      blocks: [block],
      properties: const {'version': 1, 'definitions': [], 'values': []},
      knowledge: const {
        'version': 1,
        'sources': [],
        'relations': [],
        'syncedBlocks': [],
      },
      derivatives: const {'version': 1, 'derivatives': []},
      projects: const {'version': 1, 'projects': [], 'links': []},
      study: const {'version': 1, 'items': [], 'logs': []},
      documents: const {'version': 1, 'annotations': []},
      importProvenance: const {
        'version': 1,
        'records': [],
        'batches': [],
      },
      sharedSpaces: shared,
      assets: {key: asset},
      createdAt: 10,
    );

    final restored = DisasterRecoveryBundle.decode(bytes);
    expect(restored.snapshot.notes.single.id, 'note-1');
    expect(restored.blocks.single.id, 'block-1');
    expect(restored.revisions.single['revisionId'], 'rev-1');
    expect(restored.assets[key], orderedEquals(asset));
    expect(restored.createdAt, 10);
  });

  test('disaster recovery refuses undeclared or unsafe archive content', () {
    final archive = Archive()
      ..add(ArchiveFile.string('../escape.txt', 'unsafe'));
    final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));

    expect(
      () => DisasterRecoveryBundle.decode(bytes),
      throwsFormatException,
    );
  });
}
