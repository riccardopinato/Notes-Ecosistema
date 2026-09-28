import 'dart:convert';
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
      automations: const {
        'version': 1,
        'rules': [
          {
            'id': 'auto-1',
            'name': 'Inbox',
            'enabled': 1,
            'trigger': 'itemCreated',
            'subject': 'note',
            'requiredTag': null,
            'titleContains': null,
            'actionKind': 'addTag',
            'actionValue': 'inbox',
            'createdAt': 1,
            'updatedAt': 1,
          },
        ],
        'runs': [
          {
            'id': 'run-1',
            'ruleId': 'auto-1',
            'noteId': 'note-1',
            'trigger': 'itemCreated',
            'actionKind': 'addTag',
            'ranAt': 2,
          },
        ],
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
    expect((restored.automations['rules'] as List), hasLength(1));
    expect((restored.automations['runs'] as List), hasLength(1));
  });

  test('disaster recovery v1 remains readable without automations', () {
    final snapshot = BackupSnapshot(
      notes: [note('legacy')],
      collections: const [],
      drafts: const [],
    );
    final shared = SharedSpacesSnapshot(
      identity: SharedSpaces.newIdentity(),
      spaces: const [],
    );
    final current = DisasterRecoveryBundle.encodeLoaded(
      snapshot: snapshot,
      revisions: const [],
      blocks: const [],
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
      assets: const {},
      createdAt: 10,
    );

    final archive = ZipDecoder().decodeBytes(current);
    final legacy = Archive();
    for (final entry in archive) {
      if (entry.name == 'automations.json') continue;
      if (entry.name == 'manifest.json') {
        final manifest = jsonDecode(
          utf8.decode(entry.readBytes()!),
        ) as Map<String, dynamic>;
        manifest['version'] = 1;
        (manifest['files'] as Map<String, dynamic>).remove('automations.json');
        legacy.add(
          ArchiveFile.bytes(
            'manifest.json',
            Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
          ),
        );
      } else {
        legacy.add(ArchiveFile.bytes(entry.name, entry.readBytes()!));
      }
    }

    final restored = DisasterRecoveryBundle.decode(
      Uint8List.fromList(ZipEncoder().encodeBytes(legacy)),
    );
    expect(restored.snapshot.notes.single.id, 'note-1');
    expect(restored.automations['rules'], isEmpty);
    expect(restored.automations['runs'], isEmpty);
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
