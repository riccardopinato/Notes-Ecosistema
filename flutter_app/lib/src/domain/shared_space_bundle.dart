import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'attachments.dart';
import 'shared_spaces.dart';
import 'sync.dart';

class SharedSpaceBundlePreview {
  const SharedSpaceBundlePreview({
    required this.space,
    required this.actor,
    required this.exportedAt,
    required this.documents,
    required this.assets,
  });

  final SharedSpace space;
  final SharedIdentity actor;
  final int exportedAt;
  final Map<String, SyncDocument> documents;
  final Map<String, Uint8List> assets;

  int get assetBytes =>
      assets.values.fold<int>(0, (sum, bytes) => sum + bytes.length);
}

abstract final class SharedSpaceBundle {
  static const format = 'notes-ecosystem-shared-space-bundle';
  static const version = 1;
  static const maxArchiveBytes = 80 * 1024 * 1024;
  static const maxAssetsBytes = 64 * 1024 * 1024;

  static Future<Uint8List> encode({
    required SharedSpace space,
    required SharedIdentity actor,
    required Map<String, SyncDocument> documents,
    required AttachmentStore store,
    int? exportedAt,
  }) async {
    SharedSpaces.validateIdentity(actor);
    SharedSpaces.validateSpace(space);
    if (!space.canRead(actor.id)) {
      throw const FormatException(
        'Non hai accesso a questo spazio.',
      );
    }
    final ids = space.contentIds;
    if (documents.length != ids.length ||
        !documents.keys.toSet().containsAll(ids) ||
        !ids.containsAll(documents.keys)) {
      throw const FormatException(
        'Lo snapshot deve contenere tutti e soli gli elementi condivisi.',
      );
    }
    if (documents.length > SharedSpaces.maxContentPerSpace) {
      throw const FormatException('Troppi elementi nello spazio.');
    }

    final archive = Archive();
    final at = exportedAt ?? DateTime.now().millisecondsSinceEpoch;
    archive.add(
      ArchiveFile.string(
        'space.json',
        jsonEncode({
          'format': format,
          'version': version,
          'exportedAt': at,
          'actor': actor.toJson(),
          'space': space.toJson(),
        }),
      ),
    );

    final assetKeys = <String>{};
    for (final entry in documents.entries) {
      if (entry.key != entry.value.id) {
        throw const FormatException('ID documento condiviso non coerente.');
      }
      final encoded = SyncCodec.encode(entry.value);
      archive.add(
        ArchiveFile.string(
          'documents/${SyncCodec.filename(entry.key)}',
          encoded,
        ),
      );
      if (entry.value.sketchJson == null) {
        assetKeys.addAll(
          Attachments.refs(entry.value.body).map((ref) => ref.key),
        );
      }
    }

    if (assetKeys.length > Attachments.maxFiles) {
      throw const FormatException('Troppi allegati nello spazio.');
    }
    var assetsBytes = 0;
    final sortedKeys = assetKeys.toList()..sort();
    for (final key in sortedKeys) {
      final bytes = await store.read(key);
      Attachments.verify(key, bytes);
      assetsBytes += bytes.length;
      if (assetsBytes > maxAssetsBytes) {
        throw const FormatException(
          'Gli allegati dello spazio superano 64 MiB.',
        );
      }
      archive.add(ArchiveFile.bytes('assets/$key', bytes));
    }

    archive.add(
      ArchiveFile.string(
        'LEGGIMI.txt',
        'Shared Space Notes 0.26. Il pacchetto contiene esclusivamente '
            'gli elementi aggiunti esplicitamente allo spazio, più gli '
            'allegati necessari. I contenuti personali esterni allo spazio '
            'non sono inclusi.',
      ),
    );

    final bytes = ZipEncoder().encodeBytes(archive);
    if (bytes.length > maxArchiveBytes) {
      throw const FormatException(
        'Pacchetto Shared Space oltre 80 MiB.',
      );
    }
    return bytes;
  }

  static SharedSpaceBundlePreview decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxArchiveBytes) {
      throw const FormatException(
        'Pacchetto Shared Space vuoto o troppo grande.',
      );
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.length > 1105) {
      throw const FormatException('Troppe voci nel pacchetto.');
    }

    final seen = <String>{};
    Map<String, Object?>? manifest;
    final documents = <String, SyncDocument>{};
    final assets = <String, Uint8List>{};
    var expanded = 0;
    var assetsBytes = 0;

    for (final entry in archive) {
      if (!entry.isFile || !seen.add(entry.name)) {
        throw const FormatException(
          'Voce duplicata o non valida nel pacchetto.',
        );
      }
      final name = entry.name;
      final isDocument = RegExp(r'^documents/[a-f0-9]{64}\.md$')
          .hasMatch(name);
      final isAsset = name.startsWith('assets/') &&
          Attachments.validKey(name.substring('assets/'.length));
      if (name != 'space.json' &&
          name != 'LEGGIMI.txt' &&
          !isDocument &&
          !isAsset) {
        throw const FormatException(
          'Percorso non consentito nel pacchetto.',
        );
      }

      final raw = entry.readBytes();
      if (raw == null) {
        throw const FormatException('Voce pacchetto non leggibile.');
      }
      expanded += raw.length;
      if (expanded > maxArchiveBytes) {
        throw const FormatException(
          'Pacchetto espanso oltre 80 MiB.',
        );
      }

      if (name == 'space.json') {
        if (raw.length > SharedSpacesCodec.maxBytes) {
          throw const FormatException(
            'Manifest Shared Space troppo grande.',
          );
        }
        final decoded = jsonDecode(
          utf8.decode(raw, allowMalformed: false),
        );
        manifest = _map(decoded);
      } else if (isDocument) {
        if (raw.length > SyncCodec.maxBytes) {
          throw const FormatException(
            'Documento condiviso troppo grande.',
          );
        }
        final document = SyncCodec.decode(
          utf8.decode(raw, allowMalformed: false),
        );
        final expected = 'documents/${SyncCodec.filename(document.id)}';
        if (name != expected || documents.containsKey(document.id)) {
          throw const FormatException(
            'Documento condiviso duplicato o rinominato.',
          );
        }
        documents[document.id] = document;
      } else if (isAsset) {
        final key = name.substring('assets/'.length);
        if (assets.length >= Attachments.maxFiles ||
            raw.isEmpty ||
            raw.length > Attachments.fileLimit) {
          throw const FormatException(
            'Allegato Shared Space non valido.',
          );
        }
        final typed = Uint8List.fromList(raw);
        Attachments.verify(key, typed);
        assetsBytes += typed.length;
        if (assetsBytes > maxAssetsBytes) {
          throw const FormatException(
            'Gli allegati dello spazio superano 64 MiB.',
          );
        }
        assets[key] = typed;
      }
    }

    if (manifest == null ||
        manifest['format'] != format ||
        manifest['version'] != version) {
      throw const FormatException(
        'Manifest Shared Space mancante o non supportato.',
      );
    }
    final actor = SharedIdentity.fromJson(
      _map(manifest['actor']),
    );
    final space = SharedSpace.fromJson(
      _map(manifest['space']),
    );
    final exportedAt = _integer(manifest['exportedAt']);
    final ids = space.contentIds;
    if (documents.length != ids.length ||
        !documents.keys.toSet().containsAll(ids) ||
        !ids.containsAll(documents.keys)) {
      throw const FormatException(
        'Elementi Shared Space mancanti o incoerenti.',
      );
    }

    final referencedAssets = <String>{};
    for (final document in documents.values) {
      if (document.sketchJson == null) {
        referencedAssets.addAll(
          Attachments.refs(document.body).map((ref) => ref.key),
        );
      }
    }
    if (assets.length != referencedAssets.length ||
        !assets.keys.toSet().containsAll(referencedAssets) ||
        !referencedAssets.containsAll(assets.keys)) {
      throw const FormatException(
        'Allegati Shared Space mancanti o non coerenti.',
      );
    }

    return SharedSpaceBundlePreview(
      space: space,
      actor: actor,
      exportedAt: exportedAt,
      documents: documents,
      assets: assets,
    );
  }

  static Future<void> installAssets(
    SharedSpaceBundlePreview preview,
    AttachmentStore store,
  ) async {
    for (final entry in preview.assets.entries) {
      await store.put(entry.key, entry.value);
    }
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) {
      throw const FormatException('Oggetto Shared Space non valido.');
    }
    return value.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  static int _integer(Object? value) {
    if (value is! num ||
        value.toInt() != value ||
        value.toInt() < 0) {
      throw const FormatException('Data Shared Space non valida.');
    }
    return value.toInt();
  }
}
