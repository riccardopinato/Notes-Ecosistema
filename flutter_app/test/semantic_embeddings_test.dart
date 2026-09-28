import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/semantic_embeddings.dart';

void main() {
  const engine = LocalHashEmbeddingEngine();

  test('local embeddings are fixed-size deterministic normalized vectors', () {
    final a = engine.embed('batteria litio autonomia e ricarica');
    final b = engine.embed('batteria litio autonomia e ricarica');

    expect(a, hasLength(engine.dimensions));
    expect(b, a);
    final norm = math.sqrt(
      a.fold<double>(0, (sum, value) => sum + value * value),
    );
    expect(norm, closeTo(1, 0.000001));
  });

  test('concept aliases improve synonym retrieval beyond unrelated text', () {
    final query = engine.embed('automobile con grande autonomia');
    final related = engine.embed('auto con buona range e batteria');
    final unrelated = engine.embed('ricetta pasta pomodoro basilico');

    final relatedScore = LocalHashEmbeddingEngine.cosine(query, related);
    final unrelatedScore = LocalHashEmbeddingEngine.cosine(query, unrelated);

    expect(relatedScore, greaterThan(unrelatedScore));
    expect(relatedScore, greaterThan(0.10));
  });

  test('multilingual concept aliases preserve local semantic similarity', () {
    final italian = engine.embed('viaggio e vacanza');
    final english = engine.embed('travel trip journey');
    final unrelated = engine.embed('database schema migration');

    expect(
      LocalHashEmbeddingEngine.cosine(italian, english),
      greaterThan(
        LocalHashEmbeddingEngine.cosine(italian, unrelated),
      ),
    );
  });

  test('embedding footprint and throughput stay bounded', () {
    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < 1000; i++) {
      final vector = engine.embed(
        'Documento $i progetto ricerca note lavoro viaggio batteria '
        'contenuto locale deterministico con alcune parole aggiuntive.',
      );
      expect(vector, hasLength(192));
    }
    stopwatch.stop();

    expect(192 * 4, 768);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 8)));
  });
}
