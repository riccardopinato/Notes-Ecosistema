import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/data/local_intelligence_service.dart';
import 'package:notes_ecosistema/src/domain/local_intelligence.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/unified_retrieval.dart';

void main() {
  Note note(String id, String title, String body, {int updatedAt = 1}) => Note(
        id: id,
        title: title,
        body: body,
        favorite: false,
        createdAt: 1,
        updatedAt: updatedAt,
        pinned: false,
        archived: false,
        tags: const [],
      );

  test('model audit keeps Needle gated and multilingual E5 as reference', () {
    final needle = LocalModelAudit.needle;
    expect(needle.role, LocalModelRole.shipCandidate);
    expect(needle.capabilities, contains(LocalModelCapability.embeddings));
    expect(needle.capabilities, contains(LocalModelCapability.toolCalling));
    expect(needle.maxWeightMb, lessThan(40));
    expect(needle.supportsAllProductLanguages, isFalse);

    final compressed = LocalModelAudit.candidates.firstWhere(
      (candidate) => candidate.id == 'me5s-compressed-v3-distilled',
    );
    expect(compressed.role, LocalModelRole.shipCandidate);
    expect(compressed.supportsAllProductLanguages, isTrue);
    expect(compressed.maxWeightMb, lessThan(55));

    final e5 = LocalModelAudit.candidates.firstWhere(
      (candidate) => candidate.id == 'multilingual-e5-small-int8',
    );
    expect(e5.role, LocalModelRole.qualityReference);
    expect(e5.supportsAllProductLanguages, isTrue);
    expect(e5.maxWeightMb, greaterThan(100));
  });

  test('semantic vectors validate dimensions and cosine', () {
    final a = SemanticVector([1, 0, 0]);
    final b = SemanticVector([0.8, 0.2, 0]);
    final opposite = SemanticVector([-1, 0, 0]);

    expect(SemanticVector.cosine(a, b), closeTo(0.9701, 0.001));
    expect(SemanticVector.cosine(a, opposite), -1);
    expect(
      () => SemanticVector.cosine(a, SemanticVector([1, 0])),
      throwsFormatException,
    );
  });

  test('hybrid ranker can recover a semantic result absent from lexical hits',
      () {
    final a = note('a', 'Budget', 'Spese e risparmio');
    final b = note('b', 'Montagna', 'Sentieri e rifugi', updatedAt: 2);
    final documents = [
      RetrievalDocument(
        id: 'note:a',
        noteId: 'a',
        kind: RetrievalKind.note,
        title: a.title,
        text: a.body,
      ),
      RetrievalDocument(
        id: 'note:b',
        noteId: 'b',
        kind: RetrievalKind.note,
        title: b.title,
        text: b.body,
      ),
    ];
    final lexical = [
      RetrievalHit(
        document: documents.first,
        score: 10,
        excerpt: 'Spese',
      ),
    ];

    final hits = HybridSemanticRanker.rank(
      query: 'escursione alpina',
      documents: documents,
      lexicalHits: lexical,
      semanticScores: const [
        SemanticScore(
          documentId: 'note:a',
          noteId: 'a',
          score: 0.05,
        ),
        SemanticScore(
          documentId: 'note:b',
          noteId: 'b',
          score: 0.92,
        ),
      ],
      notes: [a, b],
      semanticWeight: 0.72,
    );

    expect(hits.first.note.id, 'b');
  });

  test('fingerprint changes with semantic document content', () {
    const first = RetrievalDocument(
      id: 'note:a',
      noteId: 'a',
      kind: RetrievalKind.note,
      title: 'Alpha',
      text: 'Uno',
    );
    const second = RetrievalDocument(
      id: 'note:a',
      noteId: 'a',
      kind: RetrievalKind.note,
      title: 'Alpha',
      text: 'Due',
    );
    expect(
      LocalIntelligenceService.fingerprintOf(first),
      isNot(LocalIntelligenceService.fingerprintOf(second)),
    );
  });

  test('six-language benchmark contract can pass with a perfect provider',
      () async {
    final result = await SemanticBenchmark.run(
      provider: _PerfectBenchmarkProvider(),
    );

    expect(result.total, 12);
    expect(result.top1Accuracy, 1);
    expect(result.meanReciprocalRank, 1);
    expect(result.perLanguageTop1.keys.toSet(), {
      'it',
      'en',
      'es',
      'fr',
      'de',
      'pt',
    });
    expect(result.passesNotesGate, isTrue);
  });

  test('unavailable provider reports no local model', () async {
    const provider = UnavailableSemanticProvider();
    expect(await provider.isAvailable(), isFalse);
    expect(provider.telemetryDisabled, isTrue);
    expect(() => provider.embed('test'), throwsStateError);
  });
}

class _PerfectBenchmarkProvider implements SemanticEmbeddingProvider {
  @override
  String get modelId => 'perfect-fixture';

  @override
  String get modelVersion => '1';

  @override
  int get dimensions => 6;

  @override
  bool get telemetryDisabled => true;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<SemanticVector>> embedBatch(List<String> texts) async {
    final result = <SemanticVector>[];
    for (final text in texts) {
      result.add(await embed(text));
    }
    return result;
  }

  @override
  Future<SemanticVector> embed(String text) async {
    final value = text.toLowerCase();
    final concept = _concept(value);
    final vector = List<double>.filled(dimensions, 0);
    vector[concept] = 1;
    return SemanticVector(vector);
  }

  int _concept(String value) {
    if (_has(value, [
      'montagna',
      'sentieri',
      'rifugi',
      'escursioni',
      'randonnées',
      'refuges',
    ])) {
      return 0;
    }
    if (_has(value, [
      'budget',
      'spese',
      'risparmio',
      'expenses',
      'savings',
      'ausgaben',
      'sparziele',
    ])) {
      return 1;
    }
    if (_has(value, [
      'esame',
      'ripasso',
      'exam',
      'réviser',
      'examen',
      'study',
    ])) {
      return 2;
    }
    if (_has(value, [
      'progetto',
      'task',
      'milestone',
      'project',
      'proyecto',
      'tareas',
      'meilensteine',
      'fristen',
    ])) {
      return 3;
    }
    if (_has(value, [
      'allenamento',
      'recupero',
      'sonno',
      'training',
      'recovery',
      'treino',
      'recuperação',
      'entrenamiento',
      'recuperación',
      'sueño',
    ])) {
      return 4;
    }
    if (_has(value, [
      'pdf',
      'ocr',
      'document',
      'annotazioni',
      'anotações',
      'archivos',
    ])) {
      return 5;
    }
    throw StateError('Benchmark fixture non classificata: $value');
  }

  bool _has(String value, List<String> words) =>
      words.any((word) => value.contains(word));
}
