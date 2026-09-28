import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local_intelligence_service.dart';
import '../data/semantic_index_store.dart';
import '../data/unified_retrieval_service.dart';
import '../domain/local_intelligence.dart';
import '../domain/note.dart';
import 'document_controller.dart';
import 'study_controller.dart';
import 'workspace_controller.dart';

final semanticIndexStoreProvider = Provider<SemanticIndexStore>((ref) {
  final store = SemanticIndexStore();
  ref.onDispose(store.close);
  return store;
});

final semanticEmbeddingProviderProvider =
    Provider<SemanticEmbeddingProvider>((ref) {
  return const UnavailableSemanticProvider();
});

final localIntelligenceServiceProvider =
    Provider<LocalIntelligenceService>((ref) {
  return LocalIntelligenceService(
    retrieval: UnifiedRetrievalService(
      derivativeStore: ref.watch(derivativeStoreProvider),
      documentStore: ref.watch(documentStoreProvider),
      knowledgeStore: ref.watch(knowledgeStoreProvider),
      propertyStore: ref.watch(propertyStoreProvider),
      studyStore: ref.watch(studyStoreProvider),
    ),
    index: ref.watch(semanticIndexStoreProvider),
    provider: ref.watch(semanticEmbeddingProviderProvider),
  );
});

class LocalIntelligenceState {
  const LocalIntelligenceState({
    this.enabled = false,
    this.loading = true,
    this.providerAvailable = false,
    this.indexedDocuments = 0,
    this.totalDocuments = 0,
    this.modelId = 'needle3',
    this.modelVersion = 'not-installed',
    this.progress,
    this.benchmark,
    this.error,
  });

  final bool enabled;
  final bool loading;
  final bool providerAvailable;
  final int indexedDocuments;
  final int totalDocuments;
  final String modelId;
  final String modelVersion;
  final double? progress;
  final SemanticBenchmarkResult? benchmark;
  final Object? error;

  bool get active => enabled && providerAvailable;

  LocalIntelligenceState copyWith({
    bool? enabled,
    bool? loading,
    bool? providerAvailable,
    int? indexedDocuments,
    int? totalDocuments,
    String? modelId,
    String? modelVersion,
    Object? progress = _unset,
    Object? benchmark = _unset,
    Object? error = _unset,
  }) =>
      LocalIntelligenceState(
        enabled: enabled ?? this.enabled,
        loading: loading ?? this.loading,
        providerAvailable: providerAvailable ?? this.providerAvailable,
        indexedDocuments: indexedDocuments ?? this.indexedDocuments,
        totalDocuments: totalDocuments ?? this.totalDocuments,
        modelId: modelId ?? this.modelId,
        modelVersion: modelVersion ?? this.modelVersion,
        progress:
            identical(progress, _unset) ? this.progress : progress as double?,
        benchmark: identical(benchmark, _unset)
            ? this.benchmark
            : benchmark as SemanticBenchmarkResult?,
        error: identical(error, _unset) ? this.error : error,
      );
}

class LocalIntelligenceController
    extends StateNotifier<LocalIntelligenceState> {
  LocalIntelligenceController(this._service)
      : super(const LocalIntelligenceState()) {
    _loadPreference();
  }

  static const _enabledKey = 'local_intelligence_enabled_v1';

  final LocalIntelligenceService _service;

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      enabled: prefs.getBool(_enabledKey) ?? false,
      loading: false,
    );
  }

  Future<void> refresh(List<Note> notes) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final status = await _service.status(notes);
      state = state.copyWith(
        loading: false,
        providerAvailable: status.providerAvailable,
        indexedDocuments: status.indexedDocuments,
        totalDocuments: status.totalDocuments,
        modelId: status.modelId,
        modelVersion: status.modelVersion,
        progress: null,
        error: null,
      );
    } catch (error) {
      state = state.copyWith(loading: false, progress: null, error: error);
    }
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    state = state.copyWith(enabled: value);
  }

  Future<void> rebuild(List<Note> notes) async {
    state = state.copyWith(loading: true, progress: 0.0, error: null);
    try {
      await _service.rebuildIndex(
        notes,
        onProgress: (done, total) {
          state = state.copyWith(
            progress: total <= 0 ? 1.0 : done / total,
          );
        },
      );
      await refresh(notes);
    } catch (error) {
      state = state.copyWith(loading: false, progress: null, error: error);
    }
  }

  Future<void> runBenchmark(List<Note> notes) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final result = await _service.benchmark();
      state = state.copyWith(
        loading: false,
        benchmark: result,
        error: null,
      );
      await refresh(notes);
      state = state.copyWith(benchmark: result);
    } catch (error) {
      state = state.copyWith(loading: false, error: error);
    }
  }

  Future<void> clearIndex(List<Note> notes) async {
    await _service.index.clearAll();
    await refresh(notes);
  }
}

final localIntelligenceProvider =
    StateNotifierProvider<LocalIntelligenceController, LocalIntelligenceState>(
        (ref) {
  return LocalIntelligenceController(
    ref.watch(localIntelligenceServiceProvider),
  );
});

const _unset = Object();
