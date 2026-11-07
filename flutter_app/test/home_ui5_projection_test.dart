import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/home_ui5_projection.dart';
import 'package:notes_ecosistema/src/domain/note.dart';

void main() {
  Note page(String id, int updatedAt) => Note(
        id: id,
        title: id,
        body: 'Text',
        favorite: false,
        createdAt: 1,
        updatedAt: updatedAt,
        pinned: false,
        archived: false,
        tags: const [],
      );

  test('projects only authorized active pages, stable newest-first tie', () {
    final source = [
      page('z', 10),
      page('a', 10),
      page('newest', 20),
      page('old', 1),
      page('trashed', 100).copyWith(deletedAt: 100),
      page('archived', 200).copyWith(archived: true),
      page('task', 300).copyWith(taskJson: '{"completedAt":null}'),
      page('done', 400).copyWith(taskJson: '{"completedAt":20}'),
    ];
    final result = HomeUi5Projection.fromNotes(source);
    expect(result.pageCount, 4);
    expect(result.pendingTasks, 1);
    expect(
      result.recentPages.map((item) => item.id).toList(),
      ['newest', 'a', 'z'],
    );
    expect(() => result.recentPages.add(page('x', 5)), throwsUnsupportedError);
  });

  test('0 limit has no recent pages; invalid limits fail closed', () {
    final result = HomeUi5Projection.fromNotes([page('a', 1)], recentLimit: 0);
    expect(result.pageCount, 1);
    expect(result.recentPages, isEmpty);
    expect(
      () => HomeUi5Projection.fromNotes([page('a', 1)], recentLimit: 11),
      throwsFormatException,
    );
  });

  test('bounded output with 5000 notes and no content duplication', () {
    final notes = List.generate(
      5000,
      (index) => page('id-$index', index),
      growable: false,
    );
    final result = HomeUi5Projection.fromNotes(notes);
    expect(result.pageCount, 5000);
    expect(result.recentPages.length, 3);
    expect(result.recentPages.first, same(notes.last));
    expect(result.recentPages.last, same(notes[4997]));
  });
}
