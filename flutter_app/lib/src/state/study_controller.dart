import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/study_store.dart';
import '../domain/note.dart';
import '../domain/study.dart';

final studyStoreProvider = Provider<StudyStore>((ref) {
  final store = StudyStore();
  ref.onDispose(store.close);
  return store;
});

class StudyState {
  const StudyState({
    this.items = const [],
    this.logs = const [],
    this.loading = true,
    this.error,
  });

  final List<LearningItem> items;
  final List<ReviewLog> logs;
  final bool loading;
  final Object? error;

  StudyState copyWith({
    List<LearningItem>? items,
    List<ReviewLog>? logs,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) =>
      StudyState(
        items: items ?? this.items,
        logs: logs ?? this.logs,
        loading: loading ?? this.loading,
        error: clearError ? null : error ?? this.error,
      );
}

class StudyController extends StateNotifier<StudyState> {
  StudyController(this._store) : super(const StudyState()) {
    refresh();
  }

  final StudyStore _store;

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final snapshot = await _store.snapshot();
      state = StudyState(
        items: snapshot.items,
        logs: snapshot.logs,
        loading: false,
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: error);
    }
  }

  Future<void> createFromNote({
    required Note source,
    required String prompt,
    required String answer,
  }) async {
    final snapshot = source.body.length <= StudyRules.maxSnapshot
        ? source.body
        : source.body.substring(0, StudyRules.maxSnapshot);
    await _store.create(
      sourceNoteId: source.id,
      prompt: prompt,
      answer: answer,
      sourceSnapshot: snapshot,
      sourceUpdatedAt: source.updatedAt,
    );
    await refresh();
  }

  Future<void> review(LearningItem item, StudyRating rating) async {
    await _store.review(item: item, rating: rating);
    await refresh();
  }

  Future<void> delete(String id) async {
    await _store.delete(id);
    await refresh();
  }
}

final studyProvider =
    StateNotifierProvider<StudyController, StudyState>((ref) {
  return StudyController(ref.watch(studyStoreProvider));
});
