import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'attachments.dart';
import 'backup.dart';
import 'visual_documents.dart';

class MediaBundlePreview {
  const MediaBundlePreview({
    required this.snapshot,
    required this.assets,
  });

  final BackupSnapshot snapshot;
  final Map<String, Uint8List> assets;

  int get assetBytes =>
      assets.values.fold<int>(0, (sum, bytes) => sum + bytes.length);
}

abstract final class MediaBundle {
  static const maxArchiveBytes = 80 * 1024 * 1024;
  static const maxAssetBatchBytes = 64 * 1024 * 1024;
  static const format = 'notes-ecosystem-media';
  static const version = 1;

  static Future<Uint8List> encode(
    BackupSnapshot snapshot,
    AttachmentStore store,
  ) async {
    BackupCodec.validate(snapshot);
    final keys = _keys(snapshot).toList()..sort();
    if (keys.length > Attachments.maxFiles) {
      throw const FormatException('Troppi allegati nel backup.');
    }

    final backup = BackupCodec.encode(snapshot);
    if (utf8.encode(backup).length > BackupCodec.maxBytes) {
      throw const FormatException('Il backup delle note supera 5 MiB.');
    }

    final archive = Archive();
    archive.add(
      ArchiveFile.string(
        'bundle.json',
        jsonEncode({
          'format': format,
          'version': version,
          'assets': keys,
        }),
      ),
    );
    archive.add(ArchiveFile.string('backup.json', backup));

    var assetBytes = 0;
    for (final key in keys) {
      final bytes = await store.read(key);
      assetBytes += bytes.length;
      if (assetBytes > maxAssetBatchBytes) {
        throw const FormatException(
          'Gli allegati del backup superano 64 MiB.',
        );
      }
      archive.add(ArchiveFile.bytes('assets/$key', bytes));
    }

    var textIndex = 0;
    var sketchIndex = 0;
    var boardIndex = 0;
    for (final note in snapshot.notes.where((note) => !note.isDeleted)) {
      if (note.sketchJson == null) {
        textIndex++;
        archive.add(
          ArchiveFile.string(
            'note/$textIndex.md',
            '# ${note.title}\n\n${_portableBody(note.body)}',
          ),
        );
      } else {
        final info = VisualInfo.decode(note.sketchJson!);
        if (info.kind == VisualInfoKind.sketch) {
          sketchIndex++;
          archive.add(
            ArchiveFile.string(
              'disegni/$sketchIndex.sketch.json',
              note.body,
            ),
          );
        } else {
          boardIndex++;
          archive.add(
            ArchiveFile.string(
              'lavagne/$boardIndex.whiteboard.json',
              note.body,
            ),
          );
        }
      }
    }

    archive.add(
      ArchiveFile.string(
        'LEGGIMI.txt',
        'Backup completo Notes 0.25.1+. '
            'backup.json contiene note e metadati; assets contiene gli originali '
            'verificati SHA-256. Ricerche salvate, revisioni locali e timer Focus '
            'attivo non sono inclusi. Archivio non cifrato.',
      ),
    );

    final bytes = ZipEncoder().encodeBytes(archive);
    if (bytes.length > maxArchiveBytes) {
      throw const FormatException('Il backup ZIP supera 80 MiB.');
    }
    return bytes;
  }

  static MediaBundlePreview decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxArchiveBytes) {
      throw const FormatException('Archivio ZIP vuoto o oltre 80 MiB.');
    }

    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.length > 11005) {
      throw const FormatException('Troppe voci nel backup.');
    }

    final seen = <String>{};
    String? backupText;
    Set<String>? manifest;
    final assets = <String, Uint8List>{};
    var expandedBytes = 0;
    var assetBytes = 0;

    for (final entry in archive) {
      if (!entry.isFile || !seen.add(entry.name)) {
        throw const FormatException('Voce ZIP duplicata o non valida.');
      }
      final name = entry.name;
      final isAsset = name.startsWith('assets/');
      final assetKey = isAsset ? name.substring('assets/'.length) : '';
      final allowed = isAsset && Attachments.validKey(assetKey) ||
          name == 'bundle.json' ||
          name == 'backup.json' ||
          name == 'LEGGIMI.txt' ||
          RegExp(r'^note/[0-9]+\.md$').hasMatch(name) ||
          RegExp(r'^disegni/[0-9]+\.sketch\.json$').hasMatch(name) ||
          RegExp(r'^lavagne/[0-9]+\.whiteboard\.json$').hasMatch(name);
      if (!allowed) {
        throw const FormatException('Percorso ZIP non consentito.');
      }

      final data = entry.readBytes();
      if (data == null) {
        throw const FormatException('Voce ZIP non leggibile.');
      }
      expandedBytes += data.length;
      if (expandedBytes > maxArchiveBytes) {
        throw const FormatException('Archivio espanso oltre 80 MiB.');
      }

      if (isAsset) {
        if (assets.length >= Attachments.maxFiles ||
            data.isEmpty ||
            data.length > Attachments.fileLimit) {
          throw const FormatException('Allegato ZIP non valido.');
        }
        final typed = Uint8List.fromList(data);
        Attachments.verify(assetKey, typed);
        assetBytes += typed.length;
        if (assetBytes > maxAssetBatchBytes) {
          throw const FormatException(
            'Gli allegati del backup superano 64 MiB.',
          );
        }
        assets[assetKey] = typed;
      } else if (name == 'backup.json') {
        if (data.length > BackupCodec.maxBytes) {
          throw const FormatException('backup.json supera 5 MiB.');
        }
        backupText = utf8.decode(data, allowMalformed: false);
      } else if (name == 'bundle.json') {
        if (data.length > 100000) {
          throw const FormatException('Manifest backup troppo grande.');
        }
        final root = jsonDecode(utf8.decode(data, allowMalformed: false));
        if (root is! Map ||
            root['format'] != format ||
            root['version'] != version ||
            root['assets'] is! List) {
          throw const FormatException('Manifest backup non valido.');
        }
        final list = (root['assets'] as List)
            .map((value) => value.toString())
            .toList(growable: false);
        if (list.length > Attachments.maxFiles ||
            list.toSet().length != list.length ||
            list.any((key) => !Attachments.validKey(key))) {
          throw const FormatException('Elenco allegati non valido.');
        }
        manifest = list.toSet();
      }
    }

    if (backupText == null || manifest == null) {
      throw const FormatException('backup.json o bundle.json mancante.');
    }
    final snapshot = BackupCodec.decode(backupText);
    final referenced = _keys(snapshot);
    if (manifest.length != assets.length ||
        !manifest.containsAll(assets.keys) ||
        !assets.keys.toSet().containsAll(manifest) ||
        !referenced.containsAll(manifest) ||
        !manifest.containsAll(referenced)) {
      throw const FormatException(
        'Allegati mancanti o non coerenti con le note.',
      );
    }

    return MediaBundlePreview(snapshot: snapshot, assets: assets);
  }

  static Future<void> installAssets(
    MediaBundlePreview preview,
    AttachmentStore store,
  ) async {
    for (final entry in preview.assets.entries) {
      await store.put(entry.key, entry.value);
    }
  }

  static Set<String> _keys(BackupSnapshot snapshot) {
    final keys = <String>{};
    for (final note in snapshot.notes) {
      if (note.sketchJson == null) {
        keys.addAll(Attachments.refs(note.body).map((ref) => ref.key));
      }
    }
    for (final draft in snapshot.drafts) {
      keys.addAll(Attachments.refs(draft.body).map((ref) => ref.key));
    }
    return keys;
  }

  static String _portableBody(String body) => body.replaceAllMapped(
        RegExp(r'notes-asset://([a-f0-9]{64}\.[a-z0-9]{2,4})'),
        (match) => 'assets/${match.group(1)}',
      );
}
