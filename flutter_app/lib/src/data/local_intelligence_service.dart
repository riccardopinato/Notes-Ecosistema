import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/intelligence.dart';
import '../domain/local_intelligence.dart';
import '../domain/note.dart';
import '../domain/unified_retrieval.dart';
import 'semantic_index_store.dart';
import 'unified_retrieval_service.dart';

class LocalIntelligenceStatus {
  const LocalIntelligenceStatus({
    required this.providerAvailable,
    required this.indexedDocuments,
    required this.totalDocuments,
    required this.modelId,
    required this.modelVersion,
  });

  final bool providerAvailable;
  final int indexedDocuments;
  final int totalDocuments;
  final String modelId;
  final String modelVersion;

  bool get indexComplete =>
      providerAvailable &&
      totalDocuments > 0 &&
      indexedDocuments >= totalDocuments;
}

class LocalIntelligenceService {
  const LocalIntelligenceService({
    required this.retrieval,
    required this.index,
    required this.provider,
  });

  final UnifiedRetrievalService retrieval;
  final SemanticIndexStore index;
  final SemanticEmbeddingProvider provider;

  Future<LocalIntelligenceStatus> status(List<Note> notes) async {
    final available = await provider.isAvailable();
    if (!available) {
      return LocalIntelligenceStatus(
        providerAvailable: false,
        indexedDocuments: 0,
        totalDocuments: 0,
        modelId: provider.modelId,
        modelVersion: provider.modelVersion,
      );
    }
    final documents = await retrieval.documents(notes: notes);
    final count = await index.count(
      modelId: provider.modelId,
      modelVersion: provider.modelVersion,
    );
    return LocalIntelligenceStatus(
      providerAvailable: true,
      indexedDocuments: count,
      totalDocuments: documents.length,
      modelId: provider.modelId,
      modelVersion: provider.modelVersion,
    );
  }

  Future<int> rebuildIndex(
    List<Note> notes, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (!await provider.isAvailable()) {
      throw StateError('Modello locale non installato.');
    }
    if (!provider.telemetryDisabled) {
      throw StateError(
        'Il provider locale non può essere usato finché la telemetria '
        'non è esplicitamente disattivata.',
      );
    }

    final documents = await retrieval.documents(notes: notes);
    final liveIds = documents.map((item) => item.id).toSet();
    await index.deleteStale(
      modelId: provider.modelId,
      modelVersion: provider.modelVersion,
      liveDocumentIds: liveIds,
    );

    final missing = <RetrievalDocument>[];
    for (final document in documents) {
      final fingerprint = fingerprintOf(document);
      final current = await index.get(
        modelId: provider.modelId,
        modelVersion: provider.modelVersion,
        documentId: document.id,
      );
      if (current == null ||
          current.fingerprint != fingerprint ||
          current.vector.values.length != provider.dimensions) {
        missing.add(document);
      }
    }

    var done = documents.length - missing.length;
    onProgress?.call(done, documents.length);
    const batchSize = 8;
    for (var offset = 0; offset < missing.length; offset += batchSize) {
      final end = offset + batchSize < missing.length
          ? offset + batchSize
          : missing.length;
      final batch = missing.sublist(offset, end);
      final vectors = await provider.embedBatch(
        batch.map(_documentText).toList(growable: false),
      );
      if (vectors.length != batch.length) {
        throw StateError('Il provider ha restituito un batch incompleto.');
      }
      for (var indexInBatch = 0;
          indexInBatch < batch.length;
          indexInBatch++) {
        final document = batch[indexInBatch];
        final vector = vectors[indexInBatch];
        if (vector.values.length != provider.dimensions) {
          throw StateError('Dimensione embedding inattesa.');
        }
        await index.upsert(
          SemanticIndexEntry(
            modelId: provider.modelId,
            modelVersion: provider.modelVersion,
            documentId: document.id,
            noteId: document.noteId,
            fingerprint: fingerprintOf(document),
            vector: vector,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        done++;
        onProgress?.call(done, documents.length);
      }
    }
    return done;
  }

  Future<KnowledgeQueryResult> search({
    required String query,
    required List<Note> notes,
    int limit = 8,
  }) async {
    final documents = await retrieval.documents(notes: notes);
    final lexical = UnifiedRetrieval.search(
      query,
      documents,
      limit: 100,
    );

    if (!await provider.isAvailable() || !provider.telemetryDisabled) {
      return _lexicalResult(query, lexical, notes, limit);
    }

    await rebuildIndex(notes);
    final queryVector = await provider.embed(query);
    if (queryVector.values.length != provider.dimensions) {
      return _lexicalResult(query, lexical, notes, limit);
    }
    final indexed = await index.forModel(
      modelId: provider.modelId,
      modelVersion: provider.modelVersion,
    );
    final scores = <SemanticScore>[];
    final live = documents.map((item) => item.id).toSet();
    for (final entry in indexed) {
      if (!live.contains(entry.documentId) ||
          entry.vector.values.length != queryVector.values.length) {
        continue;
      }
      scores.add(
        SemanticScore(
          documentId: entry.documentId,
          noteId: entry.noteId,
          score: SemanticVector.cosine(queryVector, entry.vector),
        ),
      );
    }

    final hits = HybridSemanticRanker.rank(
      query: query,
      documents: documents,
      lexicalHits: lexical,
      semanticScores: scores,
      notes: notes,
      limit: limit,
    );
    return KnowledgeQueryResult(query: query.trim(), hits: hits);
  }

  Future<List<KnowledgeHit>> related({
    required Note source,
    required List<Note> notes,
    int limit = 6,
  }) async {
    if (!await provider.isAvailable() || !provider.telemetryDisabled) {
      return const LocalKnowledgeRetrieval().related(
        source,
        notes,
        limit: limit,
      );
    }

    await rebuildIndex(notes);
    final queryVector = await provider.embed(
      _boundedText('${source.title}\n${source.body}'),
    );
    final indexed = await index.forModel(
      modelId: provider.modelId,
      modelVersion: provider.modelVersion,
    );
    final byNote = {for (final note in notes) note.id: note};
    final best = <String, double>{};
    for (final entry in indexed) {
      if (entry.noteId == source.id ||
          entry.vector.values.length != queryVector.values.length) {
        continue;
      }
      final note = byNote[entry.noteId];
      if (note == null || note.isDeleted || note.archived || note.isVisual) {
        continue;
      }
      final score = SemanticVector.cosine(queryVector, entry.vector);
      best.update(
        entry.noteId,
        (value) => value > score ? value : score,
        ifAbsent: () => score,
      );
    }

    final ranked = best.entries.where((entry) => entry.value >= 0.18).toList()
      ..sort((a, b) {
        final score = b.value.compareTo(a.value);
        if (score != 0) return score;
        final aNote = byNote[a.key]!;
        final bNote = byNote[b.key]!;
        return bNote.updatedAt.compareTo(aNote.updatedAt);
      });
    return ranked.take(limit.clamp(1, 20)).map((entry) {
      final note = byNote[entry.key]!;
      return KnowledgeHit(
        note: note,
        score: entry.value,
        excerpt: UnifiedRetrieval.excerpt(note.body, source.title),
      );
    }).toList(growable: false);
  }

  Future<SemanticBenchmarkResult> benchmark() async {
    final result = await SemanticBenchmark.run(provider: provider);
    await index.setMeta(
      'benchmark:${provider.modelId}:${provider.modelVersion}',
      jsonEncode({
        'modelId': result.modelId,
        'modelVersion': result.modelVersion,
        'total': result.total,
        'top1': result.top1,
        'top1Accuracy': result.top1Accuracy,
        'meanReciprocalRank': result.meanReciprocalRank,
        'perLanguageTop1': result.perLanguageTop1,
        'elapsedMilliseconds': result.elapsedMilliseconds,
        'passesNotesGate': result.passesNotesGate,
        'ranAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    return result;
  }

  Future<void> purgeNote(String noteId) => index.deleteForNote(noteId);

  static String fingerprintOf(RetrievalDocument document) {
    final canonical = [
      document.id,
      document.noteId,
      document.kind.name,
      document.title,
      document.text,
      document.tags.join('\u001f'),
    ].join('\u001e');
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static String _documentText(RetrievalDocument document) => _boundedText(
        [
          document.title,
          document.tags.join(' '),
          document.text,
        ].where((value) => value.trim().isNotEmpty).join('\n'),
      );

  static String _boundedText(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 3200) return compact;
    return compact.substring(0, 3200);
  }

  static KnowledgeQueryResult _lexicalResult(
    String query,
    List<RetrievalHit> lexical,
    List<Note> notes,
    int limit,
  ) {
    final byId = {for (final note in notes) note.id: note};
    final hits = <KnowledgeHit>[];
    for (final hit in lexical) {
      final note = byId[hit.document.noteId];
      if (note == null) continue;
      hits.add(
        KnowledgeHit(
          note: note,
          score: hit.score,
          excerpt: hit.excerpt,
        ),
      );
      if (hits.length >= limit.clamp(1, 30)) break;
    }
    return KnowledgeQueryResult(query: query.trim(), hits: hits);
  }
}

class UnavailableSemanticProvider implements SemanticEmbeddingProvider {
  const UnavailableSemanticProvider({
    this.modelId = 'needle3',
    this.modelVersion = 'not-installed',
    this.dimensions = 128,
  });

  @override
  final String modelId;

  @override
  final String modelVersion;

  @override
  final int dimensions;

  @override
  bool get telemetryDisabled => true;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<SemanticVector> embed(String text) {
    throw StateError('Modello semantico locale non installato.');
  }
}
