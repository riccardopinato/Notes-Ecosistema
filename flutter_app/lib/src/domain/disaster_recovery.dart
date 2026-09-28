import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'attachments.dart';

class DisasterRecoveryPreview {
  const DisasterRecoveryPreview({
    required this.exportedAt,
    required this.components,
    required this.assets,
  });

  final int exportedAt;
  final Map<String, Map<String, Object?>> components;
  final Map<String, Uint8List> assets;
}

abstract final class DisasterRecoveryArchive {
  static const format = 'notes-ecosystem-disaster-recovery';
  static const version = 1;
  static const maxArchiveBytes = 96 * 1024 * 1024;
  static const maxExpandedBytes = 128 * 1024 * 1024;
  static const maxComponentBytes = 16 * 1024 * 1024;
  static const maxAssetBytes = 64 * 1024 * 1024;

  static final _componentName = RegExp(r'^[a-z][a-z0-9_-]{0,63}$');

  static Uint8List encode({
    required Map<String, Map<String, Object?>> components,
    required Map<String, Uint8List> assets,
    int? exportedAt,
  }) {
    if (components.isEmpty) {
      throw const FormatException('Backup di emergenza senza stato.');
    }

    final archive = Archive();
    final entries = <String, Map<String, Object?>>{};
    var expanded = 0;

    final componentNames = components.keys.toList()..sort();
    for (final name in componentNames) {
      if (!_componentName.hasMatch(name)) {
        throw FormatException('Componente backup non valido: $name');
      }
      final bytes = Uint8List.fromList(
        utf8.encode(jsonEncode(components[name])),
      );
      if (bytes.length > maxComponentBytes) {
        throw FormatException('Componente $name oltre 16 MiB.');
      }
      final path = 'state/$name.json';
      expanded += bytes.length;
      entries[path] = _entry(bytes);
      archive.add(ArchiveFile.bytes(path, bytes));
    }

    var assetBytes = 0;
    final assetKeys = assets.keys.toList()..sort();
    for (final key in assetKeys) {
      final bytes = assets[key]!;
      Attachments.verify(key, bytes);
      assetBytes += bytes.length;
      if (assetBytes > maxAssetBytes) {
        throw const FormatException(
          'Gli allegati del backup superano 64 MiB.',
        );
      }
      final path = 'assets/$key';
      expanded += bytes.length;
      entries[path] = _entry(bytes);
      archive.add(ArchiveFile.bytes(path, bytes));
    }

    if (expanded > maxExpandedBytes) {
      throw const FormatException('Backup di emergenza troppo grande.');
    }

    final manifest = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': format,
          'version': version,
          'exportedAt': exportedAt ?? DateTime.now().millisecondsSinceEpoch,
          'entries': entries,
        }),
      ),
    );
    archive.add(ArchiveFile.bytes('manifest.json', manifest));

    final encoded = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    if (encoded.length > maxArchiveBytes) {
      throw const FormatException('Backup di emergenza oltre 96 MiB.');
    }
    return encoded;
  }

  static DisasterRecoveryPreview decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxArchiveBytes) {
      throw const FormatException(
        'Backup di emergenza vuoto o oltre 96 MiB.',
      );
    }

    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.length > 12000) {
      throw const FormatException('Troppe voci nel backup di emergenza.');
    }

    final files = <String, Uint8List>{};
    var expanded = 0;
    for (final entry in archive) {
      if (!entry.isFile) {
        throw const FormatException('Il backup contiene una voce non valida.');
      }
      final name = entry.name;
      if (!_safePath(name) || files.containsKey(name)) {
        throw const FormatException(
          'Percorso duplicato o non sicuro nel backup.',
        );
      }
      final raw = entry.readBytes();
      if (raw == null) {
        throw const FormatException('Voce backup non leggibile.');
      }
      final data = Uint8List.fromList(raw);
      expanded += data.length;
      if (expanded > maxExpandedBytes) {
        throw const FormatException(
          'Contenuto espanso del backup oltre il limite.',
        );
      }
      files[name] = data;
    }

    final manifestBytes = files.remove('manifest.json');
    if (manifestBytes == null || manifestBytes.length > 1024 * 1024) {
      throw const FormatException('Manifest backup mancante o non valido.');
    }
    final decoded = jsonDecode(
      utf8.decode(manifestBytes, allowMalformed: false),
    );
    if (decoded is! Map ||
        decoded['format'] != format ||
        decoded['version'] != version ||
        decoded['entries'] is! Map) {
      throw const FormatException(
        'Formato backup di emergenza non supportato.',
      );
    }

    final exportedAt = (decoded['exportedAt'] as num?)?.toInt();
    if (exportedAt == null || exportedAt < 0) {
      throw const FormatException('Data backup non valida.');
    }

    final declared = (decoded['entries'] as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
    if (declared.length != files.length ||
        !declared.keys.toSet().containsAll(files.keys) ||
        !files.keys.toSet().containsAll(declared.keys)) {
      throw const FormatException(
        'Manifest e contenuto del backup non coincidono.',
      );
    }

    for (final entry in declared.entries) {
      final meta = entry.value;
      final data = files[entry.key]!;
      if (meta is! Map ||
          (meta['size'] as num?)?.toInt() != data.length ||
          meta['sha256']?.toString() != sha256.convert(data).toString()) {
        throw FormatException('Integrità non valida per ${entry.key}.');
      }
    }

    final components = <String, Map<String, Object?>>{};
    final assets = <String, Uint8List>{};
    for (final entry in files.entries) {
      if (entry.key.startsWith('state/') && entry.key.endsWith('.json')) {
        final name = entry.key.substring(6, entry.key.length - 5);
        if (!_componentName.hasMatch(name) ||
            entry.value.length > maxComponentBytes) {
          throw const FormatException('Componente backup non valido.');
        }
        final raw = jsonDecode(
          utf8.decode(entry.value, allowMalformed: false),
        );
        if (raw is! Map) {
          throw FormatException('Componente $name non valido.');
        }
        components[name] = raw.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      } else if (entry.key.startsWith('assets/')) {
        final key = entry.key.substring(7);
        if (!Attachments.validKey(key)) {
          throw const FormatException('Allegato backup non valido.');
        }
        Attachments.verify(key, entry.value);
        assets[key] = entry.value;
      } else {
        throw FormatException(
          'Voce backup non riconosciuta: ${entry.key}',
        );
      }
    }

    if (!components.containsKey('workspace')) {
      throw const FormatException(
        'Il backup non contiene il workspace principale.',
      );
    }
    return DisasterRecoveryPreview(
      exportedAt: exportedAt,
      components: Map.unmodifiable(components),
      assets: Map.unmodifiable(assets),
    );
  }

  static Map<String, Object?> _entry(Uint8List bytes) => {
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      };

  static bool _safePath(String value) {
    if (value.isEmpty ||
        value.startsWith('/') ||
        value.startsWith(r'\') ||
        value.contains(r'\') ||
        value.split('/').any((part) => part.isEmpty || part == '..')) {
      return false;
    }
    return value == 'manifest.json' ||
        value.startsWith('state/') ||
        value.startsWith('assets/');
  }
}
