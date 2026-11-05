import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/project_task_readiness.dart';
import 'package:notes_ecosistema/src/domain/project_workspace.dart';

void main() {
  ProjectWorkItem task(
    String id, {
    List<String> tags = const [],
    String stage = 'TODO',
    bool completed = false,
    bool archived = false,
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
        stage: stage,
        completed: completed,
        priority: 0,
        due: null,
        plannedDate: null,
        plannedTime: null,
        plannedMinutes: 30,
      );

  test('derive operational status from canonical project tasks', () {
    final items = [
      task('ready'),
      task('doing', stage: 'DOING'),
      task('waiting', tags: ['dep_doing']),
      task('finished', completed: true),
    ];
    final result = ProjectTaskReadiness.inspect(items);
    expect(result.map((x) => x.status), [
      ProjectTaskReadinessStatus.ready,
      ProjectTaskReadinessStatus.doing,
      ProjectTaskReadinessStatus.blocked,
      ProjectTaskReadinessStatus.done,
    ]);
    expect(result[2].reasonCode, 'DEPENDENCY_OPEN');
    expect(
        result.map((x) => x.taskId), ['ready', 'doing', 'waiting', 'finished']);
    expect(items[2].note.tags, ['dep_doing']);
  });

  test('cycle, unavailable target and explicit block fail closed', () {
    final result = ProjectTaskReadiness.inspect([
      task('a', tags: ['dep_b']),
      task('b', tags: ['dep_a']),
      task('missing', tags: ['dep_secret']),
      task('manual', tags: ['blocked']),
    ]);
    expect(result.map((x) => x.reasonCode), [
      'DEPENDENCY_CYCLE',
      'DEPENDENCY_CYCLE',
      'DEPENDENCY_UNAVAILABLE',
      'EXPLICIT_BLOCKED',
    ]);
  });

  test('completed target no longer blocks a source', () {
    final result = ProjectTaskReadiness.inspect([
      task('next', tags: ['dep_done']),
      task('done', completed: true),
    ]);
    expect(result.first.status, ProjectTaskReadinessStatus.ready);
    expect(result.last.status, ProjectTaskReadinessStatus.done);
  });

  test('archived references stay hidden and duplicate IDs remain blocked', () {
    final result = ProjectTaskReadiness.inspect([
      task('next', tags: ['dep_hidden']),
      task('hidden', archived: true),
      task('dup'),
      task('dup'),
    ]);
    expect(result.first.reasonCode, 'DEPENDENCY_UNAVAILABLE');
    expect(result.map((x) => x.reasonCode).skip(1),
        ['DEPENDENCY_UNAVAILABLE', 'DEPENDENCY_UNAVAILABLE']);
  });

  test('inconsistent DONE stage is never treated as completed', () {
    final result = ProjectTaskReadiness.inspect([task('wrong', stage: 'DONE')]);
    expect(result.single.status, ProjectTaskReadinessStatus.ready);
    expect(result.single.reasonCode, 'TASK_STAGE_INCONSISTENT');
  });

  test('5000 scoped tasks stay bounded and original notes are immutable', () {
    final items = [
      for (var i = 0; i < 5000; i++) task('t$i'),
    ];
    final result = ProjectTaskReadiness.inspect(items, limit: 8);
    expect(result.length, 8);
    expect(result.every((x) => x.status == ProjectTaskReadinessStatus.ready),
        isTrue);
    expect(items.first.note.tags, isEmpty);
    expect(() => ProjectTaskReadiness.inspect(items, limit: 21),
        throwsFormatException);
    expect(ProjectTaskReadiness.inspect(items, limit: 0), isEmpty);
  });
}
