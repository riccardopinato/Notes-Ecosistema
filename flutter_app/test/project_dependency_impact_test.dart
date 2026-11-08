import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/project_dependency_impact.dart';
import 'package:notes_ecosistema/src/domain/project_workspace.dart';

void main() {
  ProjectWorkItem task(String id,
      {List<String> tags = const [],
      bool completed = false,
      bool archived = false}) {
    return ProjectWorkItem(
      note: Note(
        id: id,
        title: 'Task $id',
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
  }

  test('counts only direct authorized unresolved prerequisites', () {
    final rows = [
      task('base'),
      task('second'),
      task('a', tags: ['dep_base', 'dep_second', 'dep_base']),
      task('b', tags: ['dep_base']),
      task('c', tags: ['dep_second']),
      task('done-source', tags: ['dep_base'], completed: true),
      task('hidden-source', tags: ['dep_base'], archived: true),
    ];
    final result = ProjectDependencyImpactReview.inspect(rows);
    expect(result.map((item) => item.taskId), ['base', 'second']);
    expect(result.map((item) => item.directDependents), [2, 2]);
    expect(result.first.visibleDependentTitles, ['Task a', 'Task b']);
  });

  test('completed or unavailable targets are never presented', () {
    final result = ProjectDependencyImpactReview.inspect([
      task('done', completed: true),
      task('hidden', archived: true),
      task('x', tags: ['dep_done', 'dep_hidden', 'dep_secret']),
      task('dup'),
      task('dup'),
      task('y', tags: ['dep_dup']),
    ]);
    expect(result, isEmpty);
  });

  test('no data mutation; stable top5 within project 5000 task bound', () {
    final source = [
      task('priority'),
      for (var i = 0; i < 4999; i++)
        task('t$i', tags: i < 10 ? ['dep_priority'] : const []),
    ];
    final result = ProjectDependencyImpactReview.inspect(source);
    expect(result.single.taskId, 'priority');
    expect(result.single.directDependents, 10);
    expect(result.single.visibleDependentTitles.length, 3);
    expect(source.first.note.tags, isEmpty);
    expect(() => ProjectDependencyImpactReview.inspect(source, limit: 21),
        throwsFormatException);
    expect(ProjectDependencyImpactReview.inspect(source, limit: 0), isEmpty);
    expect(ProjectDependencyImpactReview.inspect([...source, task('extra')]),
        isEmpty);
  });
}
