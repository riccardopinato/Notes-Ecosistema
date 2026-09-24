import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'note.dart';
import 'planner.dart';
import 'visual_documents.dart';

class SyncDocument {
  const SyncDocument({
    required this.id,
    required this.title,
    required this.body,
    required this.favorite,
    required this.createdAt,
    required this.updatedAt,
    required this.pinned,
    required this.archived,
    required this.tags,
    this.collection,
    this.deletedAt,
    this.taskJson,
    this.sketchJson,
  });

  final String id;
  final String title;
  final String body;
  final String? collection;
  final bool favorite;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final bool pinned;
  final bool archived;
  final List<String> tags;
  final String? taskJson;
  final String? sketchJson;

  factory SyncDocument.fromNote(Note note, String? collection) =>
      SyncDocument(
        id: note.id,
        title: note.title,
        body: note.body,
        collection: collection,
        favorite: note.favorite,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
        deletedAt: note.deletedAt,
        pinned: note.pinned,
        archived: note.archived,
        tags: note.tags,
        taskJson: note.taskJson,
        sketchJson: note.sketchJson,
      );

  SyncDocument tombstone() => SyncDocument(
        id: id,
        title: title,
        body: body,
        collection: collection,
        favorite: favorite,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt ?? updatedAt,
        pinned: pinned,
        archived: archived,
        tags: tags,
        taskJson: taskJson,
        sketchJson: sketchJson,
      );

  @override
  bool operator ==(Object other) =>
      other is SyncDocument &&
      id == other.id &&
      title == other.title &&
      body == other.body &&
      collection == other.collection &&
      favorite == other.favorite &&
      createdAt == other.createdAt &&
      updatedAt == other.updatedAt &&
      deletedAt == other.deletedAt &&
      pinned == other.pinned &&
      archived == other.archived &&
      _listEquals(tags, other.tags) &&
      taskJson == other.taskJson &&
      sketchJson == other.sketchJson;

  @override
  int get hashCode => Object.hash(
        id,
        title,
        body,
        collection,
        favorite,
        createdAt,
        updatedAt,
        deletedAt,
        pinned,
        archived,
        Object.hashAll(tags),
        taskJson,
        sketchJson,
      );
}

enum SyncDecision { same, upload, download, conflict }

SyncDecision decideSync(
  SyncDocument? base,
  SyncDocument? local,
  SyncDocument? remote,
) {
  if (local == remote) return SyncDecision.same;
  if (local == base) return SyncDecision.download;
  if (remote == base) return SyncDecision.upload;
  return SyncDecision.conflict;
}

bool shouldPreserveConcurrentLocal({
  required SyncDocument? expectedLocal,
  required SyncDocument? currentLocal,
  required SyncDocument? remote,
}) =>
    currentLocal != expectedLocal && currentLocal != remote;

abstract final class SyncCodec {
  static const maxBytes = 256 * 1024;

  static String hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static String filename(String id) => '${hash(id)}.md';

  static String encode(SyncDocument document) {
    if (document.taskJson != null && document.sketchJson != null) {
      throw const FormatException(
        'Un elemento non può essere attività e documento visuale.',
      );
    }
    if (document.id.trim().isEmpty ||
        document.id.length > 200 ||
        document.title.length > 8000) {
      throw const FormatException(
        'ID o titolo oltre i limiti della sincronizzazione.',
      );
    }
    if (document.collection != null &&
        (document.collection!.trim().isEmpty ||
            document.collection!.length > 200)) {
      throw const FormatException(
        'Nome raccolta oltre i limiti della sincronizzazione.',
      );
    }
    if (document.createdAt < 0 ||
        document.updatedAt < 0 ||
        (document.deletedAt != null && document.deletedAt! < 0)) {
      throw const FormatException('Data sync non valida.');
    }
    if (document.taskJson != null) {
      TaskDetails.decode(document.taskJson!);
    }
    if (document.sketchJson != null) {
      final info = VisualInfo.decode(document.sketchJson!);
      if (info.kind == VisualInfoKind.sketch) {
        SketchCodec.decode(document.body);
      } else {
        WhiteboardCodec.decode(document.body);
      }
    }

    Object? optionalJson(String? raw) =>
        raw == null || raw.trim().isEmpty ? null : jsonDecode(raw);

    final meta = <String, Object?>{
      'format': 'notes-ecosystem-sync',
      'version': 6,
      'id': document.id,
      'title': document.title,
      'collection': document.collection,
      'tags': document.tags,
      'task': optionalJson(document.taskJson),
      'sketch': optionalJson(document.sketchJson),
      'pinned': document.pinned,
      'archived': document.archived,
      'favorite': document.favorite,
      'createdAt': document.createdAt,
      'updatedAt': document.updatedAt,
      'deletedAt': document.deletedAt,
    };

    final metadata = jsonEncode(meta).replaceAll('--', r'\u002d\u002d');
    final header = '<!-- notes-ecosystem $metadata -->';
    if (header.length > 32768) {
      throw const FormatException(
        'Metadati troppo grandi per la sincronizzazione.',
      );
    }
    final result = '$header\n${document.body}';
    if (utf8.encode(result).length > maxBytes) {
      throw const FormatException(
        'Nota oltre 256 KB: sincronizzazione sospesa.',
      );
    }
    return result;
  }

  static SyncDocument decode(String text) {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('Nota GitHub oltre 256 KB.');
    }
    final end = text.indexOf('\n');
    if (end < 1 || end > 32768) {
      throw const FormatException(
        'Metadati Markdown mancanti o troppo grandi.',
      );
    }
    final header = text.substring(0, end).replaceFirst(RegExp(r'\r'), '');
    const prefix = '<!-- notes-ecosystem ';
    const suffix = ' -->';
    if (!header.startsWith(prefix) || !header.endsWith(suffix)) {
      throw const FormatException('Formato Markdown non riconosciuto.');
    }
    final raw = header.substring(prefix.length, header.length - suffix.length);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Metadati sync non validi.');
    }
    final meta =
        decoded.map((key, value) => MapEntry(key.toString(), value));
    if (meta['format'] != 'notes-ecosystem-sync') {
      throw const FormatException('Formato sync non riconosciuto.');
    }
    final version = _integer(meta['version'], 'version');
    if (version < 1 || version > 6) {
      throw const FormatException('Versione sync non supportata.');
    }

    final id = _string(meta['id'], 'id');
    if (id.trim().isEmpty || id.length > 200) {
      throw const FormatException('ID sync non valido.');
    }

    final taskJson =
        version >= 4 && meta['task'] != null ? jsonEncode(meta['task']) : null;
    final sketchJson = version >= 5 && meta['sketch'] != null
        ? jsonEncode(meta['sketch'])
        : null;

    final document = SyncDocument(
      id: id,
      title: _string(meta['title'], 'title'),
      body: text.substring(end + 1),
      collection: meta['collection'] == null
          ? null
          : _string(meta['collection'], 'collection'),
      favorite: _boolean(meta['favorite'], 'favorite'),
      createdAt: _integer(meta['createdAt'], 'createdAt'),
      updatedAt: _integer(meta['updatedAt'], 'updatedAt'),
      deletedAt: meta['deletedAt'] == null
          ? null
          : _integer(meta['deletedAt'], 'deletedAt'),
      pinned: version >= 2 ? _boolean(meta['pinned'], 'pinned') : false,
      archived:
          version >= 2 ? _boolean(meta['archived'], 'archived') : false,
      tags: version >= 3
          ? _strings(meta['tags'], 'tags')
          : const [],
      taskJson: taskJson,
      sketchJson: sketchJson,
    );

    if (document.taskJson != null && document.sketchJson != null) {
      throw const FormatException('Elemento sync incompatibile.');
    }
    if (taskJson != null) TaskDetails.decode(taskJson);
    if (sketchJson != null) {
      final info = VisualInfo.decode(sketchJson);
      if (info.kind == VisualInfoKind.sketch) {
        SketchCodec.decode(document.body);
      } else {
        WhiteboardCodec.decode(document.body);
      }
    }
    return document;
  }

  static String _string(Object? value, String field) {
    if (value is! String) {
      throw FormatException('Metadato non valido: $field');
    }
    return value;
  }

  static int _integer(Object? value, String field) {
    if (value is! num || value.toInt() != value || value.toInt() < 0) {
      throw FormatException('Intero non valido: $field');
    }
    return value.toInt();
  }

  static bool _boolean(Object? value, String field) {
    if (value is! bool) {
      throw FormatException('Booleano non valido: $field');
    }
    return value;
  }

  static List<String> _strings(Object? value, String field) {
    if (value is! List) {
      throw FormatException('Elenco non valido: $field');
    }
    return value.map((item) => _string(item, field)).toList();
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
