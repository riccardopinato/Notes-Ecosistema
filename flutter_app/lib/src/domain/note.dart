import 'dart:convert';

enum VisualDocumentKind { sketch, whiteboard }

class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.favorite,
    required this.createdAt,
    required this.updatedAt,
    required this.pinned,
    required this.archived,
    required this.tags,
    this.collectionId,
    this.deletedAt,
    this.taskJson,
    this.sketchJson,
  });

  final String id;
  final String title;
  final String body;
  final String? collectionId;
  final bool favorite;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final bool pinned;
  final bool archived;
  final List<String> tags;
  final String? taskJson;
  final String? sketchJson;

  bool get isDeleted => deletedAt != null;
  bool get isTask => taskJson != null && taskJson!.trim().isNotEmpty;
  bool get isVisual => sketchJson != null && sketchJson!.trim().isNotEmpty;

  VisualDocumentKind? get visualKind {
    final raw = sketchJson;
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is Map && map['kind']?.toString().toUpperCase() == 'WHITEBOARD') {
        return VisualDocumentKind.whiteboard;
      }
    } catch (_) {}
    return VisualDocumentKind.sketch;
  }

  bool get taskCompleted {
    final raw = taskJson;
    if (raw == null || raw.isEmpty) return false;
    try {
      final map = jsonDecode(raw);
      if (map is Map) {
        final completedAt = map['completedAt'];
        return completedAt != null && completedAt.toString().isNotEmpty;
      }
    } catch (_) {}
    return false;
  }

  String? get taskDue {
    final raw = taskJson;
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is Map) return map['due']?.toString();
    } catch (_) {}
    return null;
  }

  factory Note.fromMap(Map<String, Object?> row) {
    List<String> tags = const [];
    final tagsRaw = row['tagsJson']?.toString();
    if (tagsRaw != null && tagsRaw.isNotEmpty) {
      try {
        tags = (jsonDecode(tagsRaw) as List).map((e) => e.toString()).toList(growable: false);
      } catch (_) {}
    }
    return Note(
      id: row['id']! as String,
      title: row['title']?.toString() ?? '',
      body: row['body']?.toString() ?? '',
      collectionId: row['collectionId']?.toString(),
      favorite: (row['favorite'] as num?)?.toInt() == 1,
      createdAt: (row['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
      deletedAt: (row['deletedAt'] as num?)?.toInt(),
      pinned: (row['pinned'] as num?)?.toInt() == 1,
      archived: (row['archived'] as num?)?.toInt() == 1,
      tags: tags,
      taskJson: row['taskJson']?.toString(),
      sketchJson: row['sketchJson']?.toString(),
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'body': body,
        'collectionId': collectionId,
        'favorite': favorite ? 1 : 0,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'deletedAt': deletedAt,
        'pinned': pinned ? 1 : 0,
        'archived': archived ? 1 : 0,
        'tagsJson': jsonEncode(tags),
        'taskJson': taskJson,
        'sketchJson': sketchJson,
      };

  Note copyWith({
    String? title,
    String? body,
    String? collectionId,
    bool? favorite,
    int? updatedAt,
    int? deletedAt,
    bool? pinned,
    bool? archived,
    List<String>? tags,
    String? taskJson,
    String? sketchJson,
  }) =>
      Note(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        collectionId: collectionId ?? this.collectionId,
        favorite: favorite ?? this.favorite,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
        pinned: pinned ?? this.pinned,
        archived: archived ?? this.archived,
        tags: tags ?? this.tags,
        taskJson: taskJson ?? this.taskJson,
        sketchJson: sketchJson ?? this.sketchJson,
      );
}

class NoteCollection {
  const NoteCollection({required this.id, required this.name});
  final String id;
  final String name;

  factory NoteCollection.fromMap(Map<String, Object?> row) =>
      NoteCollection(id: row['id']! as String, name: row['name']?.toString() ?? '');
}
