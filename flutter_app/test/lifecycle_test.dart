import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/library.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/planner.dart';
import 'package:notes_ecosistema/src/platform/reminder_bridge.dart';

void main() {
  Note task({
    required String id,
    int? deletedAt,
    bool archived = false,
    bool completed = false,
    int? reminderAt,
  }) {
    var details = TaskDetails.empty().copyWith(reminderAt: reminderAt);
    if (completed) {
      details = details.copyWith(completedAt: 10);
    }
    return Note(
      id: id,
      title: 'Task $id',
      body: '',
      favorite: false,
      createdAt: 1,
      updatedAt: 2,
      deletedAt: deletedAt,
      pinned: false,
      archived: archived,
      tags: const [],
      taskJson: details.encode(),
    );
  }

  test('universal trash keeps deleted tasks reachable', () {
    final deletedTask = task(id: 'task-deleted', deletedAt: 3);
    final activeTask = task(id: 'task-active');

    expect(searchNotes([deletedTask, activeTask]), isEmpty);

    final trash = searchNotes(
      [deletedTask, activeTask],
      scope: NoteScope.trash,
    );
    expect(trash.map((note) => note.id), ['task-deleted']);
  });

  test('bulk restore preserves task metadata and prior archive state', () {
    final source = task(
      id: 'task-restore',
      deletedAt: 3,
      archived: true,
      reminderAt: 1000,
    );

    final restored = planBulkEdit(
      [source],
      const BulkChange(BulkAction.restore),
      50,
    ).single;

    expect(restored.deletedAt, isNull);
    expect(restored.archived, isTrue);
    expect(restored.taskJson, source.taskJson);
    expect(restored.updatedAt, 50);
  });

  test('reminder payload excludes lifecycle-inactive tasks', () {
    final active = task(id: 'active', reminderAt: 1000);
    final deleted = task(id: 'deleted', reminderAt: 1000, deletedAt: 3);
    final archived = task(id: 'archived', reminderAt: 1000, archived: true);
    final completed = task(id: 'completed', reminderAt: 1000, completed: true);
    final withoutReminder = task(id: 'none');

    final payload = reminderPayload([
      active,
      deleted,
      archived,
      completed,
      withoutReminder,
    ]);

    expect(payload, hasLength(1));
    expect(payload.single['id'], 'active');
    expect(payload.single['at'], 1000);
  });
}
