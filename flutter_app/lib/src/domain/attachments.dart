import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum AttachmentCategory { image, audio, file }

enum AttachmentType {
  jpeg('jpg', 'image/jpeg', AttachmentCategory.image),
  png('png', 'image/png', AttachmentCategory.image),
  webp('webp', 'image/webp', AttachmentCategory.image),
  m4a('m4a', 'audio/mp4', AttachmentCategory.audio),
  mp3('mp3', 'audio/mpeg', AttachmentCategory.audio),
  wav('wav', 'audio/wav', AttachmentCategory.audio),
  ogg('ogg', 'audio/ogg', AttachmentCategory.audio),
  pdf('pdf', 'application/pdf', AttachmentCategory.file),
  text('txt', 'text/plain', AttachmentCategory.file),
  docx(
    'docx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    AttachmentCategory.file,
  ),
  xlsx(
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    AttachmentCategory.file,
  ),
  pptx(
    'pptx',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    AttachmentCategory.file,
  );

  const AttachmentType(this.ext, this.mime, this.category);
  final String ext;
  final String mime;
  final AttachmentCategory category;
}

class AttachmentRef {
  const AttachmentRef({
    required this.key,
    required this.name,
    required this.start,
    required this.end,
  });

  final String key;
  final String name;
  final int start;
  final int end;

  AttachmentType get type => Attachments.type(key);
}

abstract final class Attachments {
  static const fileLimit = 8 * 1024 * 1024;
  static const storeLimit = 256 * 1024 * 1024;
  static const maxFiles = 500;

  static final _key = RegExp(
    r'^[a-f0-9]{64}\.(jpg|png|webp|m4a|mp3|wav|ogg|pdf|txt|docx|xlsx|pptx)$',
  );
  static final _link = RegExp(
    r'(?<!!)\[((?:\\.|[^\]\r\n]){1,600})\]\(notes-asset://([a-f0-9]{64}\.[a-z0-9]{2,4})\)',
  );

  static bool validKey(String key) => _key.hasMatch(key);

  static AttachmentType type(String key) {
    if (!validKey(key)) {
      throw const FormatException('Allegato non valido.');
    }
    final ext = key.split('.').last;
    return AttachmentType.values.firstWhere((value) => value.ext == ext);
  }

  static AttachmentType? typeFromName(String name) {
    final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
    for (final type in AttachmentType.values) {
      if (type.ext == ext) return type;
    }
    if (ext == 'jpeg') return AttachmentType.jpeg;
    return null;
  }

  static String digest(Uint8List bytes) => sha256.convert(bytes).toString();

  static String key(Uint8List bytes, AttachmentType type) {
    if (bytes.isEmpty || bytes.length > fileLimit) {
      throw const FormatException(
        'Ogni allegato deve essere tra 1 byte e 8 MiB.',
      );
    }
    return '${digest(bytes)}.${type.ext}';
  }

  static void verify(String key, Uint8List bytes) {
    if (!validKey(key) || Attachments.key(bytes, type(key)) != key) {
      throw const FormatException(
        'Allegato danneggiato: impronta diversa dal nome.',
      );
    }
  }

  static List<AttachmentRef> refs(String body) {
    if (!body.contains('notes-asset://')) return const [];
    return _link.allMatches(body).map((match) {
      final rawLabel = match.group(1) ?? 'Allegato';
      return AttachmentRef(
        key: match.group(2)!,
        name: rawLabel.replaceAllMapped(
          RegExp(r'\\(.)'),
          (m) => m.group(1) ?? '',
        ),
        start: match.start,
        end: match.end,
      );
    }).where((ref) => validKey(ref.key)).toList(growable: false);
  }

  static String append(String body, String key, String name) {
    if (!validKey(key)) {
      throw const FormatException('Allegato non valido.');
    }
    final existing = {...refs(body).map((ref) => ref.key), key};
    if (existing.length > 20) {
      throw const FormatException(
        'Puoi aggiungere fino a 20 allegati per nota.',
      );
    }
    var label = (name.length > 120 ? name.substring(0, 120) : name)
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
        .trim();
    if (label.isEmpty) label = 'Allegato';
    label = label
        .replaceAll('\\', '\\\\')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]');
    final result =
        '$body${body.isEmpty ? '' : '\n\n'}[$label](notes-asset://$key)\n';
    if (result.length > 200000) {
      throw const FormatException('Nota troppo lunga.');
    }
    return result;
  }

  static String remove(String body, String key) {
    var result = body;
    for (final ref in refs(body).where((ref) => ref.key == key).toList().reversed) {
      result = result.replaceRange(ref.start, ref.end, '');
    }
    return result;
  }
}

class AttachmentStore {
  AttachmentStore._(this.root);

  final Directory root;

  static Future<AttachmentStore> open() async {
    final base = await getApplicationSupportDirectory();
    final root = Directory(p.join(base.path, 'attachments'));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    final store = AttachmentStore._(root);
    await store._cleanupStaleTemps();
    return store;
  }

  File file(String key) {
    if (!Attachments.validKey(key)) {
      throw const FormatException('Allegato non valido.');
    }
    return File(p.join(root.path, key));
  }

  Future<bool> contains(String key) => file(key).exists();

  Future<String> ingest(
    Uint8List bytes,
    AttachmentType type,
  ) async {
    final key = Attachments.key(bytes, type);
    await put(key, bytes);
    return key;
  }

  Future<void> put(String key, Uint8List bytes) async {
    Attachments.verify(key, bytes);
    final target = file(key);
    if (await target.exists()) {
      final current = await target.readAsBytes();
      if (sha256.convert(current) == sha256.convert(bytes)) return;
    }

    final entries = await root
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    final valid = entries
        .where((entry) => Attachments.validKey(p.basename(entry.path)))
        .toList();

    if (valid.length >= Attachments.maxFiles && !await target.exists()) {
      throw const FormatException(
        'Limite di 500 allegati sul dispositivo.',
      );
    }

    var used = 0;
    for (final entry in valid) {
      used += await entry.length();
    }
    final oldLength = await target.exists() ? await target.length() : 0;
    if (used - oldLength + bytes.length > Attachments.storeLimit) {
      throw const FormatException(
        'Spazio allegati oltre 256 MiB.',
      );
    }

    final temp = File(
      p.join(
        root.path,
        'incoming-${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(target.path);
    } finally {
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }

  Future<Uint8List> read(String key) async {
    final source = file(key);
    if (!await source.exists()) {
      throw const FileSystemException('Allegato non presente.');
    }
    final bytes = await source.readAsBytes();
    Attachments.verify(key, bytes);
    return bytes;
  }

  Future<void> _cleanupStaleTemps() async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    await for (final entity in root.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith('incoming-') || !name.endsWith('.tmp')) continue;
      try {
        final modified = (await entity.stat()).modified;
        if (modified.isBefore(cutoff)) {
          await entity.delete();
        }
      } catch (_) {
        // Best-effort cleanup: attachment access must not fail for stale temps.
      }
    }
  }

  Future<({int files, int bytes})> cleanup(Set<String> referenced) async {
    await _cleanupStaleTemps();
    var files = 0;
    var bytes = 0;
    await for (final entity in root.list()) {
      if (entity is! File) continue;
      final key = p.basename(entity.path);
      if (!Attachments.validKey(key) || referenced.contains(key)) continue;
      final length = await entity.length();
      await entity.delete();
      files++;
      bytes += length;
    }
    return (files: files, bytes: bytes);
  }

  Future<({int count, int bytes})> usage() async {
    var count = 0;
    var bytes = 0;
    await for (final entity in root.list()) {
      if (entity is File && Attachments.validKey(p.basename(entity.path))) {
        count++;
        bytes += await entity.length();
      }
    }
    return (count: count, bytes: bytes);
  }
}
