import 'dart:convert';
import 'dart:typed_data';

import 'knowledge.dart';
import 'note.dart';
import 'planner.dart';
import 'visual_documents.dart';

class BackupDraft {
  const BackupDraft({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
    required this.tags,
    this.collectionId,
  });

  final String id;
  final String title;
  final String body;
  final String? collectionId;
  final int updatedAt;
  final List<String> tags;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'collectionId': collectionId,
        'updatedAt': updatedAt,
        'tags': tags,
      };
}

class BackupSnapshot {
  const BackupSnapshot({
    required this.notes,
    required this.collections,
    required this.drafts,
  });

  final List<Note> notes;
  final List<NoteCollection> collections;
  final List<BackupDraft> drafts;
}

abstract final class BackupCodec {
  static const maxBytes = 5 * 1024 * 1024;
  static const formatVersion = 6;

  static String encode(BackupSnapshot snapshot, {int? exportedAt}) {
    validate(snapshot);
    Object? decodeOptional(String? raw) {
      if (raw == null || raw.trim().isEmpty) return null;
      return jsonDecode(raw);
    }

    final root = <String, Object?>{
      'format': 'notes-ecosystem',
      'formatVersion': formatVersion,
      'exportedAt': exportedAt ?? DateTime.now().millisecondsSinceEpoch,
      'notes': snapshot.notes
          .map(
            (note) => <String, Object?>{
              'id': note.id,
              'title': note.title,
              'body': note.body,
              'collectionId': note.collectionId,
              'tags': note.tags,
              'task': decodeOptional(note.taskJson),
              'sketch': decodeOptional(note.sketchJson),
              'pinned': note.pinned,
              'archived': note.archived,
              'favorite': note.favorite,
              'createdAt': note.createdAt,
              'updatedAt': note.updatedAt,
              'deletedAt': note.deletedAt,
            },
          )
          .toList(),
      'collections': snapshot.collections
          .map((item) => {'id': item.id, 'name': item.name})
          .toList(),
      'drafts': snapshot.drafts.map((item) => item.toJson()).toList(),
    };
    final text = const JsonEncoder.withIndent('  ').convert(root);
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('Il backup supera 5 MB.');
    }
    return text;
  }

  static BackupSnapshot decode(String input) {
    final bytes = utf8.encode(input);
    if (bytes.length > maxBytes) {
      throw const FormatException('Il backup supera 5 MB.');
    }
    var text = input;
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final root = jsonDecode(text);
    if (root is! Map) {
      throw const FormatException('Il file non contiene un backup JSON.');
    }
    if (root['format'] != 'notes-ecosystem') {
      throw const FormatException('Formato backup non riconosciuto.');
    }
    final version = _int(root['formatVersion'], 'formatVersion');
    if (version < 1 || version > formatVersion) {
      throw const FormatException('Versione backup non supportata.');
    }

    final notesRaw = _list(root['notes'], 'notes');
    final collectionsRaw = _list(root['collections'], 'collections');
    final draftsRaw = _list(root['drafts'], 'drafts');
    if (notesRaw.length > 10000 ||
        collectionsRaw.length > 10000 ||
        draftsRaw.length > 10000) {
      throw const FormatException('Troppi elementi nel backup.');
    }

    final notes = notesRaw.map((value) {
      final map = _map(value, 'nota');
      String? taskJson;
      String? sketchJson;
      if (version >= 4 && map['task'] != null) {
        taskJson = jsonEncode(map['task']);
      }
      if (version >= 5 && map['sketch'] != null) {
        sketchJson = jsonEncode(map['sketch']);
      }
      return Note(
        id: _string(map['id'], 'id'),
        title: _string(map['title'], 'title'),
        body: _string(map['body'], 'body'),
        collectionId: _nullableString(map['collectionId']),
        favorite: _bool(map['favorite'], 'favorite'),
        createdAt: _int(map['createdAt'], 'createdAt'),
        updatedAt: _int(map['updatedAt'], 'updatedAt'),
        deletedAt: _nullableInt(map['deletedAt']),
        pinned: version >= 2 ? _bool(map['pinned'], 'pinned') : false,
        archived:
            version >= 2 ? _bool(map['archived'], 'archived') : false,
        tags: version >= 3
            ? _stringList(map['tags'], 'tags')
            : const [],
        taskJson: taskJson,
        sketchJson: sketchJson,
      );
    }).toList(growable: false);

    final collections = collectionsRaw.map((value) {
      final map = _map(value, 'raccolta');
      return NoteCollection(
        id: _string(map['id'], 'id'),
        name: _string(map['name'], 'name'),
      );
    }).toList(growable: false);

    final drafts = draftsRaw.map((value) {
      final map = _map(value, 'bozza');
      return BackupDraft(
        id: _string(map['id'], 'id'),
        title: _string(map['title'], 'title'),
        body: _string(map['body'], 'body'),
        collectionId: _nullableString(map['collectionId']),
        updatedAt: _int(map['updatedAt'], 'updatedAt'),
        tags: version >= 3
            ? _stringList(map['tags'], 'tags')
            : const [],
      );
    }).toList(growable: false);

    final snapshot = BackupSnapshot(
      notes: notes,
      collections: collections,
      drafts: drafts,
    );
    validate(snapshot);
    return snapshot;
  }

  static void validate(BackupSnapshot data) {
    if (data.notes.length > 10000 ||
        data.collections.length > 10000 ||
        data.drafts.length > 10000) {
      throw const FormatException('Troppi elementi nel backup.');
    }

    Set<String> ids(Iterable<String> values) {
      final list = values.toList();
      if (list.any((id) => id.trim().isEmpty || id.length > 200) ||
          list.toSet().length != list.length) {
        throw const FormatException(
          'Identificativi duplicati o non validi nel backup.',
        );
      }
      return list.toSet();
    }

    ids(data.notes.map((note) => note.id));
    final collectionIds = ids(data.collections.map((item) => item.id));
    ids(data.drafts.map((draft) => draft.id));

    for (final collection in data.collections) {
      if (collection.name.trim().isEmpty) {
        throw const FormatException('Nome raccolta vuoto.');
      }
    }

    for (final note in data.notes) {
      if (note.collectionId != null &&
          !collectionIds.contains(note.collectionId)) {
        throw const FormatException(
          'Il backup fa riferimento a una raccolta mancante.',
        );
      }
      if (note.taskJson != null && note.sketchJson != null) {
        throw const FormatException(
          'Un elemento non può essere attività e documento visuale.',
        );
      }
      if (note.taskJson != null) {
        TaskDetails.decode(note.taskJson!);
      }
      if (note.sketchJson != null) {
        final info = VisualInfo.decode(note.sketchJson!);
        if (info.linkedNoteId == note.id) {
          throw const FormatException(
            'Il documento visuale non può collegare se stesso.',
          );
        }
        if (info.kind == VisualInfoKind.sketch) {
          SketchCodec.decode(note.body);
        } else {
          WhiteboardCodec.decode(note.body);
        }
      }
      if (note.createdAt < 0 ||
          note.updatedAt < 0 ||
          (note.deletedAt != null && note.deletedAt! < 0)) {
        throw const FormatException('Data nota non valida.');
      }
    }

    final deleted = data.notes
        .where((note) => note.isDeleted)
        .map((note) => note.id)
        .toSet();
    for (final draft in data.drafts) {
      if (draft.collectionId != null &&
          !collectionIds.contains(draft.collectionId)) {
        throw const FormatException(
          'Bozza collegata a una raccolta mancante.',
        );
      }
      if (draft.updatedAt < 0 || deleted.contains(draft.id)) {
        throw const FormatException('Bozza non valida nel backup.');
      }
    }
  }

  static Map<String, Object?> _map(Object? value, String name) {
    if (value is! Map) {
      throw FormatException('Elemento $name non valido.');
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static List<Object?> _list(Object? value, String name) {
    if (value is! List) {
      throw FormatException('Campo $name: elenco richiesto.');
    }
    return value.cast<Object?>();
  }

  static String _string(Object? value, String name) {
    if (value is! String) {
      throw FormatException('Campo $name: testo richiesto.');
    }
    return value;
  }

  static String? _nullableString(Object? value) =>
      value == null ? null : value is String ? value : throw const FormatException('Testo non valido.');

  static int _int(Object? value, String name) {
    if (value is! num || value.toInt() != value) {
      throw FormatException('Campo $name: intero richiesto.');
    }
    return value.toInt();
  }

  static int? _nullableInt(Object? value) =>
      value == null ? null : _int(value, 'data');

  static bool _bool(Object? value, String name) {
    if (value is! bool) {
      throw FormatException('Campo $name: booleano richiesto.');
    }
    return value;
  }

  static List<String> _stringList(Object? value, String name) =>
      _list(value, name).map((item) => _string(item, name)).toList();
}

class BackupImportPlan {
  const BackupImportPlan({
    required this.collections,
    required this.notes,
    required this.drafts,
  });

  final List<NoteCollection> collections;
  final List<Note> notes;
  final List<BackupDraft> drafts;
}

abstract final class BackupImport {
  static BackupImportPlan asCopies(
    BackupSnapshot data, {
    required Set<String> existingCollectionNames,
    required String Function() newId,
  }) {
    BackupCodec.validate(data);

    final collectionMap = <String, String>{
      for (final item in data.collections) item.id: newId(),
    };
    final allSourceIds = <String>{
      ...data.notes.map((note) => note.id),
      ...data.drafts.map((draft) => draft.id),
    };
    final noteMap = <String, String>{
      for (final id in allSourceIds) id: newId(),
    };

    final names = {...existingCollectionNames};
    final collections = <NoteCollection>[];
    for (final source in data.collections) {
      final base = source.name;
      var name = base;
      var suffix = 1;
      while (names.contains(name)) {
        name = '$base (importata $suffix)';
        suffix++;
      }
      names.add(name);
      collections.add(
        NoteCollection(id: collectionMap[source.id]!, name: name),
      );
    }

    final importedNoteIds = data.notes
        .where((note) => !note.isTask)
        .map((note) => note.id)
        .toSet();
    final importedTextIds = data.notes
        .where((note) => !note.isTask && !note.isVisual)
        .map((note) => note.id)
        .toSet();

    final notes = data.notes.map((source) {
      String? taskJson = source.taskJson;
      if (taskJson != null) {
        final details = TaskDetails.decode(taskJson);
        final linked = details.linkedNoteId;
        taskJson = details
            .copyWith(
              linkedNoteId: linked != null && importedNoteIds.contains(linked)
                  ? noteMap[linked]
                  : null,
            )
            .encode();
      }

      String? sketchJson = source.sketchJson;
      if (sketchJson != null) {
        final info = VisualInfo.decode(sketchJson);
        final linked = info.linkedNoteId;
        sketchJson = VisualInfo(
          linkedNoteId:
              linked != null && importedTextIds.contains(linked)
                  ? noteMap[linked]
                  : null,
          kind: info.kind,
        ).encode();
      }

      return Note(
        id: noteMap[source.id]!,
        title: source.title,
        body: source.isVisual
            ? source.body
            : Knowledge.remap(source.body, noteMap),
        collectionId: source.collectionId == null
            ? null
            : collectionMap[source.collectionId],
        favorite: source.favorite,
        createdAt: source.createdAt,
        updatedAt: source.updatedAt,
        deletedAt: source.deletedAt,
        pinned: source.pinned,
        archived: source.archived,
        tags: source.tags,
        taskJson: taskJson,
        sketchJson: sketchJson,
      );
    }).toList(growable: false);

    final drafts = data.drafts
        .map(
          (source) => BackupDraft(
            id: noteMap[source.id]!,
            title: source.title,
            body: Knowledge.remap(source.body, noteMap),
            collectionId: source.collectionId == null
                ? null
                : collectionMap[source.collectionId],
            updatedAt: source.updatedAt,
            tags: source.tags,
          ),
        )
        .toList(growable: false);

    return BackupImportPlan(
      collections: collections,
      notes: notes,
      drafts: drafts,
    );
  }
}

Uint8List backupUtf8(BackupSnapshot snapshot) =>
    Uint8List.fromList(utf8.encode(BackupCodec.encode(snapshot)));
