import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/editing.dart';
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
      task('next', tags: ['dep_source']),
      task('source'),
      task('free'),
    ]);
    expect(result.length, 1);
    expect(result.single.sourceId, 'next');
    expect(result.single.reasonCode, 'EXPLICIT_OPEN_BLOCKER');
  });

  test('missing or archived target fails closed, not as a free task', () {
    final a = ProjectDependencyReview.inspect([
      task('next', tags: ['dep_hidden']),
    ]);
    final b = ProjectDependencyReview.inspect([
      task('next', tags: ['dep_hidden']),
      task('hidden', archived: true),
    ]);
    expect(a.single.reasonCode, 'DEPENDENCY_TARGET_UNAVAILABLE');
    expect(b.single.reasonCode, 'DEPENDENCY_TARGET_UNAVAILABLE');
  });

  test('completed explicit target no longer blocks the source', () {
    final output = ProjectDependencyReview.inspect([
      task('waiting', tags: ['dep_done']),
      task('done', completed: true),
    ]);
    expect(output, isEmpty);
  });

  test('editor tag normalization accepts canonical UUID dependency tokens', () {
    const id = 'f0fb51b0-c8b2-4c00-b49a-acb086450a72';
    final normalized = NoteTags.normalize(['dep_$id']);
    expect(normalized, ['dep_$id']);
    expect(normalized.single.length, 40);
  });

  test('cycles are detected, no data is mutated', () {
    final a = task('a', tags: ['dep_b']);
    final b = task('b', tags: ['dep_a']);
    final result = ProjectDependencyReview.inspect([a, b]);
    expect(result.map((issue) => issue.reasonCode),
        ['DEPENDENCY_CYCLE', 'DEPENDENCY_CYCLE']);
    expect(a.note.tags, ['dep_b']);
  });

  test('duplicate target identity and invalid policy are rejected', () {
    final result = ProjectDependencyReview.inspect([
      task('next', tags: ['dep_duplicate']),
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
