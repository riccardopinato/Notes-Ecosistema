import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/project_workspace.dart';
import 'package:notes_ecosistema/src/domain/project_workload_guard.dart';

void main() {
  ProjectWorkItem item(
    String id, {
    String? date,
    String? time,
    int minutes = 30,
    String stage = 'TODO',
    bool archived = false,
    bool completed = false,
    List<String> tags = const [],
  }) =>
      ProjectWorkItem(
        note: Note(
          id: id,
          title: id,
          body: '',
          favorite: false,
          createdAt: 1,
          updatedAt: 1,
          pinned: false,
          archived: archived,
          tags: tags,
          taskJson: '{"priority":1}',
        ),
        kind: ProjectWorkItemKind.task,
        position: 0,
        stage: stage,
        completed: completed,
        priority: 1,
        due: null,
        plannedDate: date,
        plannedTime: time,
        plannedMinutes: minutes,
      );

  test('counts only explicitly scheduled minutes within one civil day', () {
    final result = ProjectWorkloadGuard.evaluate([
      item('a', date: '2026-11-04', time: '09:00', minutes: 120),
      item('b', date: '2026-11-04', time: '11:30', minutes: 120),
      item('c', date: '2026-11-04'),
      item('other-day', date: '2026-11-05', time: '14:00', minutes: 600),
      item('archived', date: '2026-11-04', time: '12:00', archived: true),
    ], civilDay: '2026-11-04', capacityMinutes: 180, wipLimit: 3);
    expect(result.scheduledMinutes, 240);
    expect(result.scheduledTasks, 2);
    expect(result.unknownDurationTasks, 1);
    expect(result.reasonCode, 'SCHEDULED_MINUTES_OVER_BUDGET');
  });

  test('explicit blocked tag and WIP source use lifecycle guards', () {
    final result = ProjectWorkloadGuard.evaluate([
      item('one', stage: 'DOING'),
      item('two', stage: 'DOING'),
      item('hidden', stage: 'DOING', archived: true),
      item('blocked', tags: ['blocked']),
    ], civilDay: '2026-11-04', capacityMinutes: 240, wipLimit: 1);
    expect(result.inProgressTasks, 2);
    expect(result.blockedTasks, 1);
    expect(result.reasonCode, 'WIP_LIMIT_EXCEEDED');
  });

  test('no missing durations are invented and policy is bounded', () {
    final result = ProjectWorkloadGuard.evaluate([
      item('not-timed', date: '2026-11-04'),
    ], civilDay: '2026-11-04', capacityMinutes: 240, wipLimit: 3);
    expect(result.scheduledMinutes, 0);
    expect(result.unknownDurationTasks, 1);
    expect(result.reasonCode, 'SCHEDULED_DURATION_UNKNOWN');
    expect(
        () => ProjectWorkloadGuard.evaluate(
              [],
              civilDay: 'invalid',
              capacityMinutes: 240,
              wipLimit: 3,
            ),
        throwsFormatException);
  });
}
