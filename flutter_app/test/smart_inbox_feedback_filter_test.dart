import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/contextual_work_insights.dart';
import 'package:notes_ecosistema/src/domain/note.dart';

void main() {
  Note source(String id, int updatedAt) => Note(
        id: id,
        title: id,
        body: '- [ ] Explicit task',
        favorite: false,
        createdAt: 1,
        updatedAt: updatedAt,
        pinned: false,
        archived: false,
        tags: const [],
      );

  test('ignored and muted feedback is excluded before the display limit', () {
    final notes = List.generate(30, (i) => source('recent-$i', 300 - i));
    notes.add(source('older-allowed', 1));
    final suggestions = SmartInboxReview.suggest(
      notes,
      limit: 3,
      include: (item) => item.note.id == 'older-allowed',
    );
    expect(suggestions.map((item) => item.note.id), ['older-allowed']);
    expect(suggestions.single.reasonCode, 'EXPLICIT_UNCHECKED_LIST');
  });

  test('an excluded candidate never consumes the per-screen quota', () {
    final suggestions = SmartInboxReview.suggest(
      [source('a', 3), source('b', 2), source('c', 1)],
      limit: 2,
      include: (item) => item.note.id != 'a',
    );
    expect(suggestions.map((item) => item.note.id), ['b', 'c']);
  });
}
