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
    this.properties = const {},
    this.knowledge = const {},
    this.derivatives = const {},
  });

  final BackupSnapshot snapshot;
  final Map<String, Uint8List> assets;
  final Map<String, Object?> properties;
  final Map<String, Object?> knowledge;
  final Map<String, Object?> derivatives;

  int get assetBytes =>
      assets.values.fold<int>(0, (sum, bytes) => sum + bytes.length);
}

abstract final class MediaBundle {
  static const maxArchiveBytes = 80 * 1024 * 1024;
  static const maxAssetBatchBytes = 64 * 1024 * 1024;
  static const format = 'notes-ecosystem-media';
  static const version = 2;
  static const maxSidecarBytes = 8 * 1024 * 1024;

  static Future<Uint8List> encode(
    BackupSnapshot snapshot,
    AttachmentStore store, {
    Map<String, Object?> properties = const {},
    Map<String, Object?> knowledge = const {},
    Map<String, Object?> derivatives = const {},
  }) async {
    final keys = referencedKeys(snapshot).toList()..sort();
    final assets = <String, Uint8List>{};
    for (final key in keys) {
      assets[key] = await store.read(key);
    }
    return encodeLoaded(
      snapshot,
      assets,
      properties: properties,
      knowledge: knowledge,
      derivatives: derivatives,
    );
  }

  static Uint8List encodeLoaded(
    BackupSnapshot snapshot,
    Map<String, Uint8List> assets, {
    Map<String, Object?> properties = const {},
    Map<String, Object?> knowledge = const {},
    Map<String, Object?> derivatives = const {},
  }) {
    BackupCodec.validate(snapshot);
    final keys = referencedKeys(snapshot).toList()..sort();
    if (keys.length > Attachments.maxFiles ||
        assets.length != keys.length ||
        !assets.keys.toSet().containsAll(keys) ||
        !keys.toSet().containsAll(assets.keys)) {
      throw const FormatException(
        'Allegati mancanti o non coerenti con le note.',
      );
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
          'sidecars': const [
            'properties.json',
            'knowledge.json',
            'derivatives.json',
          ],
        }),
      ),
    );
    archive.add(ArchiveFile.string('backup.json', backup));
    for (final entry in <String, Map<String, Object?>>{
      'properties.json': properties,
      'knowledge.json': knowledge,
      'derivatives.json': derivatives,
    }.entries) {
      final encoded = jsonEncode(entry.value);
      if (utf8.encode(encoded).length > maxSidecarBytes) {
        throw FormatException('${entry.key} supera 8 MiB.');
      }
      archive.add(ArchiveFile.string(entry.key, encoded));
    }

    var assetBytes = 0;
    for (final key in keys) {
      final bytes = assets[key]!;
      Attachments.verify(key, bytes);
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
        'Backup completo Notes 0.36+. '
            'backup.json contiene il workspace canonico; assets contiene gli originali '
            'verificati SHA-256; properties/knowledge/derivatives contengono i sidecar '
            'portabili. Ricerche salvate, revisioni locali e timer Focus attivo non '
            'sono inclusi. Archivio non cifrato.',
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
    int? bundleVersion;
    Set<String> declaredSidecars = const {};
    Map<String, Object?> properties = const {};
    Map<String, Object?> knowledge = const {};
    Map<String, Object?> derivatives = const {};
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
          name == 'properties.json' ||
          name == 'knowledge.json' ||
          name == 'derivatives.json' ||
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
      } else if (name == 'properties.json' ||
          name == 'knowledge.json' ||
          name == 'derivatives.json') {
        if (data.length > maxSidecarBytes) {
          throw FormatException('$name supera 8 MiB.');
        }
        final decoded = jsonDecode(utf8.decode(data, allowMalformed: false));
        if (decoded is! Map) {
          throw FormatException('$name non valido.');
        }
        final mapped =
            decoded.map((key, value) => MapEntry(key.toString(), value));
        if (name == 'properties.json') properties = mapped;
        if (name == 'knowledge.json') knowledge = mapped;
        if (name == 'derivatives.json') derivatives = mapped;
      } else if (name == 'bundle.json') {
        if (data.length > 100000) {
          throw const FormatException('Manifest backup troppo grande.');
        }
        final root = jsonDecode(utf8.decode(data, allowMalformed: false));
        if (root is! Map ||
            root['format'] != format ||
            root['version'] is! num ||
            (root['version'] as num).toInt() < 1 ||
            (root['version'] as num).toInt() > version ||
            root['assets'] is! List) {
          throw const FormatException('Manifest backup non valido.');
        }
        bundleVersion = (root['version'] as num).toInt();
        if (bundleVersion! >= 2) {
          if (root['sidecars'] is! List) {
            throw const FormatException('Sidecar backup mancanti.');
          }
          declaredSidecars = (root['sidecars'] as List)
              .map((value) => value.toString())
              .toSet();
          const required = {
            'properties.json',
            'knowledge.json',
            'derivatives.json',
          };
          if (!declaredSidecars.containsAll(required) ||
              declaredSidecars.length != required.length) {
            throw const FormatException('Elenco sidecar backup non valido.');
          }
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

    if (backupText == null || manifest == null || bundleVersion == null) {
      throw const FormatException('backup.json o bundle.json mancante.');
    }
    if (bundleVersion! >= 2 &&
        (properties.isEmpty && knowledge.isEmpty && derivatives.isEmpty)) {
      // Empty maps are valid individually, but all three files must have been
      // present as declared. Presence is guaranteed by the ZIP seen-set below.
      const required = {
        'properties.json',
        'knowledge.json',
        'derivatives.json',
      };
      if (!seen.containsAll(required)) {
        throw const FormatException('Sidecar backup dichiarati ma mancanti.');
      }
    }
    final snapshot = BackupCodec.decode(backupText);
    final referenced = referencedKeys(snapshot);
    if (manifest.length != assets.length ||
        !manifest.containsAll(assets.keys) ||
        !assets.keys.toSet().containsAll(manifest) ||
        !referenced.containsAll(manifest) ||
        !manifest.containsAll(referenced)) {
      throw const FormatException(
        'Allegati mancanti o non coerenti con le note.',
      );
    }

    return MediaBundlePreview(
      snapshot: snapshot,
      assets: assets,
      properties: properties,
      knowledge: knowledge,
      derivatives: derivatives,
    );
  }

  static Future<void> installAssets(
    MediaBundlePreview preview,
    AttachmentStore store,
  ) async {
    for (final entry in preview.assets.entries) {
      await store.put(entry.key, entry.value);
    }
  }

  static Set<String> referencedKeys(BackupSnapshot snapshot) {
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
