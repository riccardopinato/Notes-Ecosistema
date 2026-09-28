import 'dart:convert';

import '../domain/note.dart';
import '../domain/semantic_embeddings.dart';
import '../domain/unified_retrieval.dart';
import 'derivative_store.dart';
import 'semantic_index_store.dart';
import 'document_store.dart';
import 'knowledge_store.dart';
import 'property_store.dart';
import 'study_store.dart';

class UnifiedRetrievalService {
  const UnifiedRetrievalService({
    required this.derivativeStore,
    required this.documentStore,
    required this.knowledgeStore,
    required this.propertyStore,
    required this.studyStore,
    this.semanticStore,
    this.embeddingEngine = const LocalHashEmbeddingEngine(),
  });

  final DerivativeStore derivativeStore;
  final DocumentStore documentStore;
  final KnowledgeStore knowledgeStore;
  final PropertyStore propertyStore;
  final StudyStore studyStore;
  final SemanticIndexStore? semanticStore;
  final SemanticEmbeddingEngine embeddingEngine;

  Future<List<RetrievalHit>> search({
    required String query,
    required List<Note> notes,
    int limit = 30,
    bool semanticEnabled = true,
  }) async {
    final documents = <RetrievalDocument>[
      ...UnifiedRetrieval.noteDocuments(notes),
    ];

    final derivativeBackup = await derivativeStore.exportBackup();
    for (final raw in _rows(derivativeBackup['derivatives'])) {
      final noteId = raw['sourceNoteId']?.toString() ?? '';
      final content = raw['content']?.toString() ?? '';
      if (noteId.isEmpty || content.isEmpty) continue;
      final kindName = raw['kind']?.toString() ?? '';
      documents.add(
        RetrievalDocument(
          id: 'derivative:${raw['id']}',
          noteId: noteId,
          kind: kindName.startsWith('ocr')
              ? RetrievalKind.ocr
              : RetrievalKind.derivative,
          title: _noteTitle(notes, noteId),
          text: content,
          updatedAt: (raw['createdAt'] as num?)?.toInt() ?? 0,
        ),
      );
    }

    final studyBackup = await studyStore.exportBackup();
    for (final raw in _rows(studyBackup['items'])) {
      final noteId = raw['sourceNoteId']?.toString() ?? '';
      if (noteId.isEmpty) continue;
      documents.add(
        RetrievalDocument(
          id: 'study:${raw['id']}',
          noteId: noteId,
          kind: RetrievalKind.study,
          title: raw['prompt']?.toString() ?? _noteTitle(notes, noteId),
          text: [
            raw['prompt']?.toString() ?? '',
            raw['answer']?.toString() ?? '',
            raw['sourceSnapshot']?.toString() ?? '',
          ].join('\n'),
          updatedAt: (raw['updatedAt'] as num?)?.toInt() ?? 0,
        ),
      );
    }

    final documentBackup = await documentStore.exportBackup();
    for (final raw in _rows(documentBackup['annotations'])) {
      final noteId = raw['noteId']?.toString() ?? '';
      if (noteId.isEmpty) continue;
      documents.add(
        RetrievalDocument(
          id: 'pdf:${raw['id']}',
          noteId: noteId,
          kind: RetrievalKind.pdfAnnotation,
          title: _noteTitle(notes, noteId),
          text: [
            raw['selectedText']?.toString() ?? '',
            raw['comment']?.toString() ?? '',
          ].join('\n'),
          updatedAt: (raw['updatedAt'] as num?)?.toInt() ?? 0,
        ),
      );
    }

    final propertyBackup = await propertyStore.exportBackup();
    final propertyNames = <String, String>{
      for (final raw in _rows(propertyBackup['definitions']))
        if ((raw['id']?.toString() ?? '').isNotEmpty)
          raw['id'].toString(): raw['name']?.toString() ?? 'Proprietà',
    };
    for (final raw in _rows(propertyBackup['values'])) {
      final noteId = raw['noteId']?.toString() ?? '';
      final definitionId = raw['definitionId']?.toString() ?? '';
      if (noteId.isEmpty || definitionId.isEmpty) continue;
      final rawValue = raw['valueJson']?.toString() ?? '';
      documents.add(
        RetrievalDocument(
          id: 'metadata:$noteId:$definitionId',
          noteId: noteId,
          kind: RetrievalKind.metadata,
          title: _noteTitle(notes, noteId),
          text: '${propertyNames[definitionId] ?? 'Proprietà'}: '
              '${_readableJson(rawValue)}',
          updatedAt: (raw['updatedAt'] as num?)?.toInt() ?? 0,
        ),
      );
    }

    final knowledgeBackup = await knowledgeStore.exportBackup();
    for (final raw in _rows(knowledgeBackup['sources'])) {
      final noteId = raw['noteId']?.toString() ?? '';
      if (noteId.isEmpty) continue;
      documents.add(
        RetrievalDocument(
          id: 'research:${raw['id']}',
          noteId: noteId,
          kind: RetrievalKind.research,
          title: raw['title']?.toString() ?? _noteTitle(notes, noteId),
          text: [
            raw['quote']?.toString() ?? '',
            raw['author']?.toString() ?? '',
            raw['url']?.toString() ?? '',
          ].join('\n'),
          updatedAt: (raw['updatedAt'] as num?)?.toInt() ?? 0,
        ),
      );
    }

    for (final raw in _rows(knowledgeBackup['relations'])) {
      final sourceId = raw['sourceId']?.toString() ?? '';
      final targetId = raw['targetId']?.toString() ?? '';
      if (sourceId.isEmpty || targetId.isEmpty || sourceId == targetId) {
        continue;
      }
      final label = raw['label']?.toString().trim() ?? '';
      final updatedAt = (raw['updatedAt'] as num?)?.toInt() ?? 0;
      documents.add(
        RetrievalDocument(
          id: 'relation:${raw['id']}:source',
          noteId: sourceId,
          kind: RetrievalKind.relation,
          title: _noteTitle(notes, sourceId),
          text: '${label.isEmpty ? 'Collegato a' : label}: '
              '${_noteTitle(notes, targetId)}',
          updatedAt: updatedAt,
        ),
      );
      documents.add(
        RetrievalDocument(
          id: 'relation:${raw['id']}:target',
          noteId: targetId,
          kind: RetrievalKind.relation,
          title: _noteTitle(notes, targetId),
          text: '${label.isEmpty ? 'Collegato da' : label}: '
              '${_noteTitle(notes, sourceId)}',
          updatedAt: updatedAt,
        ),
      );
    }

    final lexical = UnifiedRetrieval.search(
      query,
      documents,
      limit: (limit * 3).clamp(40, 300).toInt(),
    );
    final store = semanticStore;
    if (!semanticEnabled || store == null) {
      return lexical.take(limit).toList(growable: false);
    }

    try {
      await store.syncDocuments(documents, embeddingEngine);
      final semantic = await store.search(
        query,
        embeddingEngine,
        limit: (limit * 4).clamp(60, 400).toInt(),
      );
      return _fuse(
        lexical: lexical,
        semantic: semantic,
        documents: documents,
        limit: limit,
      );
    } catch (_) {
      // Semantic retrieval is a derived optional layer. It must never make
      // canonical literal/FTS-style retrieval unavailable.
      return lexical.take(limit).toList(growable: false);
    }
  }

  Future<List<RetrievalHit>> related({
    required Note source,
    required List<Note> notes,
    int limit = 6,
    bool semanticEnabled = true,
  }) async {
    final store = semanticStore;
    if (!semanticEnabled || store == null) return const [];

    final documents = UnifiedRetrieval.noteDocuments(notes);
    final sourceDocument = documents
        .where((document) => document.noteId == source.id)
        .firstOrNull;
    if (sourceDocument == null) return const [];

    try {
      await store.syncDocuments(documents, embeddingEngine);
      final matches = await store.related(
        sourceDocument,
        embeddingEngine,
        limit: (limit * 4).clamp(30, 200).toInt(),
      );
      final byId = {for (final document in documents) document.id: document};
      final seen = <String>{};
      final result = <RetrievalHit>[];
      for (final match in matches) {
        if (!seen.add(match.noteId)) continue;
        final document = byId[match.documentId];
        if (document == null) continue;
        result.add(
          RetrievalHit(
            document: document,
            score: match.score * 100,
            excerpt: UnifiedRetrieval.excerpt(document.text, source.title),
          ),
        );
        if (result.length >= limit.clamp(1, 20)) break;
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  static List<RetrievalHit> _fuse({
    required List<RetrievalHit> lexical,
    required List<SemanticMatch> semantic,
    required List<RetrievalDocument> documents,
    required int limit,
  }) {
    final byDocumentId = {
      for (final document in documents) document.id: document,
    };
    final lexicalByNote = <String, RetrievalHit>{};
    for (final hit in lexical) {
      lexicalByNote.putIfAbsent(hit.document.noteId, () => hit);
    }

    final scores = <String, double>{};
    final semanticByNote = <String, SemanticMatch>{};

    for (var i = 0; i < lexical.length; i++) {
      final hit = lexical[i];
      scores.update(
        hit.document.noteId,
        (value) => value + 1 / (60 + i + 1),
        ifAbsent: () => 1 / (60 + i + 1),
      );
    }
    for (var i = 0; i < semantic.length; i++) {
      final hit = semantic[i];
      semanticByNote.putIfAbsent(hit.noteId, () => hit);
      final contribution = 0.85 / (60 + i + 1);
      scores.update(
        hit.noteId,
        (value) => value + contribution,
        ifAbsent: () => contribution,
      );
    }

    final noteIds = scores.keys.toList(growable: false)
      ..sort((a, b) {
        final score = scores[b]!.compareTo(scores[a]!);
        if (score != 0) return score;
        return a.compareTo(b);
      });

    final result = <RetrievalHit>[];
    for (final noteId in noteIds) {
      final lexicalHit = lexicalByNote[noteId];
      final semanticHit = semanticByNote[noteId];
      final document = lexicalHit?.document ??
          (semanticHit == null ? null : byDocumentId[semanticHit.documentId]);
      if (document == null) continue;
      result.add(
        RetrievalHit(
          document: document,
          score: scores[noteId]! * 10000,
          excerpt: lexicalHit?.excerpt ??
              UnifiedRetrieval.excerpt(document.text, document.title),
        ),
      );
      if (result.length >= limit.clamp(1, 100)) break;
    }
    return result;
  }

  static List<Map<String, Object?>> _rows(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((row) {
      return row.map((key, value) => MapEntry(key.toString(), value));
    }).toList(growable: false);
  }

  static String _readableJson(String raw) {
    if (raw.trim().isEmpty) return '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.join(', ');
      if (decoded is Map) {
        return decoded.entries
            .map((entry) => '${entry.key}: ${entry.value}')
            .join(', ');
      }
      return decoded?.toString() ?? '';
    } catch (_) {
      return raw;
    }
  }

  static String _noteTitle(List<Note> notes, String noteId) {
    for (final note in notes) {
      if (note.id == noteId) {
        return note.title.trim().isEmpty ? 'Senza titolo' : note.title;
      }
    }
    return 'Contenuto collegato';
  }
}


extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
