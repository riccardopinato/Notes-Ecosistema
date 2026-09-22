import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/legacy_notes_database.dart';
import '../domain/note.dart';

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

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final notes = await _database.loadNotes();
      final collections = await _database.loadCollections();
      state = WorkspaceState(notes: notes, collections: collections, loading: false);
    } catch (error) {
      state = state.copyWith(loading: false, error: error);
    }
  }

  Future<void> save(Note note) async {
    await _database.saveNote(note);
    await refresh();
  }

  Future<void> favorite(String id) async {
    await _database.toggleFavorite(id);
    await refresh();
  }

  Future<void> pin(String id, bool value) async {
    await _database.setPinned(id, value);
    await refresh();
  }

  Future<void> trash(String id) async {
    await _database.trash(id);
    await refresh();
  }
}

final workspaceProvider = StateNotifierProvider<WorkspaceController, WorkspaceState>((ref) {
  return WorkspaceController(ref.watch(databaseProvider));
});
