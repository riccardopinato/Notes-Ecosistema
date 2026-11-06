import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/attachments.dart';
import 'package:notes_ecosistema/src/domain/backup.dart';
import 'package:notes_ecosistema/src/domain/disaster_recovery.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/shared_spaces.dart';

Uint8List syntheticRecovery({bool withAsset = false}) {
  final asset = Uint8List.fromList(utf8.encode('synthetic safe content'));
  final key = Attachments.key(asset, AttachmentType.text);
  final body = withAsset
      ? Attachments.append('safe content', key, 'fixture.txt')
      : 'safe content';
  final snapshot = BackupSnapshot(
    notes: [
      Note(
        id: 'synthetic-note',
        title: 'Synthetic',
        body: body,
        favorite: false,
        createdAt: 1,
        updatedAt: 2,
        pinned: false,
        archived: false,
        tags: const [],
      ),
    ],
    collections: const [],
    drafts: const [],
  );
  return DisasterRecoveryBundle.encodeLoaded(
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
    automations: const {'version': 1, 'rules': [], 'runs': []},
    sharedSpaces: SharedSpacesSnapshot(
      identity: SharedSpaces.newIdentity(),
      spaces: const [],
    ),
    assets: withAsset ? {key: asset} : const {},
    createdAt: 1234,
  );
}

void main() {
  test('synthetic pre-restore archive decodes before any write', () {
    final input = syntheticRecovery(withAsset: true);
    final preview = DisasterRecoveryBundle.decode(input);
    expect(preview.snapshot.notes.single.id, 'synthetic-note');
    expect(preview.assets, hasLength(1));
    expect(preview.createdAt, 1234);
  });

  test('corrupted backup payload fails closed and original stays readable', () {
    final original = syntheticRecovery();
    final archive = ZipDecoder().decodeBytes(original);
    final tampered = Archive();

    for (final entry in archive) {
      final originalBytes = entry.readBytes()!;
      final bytes = entry.name == 'backup.json'
          ? Uint8List.fromList([...originalBytes, 32])
          : originalBytes;
      tampered.add(ArchiveFile.bytes(entry.name, bytes));
    }

    final corrupted = Uint8List.fromList(ZipEncoder().encodeBytes(tampered));
    expect(
      () => DisasterRecoveryBundle.decode(corrupted),
      throwsFormatException,
    );
    expect(
      DisasterRecoveryBundle.decode(original).snapshot.notes.single.body,
      'safe content',
    );
  });

  test('forged manifest checksum cannot bypass attachment identity', () {
    final original = syntheticRecovery(withAsset: true);
    final archive = ZipDecoder().decodeBytes(original);
    final preview = DisasterRecoveryBundle.decode(original);
    final key = preview.assets.keys.single;
    final filename = 'assets/$key';
    final corruptedAsset = Uint8List.fromList(utf8.encode('altered content'));

    final manifestEntry = archive.firstWhere(
      (entry) => entry.name == 'manifest.json',
    );
    final manifest = jsonDecode(utf8.decode(manifestEntry.readBytes()!))
        as Map<String, dynamic>;
    final files = manifest['files'] as Map<String, dynamic>;
    final assetMetadata = files[filename] as Map<String, dynamic>;
    assetMetadata['bytes'] = corruptedAsset.length;
    assetMetadata['sha256'] = sha256.convert(corruptedAsset).toString();

    final forged = Archive();
    for (final entry in archive) {
      final bytes = entry.name == filename
          ? corruptedAsset
          : entry.name == 'manifest.json'
              ? Uint8List.fromList(utf8.encode(jsonEncode(manifest)))
              : entry.readBytes()!;
      forged.add(ArchiveFile.bytes(entry.name, bytes));
    }

    expect(
      () => DisasterRecoveryBundle.decode(
        Uint8List.fromList(ZipEncoder().encodeBytes(forged)),
      ),
      throwsFormatException,
    );
    expect(DisasterRecoveryBundle.decode(original).assets, hasLength(1));
  });
}
