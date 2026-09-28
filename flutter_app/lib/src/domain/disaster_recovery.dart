import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'attachments.dart';
import 'backup.dart';
import 'blocks.dart';
import 'shared_spaces.dart';

class DisasterRecoveryPreview {
  const DisasterRecoveryPreview({
    required this.snapshot,
    required this.revisions,
    required this.blocks,
    required this.properties,
    required this.knowledge,
    required this.derivatives,
    required this.projects,
    required this.sharedSpaces,
    required this.assets,
    required this.createdAt,
  });

  final BackupSnapshot snapshot;
  final List<Map<String, Object?>> revisions;
  final List<ContentBlock> blocks;
  final Map<String, Object?> properties;
  final Map<String, Object?> knowledge;
  final Map<String, Object?> derivatives;
  final Map<String, Object?> projects;
  final SharedSpacesSnapshot sharedSpaces;
  final Map<String, Uint8List> assets;
  final int createdAt;
}

abstract final class DisasterRecoveryBundle {
  static const format = 'notes-disaster-recovery';
  static const version = 1;
  static const maxArchiveBytes = 96 * 1024 * 1024;
  static const maxExpandedBytes = 128 * 1024 * 1024;
  static const maxJsonBytes = 12 * 1024 * 1024;
  static const maxEntries = 12050;

  static Future<Uint8List> encode({
    required BackupSnapshot snapshot,
    required List<Map<String, Object?>> revisions,
    required List<ContentBlock> blocks,
    required Map<String, Object?> properties,
    required Map<String, Object?> knowledge,
    required Map<String, Object?> derivatives,
    required Map<String, Object?> projects,
    required SharedSpacesSnapshot sharedSpaces,
    required AttachmentStore store,
    int? createdAt,
  }) async {
    BackupCodec.validate(snapshot);
    _validateRevisions(revisions, snapshot);
    _validateBlocks(blocks, snapshot);
    SharedSpacesCodec.encode(sharedSpaces);

    final payloads = <String, Uint8List>{
      'backup.json': _jsonBytes(jsonDecode(BackupCodec.encode(snapshot))),
      'revisions.json': _jsonBytes({'version': 1, 'items': revisions}),
      'blocks.json': _jsonBytes({
        'version': 1,
        'items': blocks.map((block) => block.toMap()).toList(growable: false),
      }),
      'properties.json': _jsonBytes(properties),
      'knowledge.json': _jsonBytes(knowledge),
      'derivatives.json': _jsonBytes(derivatives),
      'projects.json': _jsonBytes(projects),
      'shared-spaces.json': Uint8List.fromList(
        utf8.encode(SharedSpacesCodec.encode(sharedSpaces)),
      ),
    };

    final assetKeys = <String>{};
    for (final note in snapshot.notes) {
      if (!note.isVisual) {
        assetKeys.addAll(Attachments.refs(note.body).map((ref) => ref.key));
      }
    }
    for (final draft in snapshot.drafts) {
      assetKeys.addAll(Attachments.refs(draft.body).map((ref) => ref.key));
    }

    for (final key in assetKeys) {
      final bytes = await store.read(key);
      Attachments.verify(key, bytes);
      payloads['assets/$key'] = bytes;
    }

    var expanded = 0;
    final files = <String, Object?>{};
    for (final entry in payloads.entries) {
      expanded += entry.value.length;
      if (expanded > maxExpandedBytes) {
        throw const FormatException(
          'Il backup di ripristino supera il limite espanso.',
        );
      }
      files[entry.key] = {
        'bytes': entry.value.length,
        'sha256': sha256.convert(entry.value).toString(),
      };
    }

    final created = createdAt ?? DateTime.now().millisecondsSinceEpoch;
    final manifest = _jsonBytes({
      'format': format,
      'version': version,
      'createdAt': created,
      'files': files,
    });

    final archive = Archive()
      ..add(ArchiveFile.bytes('manifest.json', manifest));
    for (final entry in payloads.entries) {
      archive.add(ArchiveFile.bytes(entry.key, entry.value));
    }

    final zip = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    if (zip.isEmpty || zip.length > maxArchiveBytes) {
      throw const FormatException(
        'Il backup di ripristino supera il limite consentito.',
      );
    }
    return zip;
  }

  static DisasterRecoveryPreview decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxArchiveBytes) {
      throw const FormatException(
        'Backup di ripristino vuoto o troppo grande.',
      );
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.isEmpty || archive.length > maxEntries) {
      throw const FormatException('Backup di ripristino non valido.');
    }

    final raw = <String, Uint8List>{};
    var expanded = 0;
    for (final entry in archive) {
      if (!entry.isFile || raw.containsKey(entry.name)) {
        throw const FormatException('Voce duplicata o non valida nel backup.');
      }
      final allowed = entry.name == 'manifest.json' ||
          entry.name == 'backup.json' ||
          entry.name == 'revisions.json' ||
          entry.name == 'blocks.json' ||
          entry.name == 'properties.json' ||
          entry.name == 'knowledge.json' ||
          entry.name == 'derivatives.json' ||
          entry.name == 'projects.json' ||
          entry.name == 'shared-spaces.json' ||
          (entry.name.startsWith('assets/') &&
              Attachments.validKey(entry.name.substring('assets/'.length)));
      if (!allowed) {
        throw const FormatException('Percorso non consentito nel backup.');
      }
      final data = entry.readBytes();
      if (data == null) {
        throw const FormatException('Voce non leggibile nel backup.');
      }
      expanded += data.length;
      if (expanded > maxExpandedBytes) {
        throw const FormatException(
          'Il backup espanso supera il limite consentito.',
        );
      }
      raw[entry.name] = Uint8List.fromList(data);
    }

    final manifestBytes = raw.remove('manifest.json');
    if (manifestBytes == null || manifestBytes.length > 256 * 1024) {
      throw const FormatException('Manifest di ripristino mancante.');
    }
    final manifest = _map(
      jsonDecode(utf8.decode(manifestBytes, allowMalformed: false)),
      'manifest',
    );
    if (manifest['format'] != format || manifest['version'] != version) {
      throw const FormatException(
        'Versione backup di ripristino non supportata.',
      );
    }
    final createdAt = _integer(manifest['createdAt'], 'createdAt');
    final declared = _map(manifest['files'], 'files');

    if (declared.length != raw.length ||
        !declared.keys.toSet().containsAll(raw.keys) ||
        !raw.keys.toSet().containsAll(declared.keys)) {
      throw const FormatException(
        'Manifest e contenuto del backup non coincidono.',
      );
    }

    for (final entry in raw.entries) {
      final info = _map(declared[entry.key], entry.key);
      final expectedBytes = _integer(info['bytes'], 'bytes');
      final expectedHash = info['sha256']?.toString() ?? '';
      if (expectedBytes != entry.value.length ||
          expectedHash != sha256.convert(entry.value).toString()) {
        throw FormatException(
          'Integrità non valida per ${entry.key}.',
        );
      }
      if (!entry.key.startsWith('assets/') &&
          entry.value.length > maxJsonBytes) {
        throw FormatException('${entry.key} supera il limite consentito.');
      }
    }

    final backupBytes = raw['backup.json'];
    if (backupBytes == null) {
      throw const FormatException('backup.json mancante.');
    }
    final snapshot = BackupCodec.decode(
      utf8.decode(backupBytes, allowMalformed: false),
    );
    final revisionsRoot = _jsonMap(raw, 'revisions.json');
    final blocksRoot = _jsonMap(raw, 'blocks.json');
    if (revisionsRoot['version'] != 1 || revisionsRoot['items'] is! List) {
      throw const FormatException('Revisioni backup non valide.');
    }
    if (blocksRoot['version'] != 1 || blocksRoot['items'] is! List) {
      throw const FormatException('Blocchi backup non validi.');
    }

    final revisions = (revisionsRoot['items'] as List)
        .map((value) => _map(value, 'revision'))
        .toList(growable: false);
    final blocks = (blocksRoot['items'] as List)
        .map((value) => ContentBlock.fromMap(_map(value, 'block')))
        .toList(growable: false);
    _validateRevisions(revisions, snapshot);
    _validateBlocks(blocks, snapshot);

    final assets = <String, Uint8List>{};
    for (final entry in raw.entries) {
      if (!entry.key.startsWith('assets/')) continue;
      final key = entry.key.substring('assets/'.length);
      Attachments.verify(key, entry.value);
      assets[key] = entry.value;
    }
    final referenced = <String>{};
    for (final note in snapshot.notes) {
      if (!note.isVisual) {
        referenced.addAll(Attachments.refs(note.body).map((ref) => ref.key));
      }
    }
    for (final draft in snapshot.drafts) {
      referenced.addAll(Attachments.refs(draft.body).map((ref) => ref.key));
    }
    if (referenced.length != assets.length ||
        !referenced.containsAll(assets.keys) ||
        !assets.keys.toSet().containsAll(referenced)) {
      throw const FormatException(
        'Allegati non coerenti con lo stato da ripristinare.',
      );
    }

    final sharedRaw = raw['shared-spaces.json'];
    if (sharedRaw == null) {
      throw const FormatException('Shared Spaces mancanti nel backup.');
    }

    return DisasterRecoveryPreview(
      snapshot: snapshot,
      revisions: revisions,
      blocks: blocks,
      properties: _jsonMap(raw, 'properties.json'),
      knowledge: _jsonMap(raw, 'knowledge.json'),
      derivatives: _jsonMap(raw, 'derivatives.json'),
      projects: _jsonMap(raw, 'projects.json'),
      sharedSpaces: SharedSpacesCodec.decode(
        utf8.decode(sharedRaw, allowMalformed: false),
      ),
      assets: Map.unmodifiable(assets),
      createdAt: createdAt,
    );
  }

  static Map<String, Object?> _jsonMap(
    Map<String, Uint8List> raw,
    String name,
  ) {
    final bytes = raw[name];
    if (bytes == null) throw FormatException('$name mancante.');
    return _map(
      jsonDecode(utf8.decode(bytes, allowMalformed: false)),
      name,
    );
  }

  static Uint8List _jsonBytes(Object value) {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(value)));
    if (bytes.length > maxJsonBytes) {
      throw const FormatException('Payload backup troppo grande.');
    }
    return bytes;
  }

  static Map<String, Object?> _map(Object? value, String name) {
    if (value is! Map) throw FormatException('$name non valido.');
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static int _integer(Object? value, String name) {
    if (value is! num || value.toInt() != value || value.toInt() < 0) {
      throw FormatException('$name non valido.');
    }
    return value.toInt();
  }

  static void _validateRevisions(
    List<Map<String, Object?>> revisions,
    BackupSnapshot snapshot,
  ) {
    if (revisions.length > 500000) {
      throw const FormatException('Troppe revisioni nel backup.');
    }
    final noteIds = snapshot.notes.map((note) => note.id).toSet();
    final ids = <String>{};
    for (final row in revisions) {
      final revisionId = row['revisionId']?.toString() ?? '';
      final noteId = row['noteId']?.toString() ?? '';
      final title = row['title']?.toString() ?? '';
      final body = row['body']?.toString() ?? '';
      final tagsJson = row['tagsJson']?.toString() ?? '';
      final savedAt = row['savedAt'];
      if (revisionId.isEmpty ||
          !ids.add(revisionId) ||
          !noteIds.contains(noteId) ||
          title.length > 8000 ||
          body.length > 500000 ||
          tagsJson.length > 100000 ||
          savedAt is! num ||
          savedAt.toInt() < 0) {
        throw const FormatException('Revisioni backup non valide.');
      }
    }
  }

  static void _validateBlocks(
    List<ContentBlock> blocks,
    BackupSnapshot snapshot,
  ) {
    if (blocks.length > 1000000) {
      throw const FormatException('Troppi blocchi nel backup.');
    }
    final textNoteIds = snapshot.notes
        .where((note) => !note.isTask && !note.isVisual)
        .map((note) => note.id)
        .toSet();
    final ids = <String>{};
    for (final block in blocks) {
      ContentBlocks.validate(block);
      if (!ids.add(block.id) ||
          block.ownerType != 'note' ||
          !textNoteIds.contains(block.ownerId)) {
        throw const FormatException('Blocchi backup non validi.');
      }
    }
  }
}
