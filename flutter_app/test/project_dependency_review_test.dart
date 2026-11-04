import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/project_dependency_review.dart';
import 'package:notes_ecosistema/src/domain/project_workspace.dart';

void main() {
  ProjectWorkItem task(
    String id, {
    List<String> tags = const [],
    bool archived = false,
    bool completed = false,
  }) =>
      ProjectWorkItem(
        note: Note(
          id: id,
          title: id,
          body: '',
          favorite: false,
          createdAt: 1,
          updatedAt: 2,
          pinned: false,
          archived: archived,
          tags: tags,
          taskJson: '{"stage":"TODO"}',
        ),
        kind: ProjectWorkItemKind.task,
        position: 0,
        stage: 'TODO',
        completed: completed,
        priority: 0,
        due: null,
        plannedDate: null,
        plannedTime: null,
        plannedMinutes: 30,
      );

  test('only explicit same-project blocker links are considered', () {
    final result = ProjectDependencyReview.inspect([
      task('next', tags: ['blocked-by:source']),
      task('source'),
      task('free'),
    ]);
    expect(result.length, 1);
    expect(result.single.sourceId, 'next');
    expect(result.single.reasonCode, 'EXPLICIT_OPEN_BLOCKER');
  });

  test('missing or archived target fails closed, not as a free task', () {
    final a = ProjectDependencyReview.inspect([
      task('next', tags: ['blocked-by:hidden']),
    ]);
    final b = ProjectDependencyReview.inspect([
      task('next', tags: ['blocked-by:hidden']),
      task('hidden', archived: true),
    ]);
    expect(a.single.reasonCode, 'DEPENDENCY_TARGET_UNAVAILABLE');
    expect(b.single.reasonCode, 'DEPENDENCY_TARGET_UNAVAILABLE');
  });

  test('completed explicit target no longer blocks the source', () {
    final output = ProjectDependencyReview.inspect([
      task('waiting', tags: ['blocked-by:done']),
      task('done', completed: true),
    ]);
    expect(output, isEmpty);
  });

  test('cycles are detected, no data is mutated', () {
    final a = task('a', tags: ['blocked-by:b']);
    final b = task('b', tags: ['blocked-by:a']);
    final result = ProjectDependencyReview.inspect([a, b]);
    expect(result.map((issue) => issue.reasonCode),
        ['DEPENDENCY_CYCLE', 'DEPENDENCY_CYCLE']);
    expect(a.note.tags, ['blocked-by:b']);
  });

  test('duplicate target identity and invalid policy are rejected', () {
    final result = ProjectDependencyReview.inspect([
      task('next', tags: ['blocked-by:duplicate']),
      task('duplicate'),
      task('duplicate'),
    ]);
    expect(result.single.reasonCode, 'DEPENDENCY_TARGET_UNAVAILABLE');
    expect(
      () => ProjectDependencyReview.inspect([], limit: -1),
      throwsFormatException,
    );
  });
}
