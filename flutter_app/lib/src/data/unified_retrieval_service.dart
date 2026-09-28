import 'dart:convert';

import '../domain/note.dart';
import '../domain/unified_retrieval.dart';
import 'derivative_store.dart';
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
  });

  final DerivativeStore derivativeStore;
  final DocumentStore documentStore;
  final KnowledgeStore knowledgeStore;
  final PropertyStore propertyStore;
  final StudyStore studyStore;

  Future<List<RetrievalHit>> search({
    required String query,
    required List<Note> notes,
    int limit = 30,
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
      if (sourceId.isEmpty || targetId.isEmpty || sourceId == targetId) continue;
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

    return UnifiedRetrieval.search(query, documents, limit: limit);
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
