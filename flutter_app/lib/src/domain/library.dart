import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'editing.dart';
import 'note.dart';

enum NoteScope { all, inbox, favorites, trash, archive }

enum TaskPresence { any, hasTasks, openTasks, noTasks }

enum NoteOrder { recent, created, oldest, title }

class SearchOptions {
  const SearchOptions({
    this.tags = const [],
    this.allTags = true,
    this.favoritesOnly = false,
    this.pinnedOnly = false,
    this.tasks = TaskPresence.any,
  });

  final List<String> tags;
  final bool allTags;
  final bool favoritesOnly;
  final bool pinnedOnly;
  final TaskPresence tasks;

  SearchOptions copyWith({
    List<String>? tags,
    bool? allTags,
    bool? favoritesOnly,
    bool? pinnedOnly,
    TaskPresence? tasks,
  }) =>
      SearchOptions(
        tags: tags ?? this.tags,
        allTags: allTags ?? this.allTags,
        favoritesOnly: favoritesOnly ?? this.favoritesOnly,
        pinnedOnly: pinnedOnly ?? this.pinnedOnly,
        tasks: tasks ?? this.tasks,
      );
}

List<Note> searchNotes(
  List<Note> notes, {
  NoteScope scope = NoteScope.all,
  String query = '',
  String? collectionId,
  SearchOptions options = const SearchOptions(),
  String kind = 'Tutte',
  NoteOrder order = NoteOrder.recent,
}) {
  final needle = query.trim().toLowerCase();
  final tags = NoteTags.normalize(options.tags);
  final filtered = notes.where((note) {
    // Deleted tasks must remain reachable from the universal trash so they can
    // be restored or permanently deleted like every other user-owned item.
    if (note.isTask && scope != NoteScope.trash) return false;

    final visible = switch (scope) {
      NoteScope.trash => note.isDeleted,
      NoteScope.archive => !note.isDeleted && note.archived,
      _ => !note.isDeleted && !note.archived,
    };
    if (!visible) return false;
    if (scope == NoteScope.inbox && note.collectionId != null) return false;
    if (scope == NoteScope.favorites && !note.favorite) return false;
    if (collectionId != null && note.collectionId != collectionId) {
      return false;
    }

    if (needle.isNotEmpty) {
      final inText = note.title.toLowerCase().contains(needle) ||
          (!note.isVisual && note.body.toLowerCase().contains(needle)) ||
          note.tags.any(
            (tag) => tag.toLowerCase().contains(
                  needle.startsWith('#') ? needle.substring(1) : needle,
                ),
          );
      if (!inText) return false;
    }

    if (options.favoritesOnly && !note.favorite) return false;
    if (options.pinnedOnly && !note.pinned) return false;
    if (tags.isNotEmpty) {
      final matches = options.allTags
          ? tags.every(note.tags.contains)
          : tags.any(note.tags.contains);
      if (!matches) return false;
    }

    final needsChecklist = options.tasks != TaskPresence.any ||
        kind == 'Testo' ||
        kind == 'Checklist';
    final checklist =
        needsChecklist ? Checklist.parse(note.body) : const <ChecklistItem>[];
    switch (options.tasks) {
      case TaskPresence.any:
        break;
      case TaskPresence.hasTasks:
        if (checklist.isEmpty) return false;
        break;
      case TaskPresence.openTasks:
        if (!checklist.any((item) => !item.completed)) return false;
        break;
      case TaskPresence.noTasks:
        if (checklist.isNotEmpty) return false;
        break;
    }

    switch (kind) {
      case 'Testo':
        if (note.isVisual || checklist.isNotEmpty) return false;
        break;
      case 'Checklist':
        if (note.isVisual || checklist.isEmpty) return false;
        break;
      case 'Disegni':
        if (note.visualKind != VisualDocumentKind.sketch) return false;
        break;
      case 'Lavagne':
        if (note.visualKind != VisualDocumentKind.whiteboard) return false;
        break;
    }
    return true;
  }).toList();

  filtered.sort(_comparator(order));
  return filtered;
}

Comparator<Note> _comparator(NoteOrder order) {
  int pinned(Note a, Note b) => (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0);
  return (a, b) {
    final first = pinned(a, b);
    if (first != 0) return first;
    switch (order) {
      case NoteOrder.recent:
        final favorite = (b.favorite ? 1 : 0) - (a.favorite ? 1 : 0);
        if (favorite != 0) return favorite;
        final updated = b.updatedAt.compareTo(a.updatedAt);
        if (updated != 0) return updated;
        break;
      case NoteOrder.created:
        final created = b.createdAt.compareTo(a.createdAt);
        if (created != 0) return created;
        break;
      case NoteOrder.oldest:
        final created = a.createdAt.compareTo(b.createdAt);
        if (created != 0) return created;
        break;
      case NoteOrder.title:
        final titleA = a.title.trim().isEmpty
            ? 'senza titolo'
            : a.title.trim().toLowerCase();
        final titleB = b.title.trim().isEmpty
            ? 'senza titolo'
            : b.title.trim().toLowerCase();
        final title = titleA.compareTo(titleB);
        if (title != 0) return title;
        break;
    }
    return a.id.compareTo(b.id);
  };
}

enum BulkAction {
  archive,
  unarchive,
  pin,
  unpin,
  favorite,
  unfavorite,
  move,
  addTag,
  removeTag,
  trash,
  restore,
}

class BulkChange {
  const BulkChange(this.action, {this.collectionId, this.tag});
  final BulkAction action;
  final String? collectionId;
  final String? tag;
}

List<Note> planBulkEdit(
  List<Note> notes,
  BulkChange change,
  int now,
) {
  if (notes.isEmpty || notes.length > 500) {
    throw const FormatException('Seleziona da 1 a 500 note.');
  }
  if (notes.map((e) => e.id).toSet().length != notes.length) {
    throw const FormatException('Selezione duplicata.');
  }

  String? tag;
  if (change.action == BulkAction.addTag ||
      change.action == BulkAction.removeTag) {
    tag = NoteTags.name(change.tag ?? '');
  }

  return notes.map((note) {
    if (change.action == BulkAction.restore) {
      if (!note.isDeleted) {
        throw const FormatException(
          'La selezione contiene note con uno stato non compatibile.',
        );
      }
    } else if (note.isDeleted) {
      throw const FormatException(
        'La selezione contiene note con uno stato non compatibile.',
      );
    }

    Note result;
    switch (change.action) {
      case BulkAction.archive:
        result = note.copyWith(archived: true);
        break;
      case BulkAction.unarchive:
        result = note.copyWith(archived: false);
        break;
      case BulkAction.pin:
        result = note.copyWith(pinned: true);
        break;
      case BulkAction.unpin:
        result = note.copyWith(pinned: false);
        break;
      case BulkAction.favorite:
        result = note.copyWith(favorite: true);
        break;
      case BulkAction.unfavorite:
        result = note.copyWith(favorite: false);
        break;
      case BulkAction.move:
        result = note.copyWith(collectionId: change.collectionId);
        break;
      case BulkAction.addTag:
        result = note.copyWith(tags: NoteTags.add(note.tags, tag!));
        break;
      case BulkAction.removeTag:
        result = note.copyWith(
          tags: note.tags.where((value) => value != tag).toList(),
        );
        break;
      case BulkAction.trash:
        result = note.copyWith(deletedAt: now);
        break;
      case BulkAction.restore:
        result = note.copyWith(deletedAt: null);
        break;
    }
    return result.toMap().toString() == note.toMap().toString()
        ? note
        : result.copyWith(updatedAt: now);
  }).toList();
}

class SavedSearch {
  const SavedSearch({
    required this.id,
    required this.name,
    this.query = '',
    this.scope = NoteScope.all,
    this.collectionId,
    this.options = const SearchOptions(),
    this.kind = 'Tutte',
    this.order = NoteOrder.recent,
  });

  final String id;
  final String name;
  final String query;
  final NoteScope scope;
  final String? collectionId;
  final SearchOptions options;
  final String kind;
  final NoteOrder order;

  SavedSearch copyWith({
    String? id,
    String? name,
    String? query,
    NoteScope? scope,
    Object? collectionId = _unset,
    SearchOptions? options,
    String? kind,
    NoteOrder? order,
  }) =>
      SavedSearch(
        id: id ?? this.id,
        name: name ?? this.name,
        query: query ?? this.query,
        scope: scope ?? this.scope,
        collectionId: identical(collectionId, _unset)
            ? this.collectionId
            : collectionId as String?,
        options: options ?? this.options,
        kind: kind ?? this.kind,
        order: order ?? this.order,
      );

  factory SavedSearch.create({
    required String name,
    required String query,
    required NoteScope scope,
    required String? collectionId,
    required SearchOptions options,
    required String kind,
    required NoteOrder order,
  }) =>
      SavedSearch(
        id: const Uuid().v4(),
        name: name,
        query: query,
        scope: scope,
        collectionId: collectionId,
        options: options,
        kind: kind,
        order: order,
      );
}

const _unset = Object();

SavedSearch validateSavedSearch(SavedSearch search) {
  final name = search.name.trim();
  if (search.id.trim().isEmpty || search.id.length > 200) {
    throw const FormatException('Identificatore ricerca non valido.');
  }
  if (name.isEmpty || name.length > 80 || name.codeUnits.any((c) => c < 32)) {
    throw const FormatException('Usa un nome di 1–80 caratteri.');
  }
  if (search.query.length > 8000 || search.query.contains('\u0000')) {
    throw const FormatException('Ricerca troppo lunga o non valida.');
  }
  if (!const {'Tutte', 'Testo', 'Checklist', 'Disegni', 'Lavagne'}
      .contains(search.kind)) {
    throw const FormatException('Tipo ricerca non valido.');
  }
  return search.copyWith(
    name: name,
    options: search.options.copyWith(
      tags: NoteTags.normalize(search.options.tags),
    ),
  );
}

class SavedSearchCodec {
  static String encode(List<SavedSearch> values) {
    if (values.length > 30 ||
        values.map((e) => e.id).toSet().length != values.length) {
      throw const FormatException('Archivio ricerche non valido.');
    }
    final checked = <SavedSearch>[];
    for (final source in values) {
      final value = validateSavedSearch(source);
      if (checked.any(
        (item) =>
            item.id != value.id &&
            item.name.toLowerCase() == value.name.toLowerCase(),
      )) {
        throw const FormatException(
          'Esiste già una ricerca con questo nome.',
        );
      }
      checked.add(value);
    }
    final raw = jsonEncode({
      'version': 1,
      'searches': checked
          .map(
            (s) => {
              'id': s.id,
              'name': s.name,
              'query': s.query,
              'filter': s.scope.name.toUpperCase(),
              'collectionId': s.collectionId,
              'kind': s.kind,
              'order': s.order.name.toUpperCase(),
              'tags': s.options.tags,
              'allTags': s.options.allTags,
              'favoritesOnly': s.options.favoritesOnly,
              'pinnedOnly': s.options.pinnedOnly,
              'tasks': s.options.tasks.name.toUpperCase(),
            },
          )
          .toList(),
    });
    if (raw.length > 400000) {
      throw const FormatException(
        'Le ricerche salvate sono troppo lunghe.',
      );
    }
    return raw;
  }

  static List<SavedSearch> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    if (raw.length > 400000) {
      throw const FormatException('Archivio ricerche troppo grande.');
    }
    final root = jsonDecode(raw);
    if (root is! Map || root['version'] != 1 || root['searches'] is! List) {
      throw const FormatException('Versione ricerche non supportata.');
    }
    final rows = root['searches'] as List;
    if (rows.length > 30) {
      throw const FormatException('Troppe ricerche salvate.');
    }
    final result = <SavedSearch>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final search = validateSavedSearch(
        SavedSearch(
          id: row['id']?.toString() ?? '',
          name: row['name']?.toString() ?? '',
          query: row['query']?.toString() ?? '',
          scope: NoteScope.values.firstWhere(
            (v) => v.name.toUpperCase() == row['filter']?.toString(),
            orElse: () => NoteScope.all,
          ),
          collectionId: row['collectionId']?.toString(),
          options: SearchOptions(
            tags: (row['tags'] as List? ?? const [])
                .map((e) => e.toString())
                .toList(),
            allTags: row['allTags'] == true,
            favoritesOnly: row['favoritesOnly'] == true,
            pinnedOnly: row['pinnedOnly'] == true,
            tasks: TaskPresence.values.firstWhere(
              (v) => v.name.toUpperCase() == row['tasks']?.toString(),
              orElse: () => TaskPresence.any,
            ),
          ),
          kind: row['kind']?.toString() ?? 'Tutte',
          order: NoteOrder.values.firstWhere(
            (v) => v.name.toUpperCase() == row['order']?.toString(),
            orElse: () => NoteOrder.recent,
          ),
        ),
      );
      if (result.any((item) => item.id == search.id)) {
        throw const FormatException('Ricerca duplicata.');
      }
      result.add(search);
    }
    return result;
  }
}
