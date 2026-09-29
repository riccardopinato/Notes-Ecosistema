import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/knowledge_graph.dart';
import 'package:notes_ecosistema/src/domain/library.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/quick_switcher.dart';
import 'package:notes_ecosistema/src/domain/retrieval_quality.dart';
import 'package:notes_ecosistema/src/domain/semantic_embeddings.dart';

void main() {
  Note note(String id, String title, String body) => Note(
        id: id,
        title: title,
        body: body,
        favorite: false,
        createdAt: 1,
        updatedAt: 2,
        pinned: false,
        archived: false,
        tags: const [],
      );

  final notes = [
    note(
      'car',
      'EV roadmap',
      'Battery charging range, vehicle efficiency and long-distance planning.',
    ),
    note(
      'travel',
      'Dolomites itinerary',
      'Journey, mountain hotel, trail and travel planning.',
    ),
    note(
      'work',
      'Office review',
      'Meeting agenda, project deadline and weekly review.',
    ),
  ];

  test('Quick Switcher can surface a semantic-only note match', () {
    final result = QuickSwitcher.search(
      query: 'automobile autonomia',
      notes: notes,
      collections: const [],
      semanticNoteIds: const ['car'],
    );

    expect(result.first.id, 'car');
    expect(result.first.kind, QuickSwitcherKind.note);
  });

  test('global note search keeps filters while accepting semantic matches', () {
    final result = searchNotes(
      notes,
      query: 'vacanza',
      semanticNoteIds: const ['travel'],
    );

    expect(result.map((item) => item.id), contains('travel'));
    expect(result.map((item) => item.id), isNot(contains('car')));
  });

  test('Knowledge Graph search shares semantic note ranking', () {
    final graph = KnowledgeGraph.build(
      KnowledgeGraphBuildInput(
        notes: notes,
        relations: const [],
        projects: const [],
        projectLinks: const [],
        studyItems: const [],
        pdfAnnotations: const [],
      ),
    );

    final result = KnowledgeGraphSearch.search(
      graph: graph,
      query: 'riunione scadenza',
      semanticNoteIds: const ['work'],
    );

    expect(result.first.id, 'note:work');
  });

  test('local semantic ranking meets curated recall and MRR gate', () {
    const engine = LocalHashEmbeddingEngine();
    final corpus = <String, String>{
      for (final item in notes) item.id: '${item.title}\n${item.body}',
    };

    List<String> rank(String query) {
      final q = engine.embed(query);
      final rows = corpus.entries
          .map(
            (entry) => (
              id: entry.key,
              score: LocalHashEmbeddingEngine.cosine(
                q,
                engine.embed(entry.value),
              ),
            ),
          )
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));
      return rows.map((row) => row.id).toList(growable: false);
    }

    final report = RetrievalQuality.evaluate(
      cases: const [
        RetrievalQualityCase(
          query: 'automobile autonomia',
          relevantIds: {'car'},
        ),
        RetrievalQualityCase(
          query: 'vacanza viaggio',
          relevantIds: {'travel'},
        ),
        RetrievalQualityCase(
          query: 'riunione scadenza',
          relevantIds: {'work'},
        ),
      ],
      ranker: rank,
      k: 3,
    );

    expect(report.recallAtK, 1);
    expect(report.meanReciprocalRank, greaterThanOrEqualTo(0.66));
  });
}
