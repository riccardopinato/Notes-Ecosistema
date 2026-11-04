import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/note_duplicate_review.dart';

void main() {
  Note make(
    String id, String title, String body, {
    bool archived = false,
    int? deletedAt,
    String? taskJson,
    String? sketchJson,
    int updatedAt = 123,
  }) =>
      Note(
        id: id, title: title, body: body,
        favorite: false, createdAt: 1, updatedAt: updatedAt,
        pinned: false, archived: archived, deletedAt: deletedAt,
        tags: const [], taskJson: taskJson, sketchJson: sketchJson,
      );

  test('identical local note content is suggested, deterministic by ID', () {
    final notes = [
      make('b', 'Riunione di studio', 'progetto biblioteca esami gruppo'),
      make('a', 'Riunione di studio', 'progetto biblioteca esami gruppo'),
      make('unrelated', 'Lista spesa', 'pomodori latte pane acqua'),
    ];
    final found = NoteDuplicateReview.review(notes);
    expect(found, hasLength(1));
    expect(found.single.first.id, 'a');
    expect(found.single.second.id, 'b');
    expect(found.single.jaccard, 1);
    final reversed = NoteDuplicateReview.review(notes.reversed.toList());
    expect(reversed.map((p) => '${p.first.id}:${p.second.id}'),
        found.map((p) => '${p.first.id}:${p.second.id}'));
  });

  test('deleted, archived, task and visual content never become suggestions', () {
    final example = make('public', 'Riunione di studio',
        'progetto biblioteca esami gruppo');
    final result = NoteDuplicateReview.review([
      example,
      make('archived', example.title, example.body, archived: true),
      make('deleted', example.title, example.body, deletedAt: 9),
      make('task', example.title, example.body, taskJson: '{"done":false}'),
      make('visual', example.title, example.body, sketchJson: '{"x":1}'),
    ]);
    expect(result, isEmpty);
  });

  test('cannot use stale or withdrawn source to open canonical editor', () {
    final original = make('n1', 'Fotografia', 'notte bosco lente paesaggio');
    expect(NoteDuplicateReview.revalidate(original, [original]), isNotNull);
    expect(NoteDuplicateReview.revalidate(original, []), isNull);
    expect(NoteDuplicateReview.revalidate(original,
        [original.copyWith(updatedAt: 124)]), isNull);
    expect(NoteDuplicateReview.revalidate(original,
        [original.copyWith(body: 'modificato')]), isNull);
    expect(NoteDuplicateReview.revalidate(original,
        [original.copyWith(archived: true)]), isNull);
    expect(NoteDuplicateReview.revalidate(original,
        [original, original]), isNull);
  });

  test('bounded corpus, duplicate IDs and tiny text fail closed', () {
    final large = [
      for (var i = 0; i < 301; i++)
        make('note$i', 'Viaggio camper', 'paesaggio montagna strada'),
    ];
    expect(NoteDuplicateReview.review(large), isEmpty);
    final one = make('dup', 'Montagna viaggi', 'camper bosco lago');
    expect(NoteDuplicateReview.review([one, one]), isEmpty);
    expect(NoteDuplicateReview.review([
      make('a', 'A', ''),
      make('b', 'A', ''),
    ]), isEmpty);
  });

  test('background compute is safe and source remains unmodified', () async {
    final a = make('a', 'Caffè e viaggi', 'montagna camper sentiero natura');
    final b = make('b', 'Caffè e viaggi', 'montagna camper sentiero natura');
    final found = await compute(NoteDuplicateReview.review, [a, b]);
    expect(found.length, 1);
    expect(a.body, 'montagna camper sentiero natura');
    expect(a.isDeleted, false);
  });

  test('medium corpus completes with no more than thirty read-only pairs',
      () {
    final corpus = [
      for (var i = 0; i < 300; i++)
        make('n$i', 'Titolo simile',
            'stesso corpo note studio lavoro progetto prova'),
    ];
    final pairs = NoteDuplicateReview.review(corpus);
    expect(pairs.length, 30);
    expect(pairs.every((p) => p.jaccard == 1), true);
  });
}
