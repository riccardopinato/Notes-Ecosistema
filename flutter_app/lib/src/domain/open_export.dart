import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'attachments.dart';
import 'backup.dart';
import 'research.dart';

abstract final class OpenExportBundle {
  static const format = 'notes-open-export';
  static const version = 1;
  static const maxBytes = 96 * 1024 * 1024;

  static Future<Uint8List> encode({
    required BackupSnapshot snapshot,
    required Map<String, Object?> properties,
    required Map<String, Object?> knowledge,
    required Map<String, Object?> projects,
    required Map<String, Object?> study,
    required Map<String, Object?> documents,
    required AttachmentStore store,
  }) async {
    final assets = <String, Uint8List>{};
    for (final key in _referencedAssets(snapshot)) {
      final bytes = await store.read(key);
      Attachments.verify(key, bytes);
      assets[key] = bytes;
    }
    return encodeLoaded(
      snapshot: snapshot,
      properties: properties,
      knowledge: knowledge,
      projects: projects,
      study: study,
      documents: documents,
      assets: assets,
    );
  }

  static Uint8List encodeLoaded({
    required BackupSnapshot snapshot,
    required Map<String, Object?> properties,
    required Map<String, Object?> knowledge,
    required Map<String, Object?> projects,
    required Map<String, Object?> study,
    required Map<String, Object?> documents,
    required Map<String, Uint8List> assets,
  }) {
    BackupCodec.validate(snapshot);

    final synced = <String, SyncedBlock>{};
    final rawBlocks = knowledge['syncedBlocks'];
    if (rawBlocks is List) {
      for (final raw in rawBlocks) {
        if (raw is! Map) continue;
        final block = SyncedBlock.fromMap(
          raw.map((key, value) => MapEntry(key.toString(), value)),
        );
        synced[block.id] = block;
      }
    }

    final assetKeys = <String>{};
    for (final note in snapshot.notes) {
      if (!note.isVisual) {
        assetKeys.addAll(Attachments.refs(note.body).map((ref) => ref.key));
      }
    }

    final files = <String, Uint8List>{};
    final used = <String>{};
    final index = <Map<String, Object?>>[];

    for (final note in snapshot.notes) {
      final kind = note.isTask
          ? 'task'
          : note.isVisual
              ? 'visual'
              : 'note';
      final lifecycle = note.isDeleted
          ? 'trash'
          : note.archived
              ? 'archived'
              : 'active';
      String? humanFile;

      if (!note.isDeleted && !note.isVisual) {
        final base = _safeName(
          note.title.trim().isEmpty ? note.id : note.title.trim(),
        );
        var name = '$base.md';
        var suffix = 2;
        while (!used.add(name.toLowerCase())) {
          name = '$base-$suffix.md';
          suffix++;
        }
        humanFile = 'notes/$name';
        final body = SyncedBlockCodec.resolve(note.body, synced);
        files[humanFile] = Uint8List.fromList(
          utf8.encode(
            [
              '---',
              'notes_id: ${note.id}',
              'notes_kind: $kind',
              'notes_lifecycle: $lifecycle',
              if (note.tags.isNotEmpty) 'tags: ${jsonEncode(note.tags)}',
              '---',
              '',
              '# ${note.title.trim().isEmpty ? 'Senza titolo' : note.title.trim()}',
              '',
              _portableAssets(body),
            ].join('\n'),
          ),
        );
      } else if (!note.isDeleted && note.isVisual) {
        humanFile = 'visual/${note.id}.json';
        files[humanFile] = Uint8List.fromList(utf8.encode(note.body));
      }

      index.add({
        'id': note.id,
        'title': note.title,
        'kind': kind,
        'lifecycle': lifecycle,
        'humanFile': humanFile,
        'collectionId': note.collectionId,
        'tags': note.tags,
        'favorite': note.favorite,
        'pinned': note.pinned,
        'createdAt': note.createdAt,
        'updatedAt': note.updatedAt,
        'deletedAt': note.deletedAt,
        'task': note.taskJson == null ? null : jsonDecode(note.taskJson!),
        'visual': note.sketchJson == null ? null : jsonDecode(note.sketchJson!),
        'body': note.isVisual ? null : _portableAssets(note.body),
      });
    }

    files['workspace.json'] = _json({
      'format': format,
      'version': version,
      'collections': snapshot.collections
          .map((item) => {'id': item.id, 'name': item.name})
          .toList(growable: false),
      'objects': index,
    });
    files['properties.json'] = _json(properties);
    files['knowledge.json'] = _json(knowledge);
    files['projects.json'] = _json(projects);
    files['study.json'] = _json(study);
    files['documents.json'] = _json(documents);

    if (assets.length != assetKeys.length ||
        !assets.keys.toSet().containsAll(assetKeys) ||
        !assetKeys.containsAll(assets.keys)) {
      throw const FormatException('Media Open Export non coerenti.');
    }
    for (final key in assetKeys) {
      final bytes = assets[key]!;
      Attachments.verify(key, bytes);
      files['assets/$key'] = bytes;
    }

    final manifestEntries = <String, Object?>{};
    var expanded = 0;
    for (final entry in files.entries) {
      expanded += entry.value.length;
      if (expanded > maxBytes) {
        throw const FormatException('Open Export oltre il limite consentito.');
      }
      manifestEntries[entry.key] = {
        'bytes': entry.value.length,
        'sha256': sha256.convert(entry.value).toString(),
      };
    }

    files['manifest.json'] = _json({
      'format': format,
      'version': version,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'files': manifestEntries,
      'scope': const [
        'objects',
        'collections',
        'properties',
        'knowledge',
        'projects',
        'study',
        'document-annotations',
        'media',
      ],
      'excluded': const [
        'drafts',
        'revision-history',
        'shared-space-identity',
        'sync-state',
        'transient-focus-state',
      ],
    });
    files['README.txt'] = Uint8List.fromList(
      utf8.encode(
        'Open Export Notes Ecosistema. '
        'Questo archivio privilegia portabilità e leggibilità fuori da Notes: '
        'Markdown, JSON strutturato e media originali. '
        'Non è un backup Disaster Recovery e non promette un restore identico.',
      ),
    );

    final archive = Archive();
    for (final entry in files.entries) {
      archive.add(ArchiveFile.bytes(entry.key, entry.value));
    }
    final encoded = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    if (encoded.length > maxBytes) {
      throw const FormatException('Open Export ZIP oltre 96 MiB.');
    }
    return encoded;
  }

  static Set<String> _referencedAssets(BackupSnapshot snapshot) {
    final keys = <String>{};
    for (final note in snapshot.notes) {
      if (!note.isVisual) {
        keys.addAll(Attachments.refs(note.body).map((ref) => ref.key));
      }
    }
    return keys;
  }

  static Uint8List _json(Object value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));

  static String _portableAssets(String body) => body.replaceAllMapped(
        RegExp(r'notes-asset://([a-f0-9]{64}\.[a-z0-9]{2,4})'),
        (match) => 'assets/${match.group(1)}',
      );

  static String _safeName(String input) {
    final normalized = input
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    final safe = normalized.isEmpty ? 'nota' : normalized;
    return safe.length > 90 ? safe.substring(0, 90).trim() : safe;
  }
}
