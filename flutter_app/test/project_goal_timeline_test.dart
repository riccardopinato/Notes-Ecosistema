import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/project_workspace.dart';
import 'package:notes_ecosistema/src/domain/project_goal_timeline.dart';

void main() {
  ProjectWorkItem task(String id,
          {List<String> tags = const [], bool completed = false}) =>
      ProjectWorkItem(
        note: Note(
            id: id,
            title: id,
            body: '',
            favorite: false,
            createdAt: 1,
            updatedAt: 2,
            pinned: false,
            archived: false,
            tags: tags,
            taskJson: '{"stage":"TODO"}'),
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

  test('reverse topological order respects explicit prerequisites', () {
    final plan = ProjectGoalTimeline.backplan(
      [
        task('finish', tags: ['dep_prepare']),
        task('prepare')
      ],
      deadline: '2026-11-06',
      minutesPerTask: 120,
      minutesPerDay: 120,
    );
    expect(plan.map((x) => x.taskId), ['prepare', 'finish']);
    expect(plan.map((x) => x.date), ['2026-11-05', '2026-11-06']);
  });

  test('weekend deadline is moved to previous working day', () {
    final plan = ProjectGoalTimeline.backplan(
      [task('a'), task('b')],
      deadline: '2026-11-08',
      minutesPerTask: 30,
      minutesPerDay: 60,
    );
    expect(plan.map((x) => x.date), ['2026-11-06', '2026-11-06']);
  });

  test('missing target and cycles fail closed, completed target ignored', () {
    expect(
        () => ProjectGoalTimeline.backplan(
              [
                task('a', tags: ['dep_hidden'])
              ],
              deadline: '2026-11-06',
              minutesPerTask: 30,
              minutesPerDay: 60,
            ),
        throwsFormatException);
    expect(
        () => ProjectGoalTimeline.backplan(
              [
                task('a', tags: ['dep_b']),
                task('b', tags: ['dep_a'])
              ],
              deadline: '2026-11-06',
              minutesPerTask: 30,
              minutesPerDay: 60,
            ),
        throwsFormatException);
    final plan = ProjectGoalTimeline.backplan(
      [
        task('a', tags: ['dep_done']),
        task('done', completed: true)
      ],
      deadline: '2026-11-06',
      minutesPerTask: 30,
      minutesPerDay: 60,
    );
    expect(plan.single.taskId, 'a');
  });

  test('invalid dates, unprovided estimates and oversized sources rejected',
      () {
    for (final day in ['2026-02-30', '10/11/2026']) {
      expect(
          () => ProjectGoalTimeline.backplan([task('a')],
              deadline: day, minutesPerTask: 30, minutesPerDay: 60),
          throwsFormatException);
    }
    expect(
        () => ProjectGoalTimeline.backplan([task('a')],
            deadline: '2026-11-06', minutesPerTask: 0, minutesPerDay: 60),
        throwsFormatException);
    expect(
        () => ProjectGoalTimeline.backplan(
            [for (var i = 0; i < 501; i++) task('t$i')],
            deadline: '2026-11-06', minutesPerTask: 30, minutesPerDay: 60),
        throwsFormatException);
  });
}
