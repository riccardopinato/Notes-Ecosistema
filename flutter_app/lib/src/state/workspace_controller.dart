import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/legacy_notes_database.dart';
import '../domain/backup.dart';
import '../domain/library.dart';
import '../domain/note.dart';
import '../domain/templates.dart';

final databaseProvider = Provider<LegacyNotesDatabase>((ref) {
  final database = LegacyNotesDatabase();
  ref.onDispose(database.close);
  return database;
});

class WorkspaceState {
  const WorkspaceState({this.notes = const [], this.collections = const [], this.loading = true, this.error});

  final List<Note> notes;
  final List<NoteCollection> collections;
  final bool loading;
  final Object? error;

  WorkspaceState copyWith({
    List<Note>? notes,
    List<NoteCollection>? collections,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) =>
      WorkspaceState(
        notes: notes ?? this.notes,
        collections: collections ?? this.collections,
        loading: loading ?? this.loading,
        error: clearError ? null : error ?? this.error,
      );
}

class WorkspaceController extends StateNotifier<WorkspaceState> {
  WorkspaceController(this._database) : super(const WorkspaceState()) {
    refresh();
  }

  final LegacyNotesDatabase _database;
  int _refreshGeneration = 0;

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final notes = await _database.loadNotes();
      final collections = await _database.loadCollections();
      if (generation != _refreshGeneration) return;
      state = WorkspaceState(
        notes: notes,
        collections: collections,
        loading: false,
      );
    } catch (error) {
      if (generation != _refreshGeneration) return;
      state = state.copyWith(loading: false, error: error);
    }
  }

  Future<void> save(Note note) async {
    await _database.saveNote(note);
    await _upsertNote(note);
  }

  Future<void> _upsertNote(Note note) async {
    if (state.loading) {
      await refresh();
      return;
    }
    _refreshGeneration++;
    final notes = [
      for (final current in state.notes)
        if (current.id != note.id) current,
      note,
    ]..sort(_compareNotes);
    state = state.copyWith(
      notes: notes,
      loading: false,
      clearError: true,
    );
  }

  Future<void> _reloadNote(String id) async {
    final note = await _database.loadNote(id);
    if (note == null) {
      await refresh();
      return;
    }
    await _upsertNote(note);
  }

  Future<String> createTemplate(TemplateContent content) async {
    final valid = PersonalTemplates.capture(
      content.title,
      content.body,
      content.tags,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = const Uuid().v4();
    final note = Note(
      id: id,
      title: valid.title,
      body: valid.body,
      favorite: false,
      createdAt: now,
      updatedAt: now,
      pinned: false,
      archived: true,
      tags: valid.tags,
    );
    await _database.saveNote(note);
    await _upsertNote(note);
    return id;
  }

  Future<BackupSnapshot> snapshot() => _database.snapshot();

  Future<void> importCopies(BackupSnapshot snapshot) async {
    await _database.importCopies(snapshot);
    await refresh();
  }

  Future<void> createCollection(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    await _database.createCollection(
      NoteCollection(id: const Uuid().v4(), name: clean),
    );
    await refresh();
  }

  Future<int> bulkEdit(
    List<Note> expected,
    BulkChange change,
  ) async {
    final count = await _database.bulkEdit(expected, change);
    await refresh();
    return count;
  }

  Future<void> renameCollection(
    NoteCollection expected,
    String name,
  ) async {
    await _database.renameCollection(expected, name);
    await refresh();
  }

  Future<void> deleteEmptyCollection(NoteCollection expected) async {
    await _database.deleteEmptyCollection(expected);
    await refresh();
  }

  Future<bool> snoozeReminder(
    String id,
    int expectedAt,
    int nextAt,
  ) async {
    final changed = await _database.snoozeReminder(id, expectedAt, nextAt);
    if (changed) await _reloadNote(id);
    return changed;
  }

  Future<void> favorite(String id) async {
    await _database.toggleFavorite(id);
    await _reloadNote(id);
  }

  Future<void> archive(String id, bool value) async {
    await _database.setArchived(id, value);
    await _reloadNote(id);
  }

  Future<void> pin(String id, bool value) async {
    await _database.setPinned(id, value);
    await _reloadNote(id);
  }

  Future<void> trash(String id) async {
    await _database.trash(id);
    await _reloadNote(id);
  }
}

int _compareNotes(Note a, Note b) {
  final favorite = (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0);
  if (favorite != 0) return favorite;
  final pinned = (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
  if (pinned != 0) return pinned;
  final updated = b.updatedAt.compareTo(a.updatedAt);
  if (updated != 0) return updated;
  return a.id.compareTo(b.id);
}

final workspaceProvider = StateNotifierProvider<WorkspaceController, WorkspaceState>((ref) {
  return WorkspaceController(ref.watch(databaseProvider));
});
