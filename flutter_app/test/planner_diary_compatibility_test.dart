import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/diary.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/planner.dart';

void main() {
  test('Planner keeps Kotlin task JSON fields while adding planning', () {
    final legacy = jsonEncode({
      'due': '2026-09-30',
      'priority': 2,
      'repeat': 'NONE',
      'completedAt': null,
      'linkedNoteId': 'note-2',
      'stage': 'TODO',
      'focusSeconds': 120,
      'focusReceipts': ['session-1'],
      'focusHistory': [
        {'id': 'session-1', 'seconds': 120, 'endedAt': 1000}
      ],
      'completedCycles': 0,
      'reminderAt': null,
      'reminderZone': null,
      'reminderTime': null,
      'futureField': {'keep': true},
    });

    final task = TaskDetails.decode(legacy);
    expect(task.plannedMinutes, 30);

    final planned = task.schedule(
      date: DateTime(2026, 9, 25),
      time: '09:30',
      minutes: 45,
    );
    final encoded = jsonDecode(planned.encode()) as Map<String, dynamic>;

    expect(encoded['plannedDate'], '2026-09-25');
    expect(encoded['plannedTime'], '09:30');
    expect(encoded['plannedMinutes'], 45);
    expect(encoded['futureField'], {'keep': true});
    expect(encoded['focusReceipts'], ['session-1']);
  });

  test('Diary uses the same diario_YYYY-MM-DD tag contract', () {
    final tags = Diary.datedTags(
      const ['viaggio', 'diario_2026-09-01'],
      DateTime(2026, 9, 23),
    );

    expect(tags, contains('viaggio'));
    expect(tags, contains('diario_2026-09-23'));
    expect(tags, isNot(contains('diario_2026-09-01')));
    expect(Diary.date(tags), DateTime(2026, 9, 23));
    expect(Diary.userTags(tags), ['viaggio']);
  });

  test('Planner index separates planned and unplanned tasks', () {
    final planned = _note(
      id: 'p',
      task: TaskDetails.empty()
          .withEditorValues(
            due: '2026-09-30',
            priority: 3,
            repeat: 'NONE',
            linkedNoteId: null,
            plannedDate: '2026-09-23',
            plannedTime: '10:00',
            plannedMinutes: 60,
          )
          .encode(),
    );
    final unplanned = _note(
      id: 'u',
      task: TaskDetails.empty().encode(),
    );

    final index = PlannerPro.index([planned, unplanned]);

    expect(index.planned['2026-09-23']?.single.id, 'p');
    expect(index.unplanned.single.id, 'u');
    expect(PlannerPro.timeBlocks(index, DateTime(2026, 9, 23)).single.minutes, 60);
  });

  test('Planner detects overlapping time blocks', () {
    final first = _note(
      id: 'a',
      task: TaskDetails.empty()
          .schedule(date: DateTime(2026, 9, 23), time: '09:00', minutes: 60)
          .encode(),
    );
    final second = _note(
      id: 'b',
      task: TaskDetails.empty()
          .schedule(date: DateTime(2026, 9, 23), time: '09:30', minutes: 30)
          .encode(),
    );

    final blocks = PlannerPro.timeBlocks(
      PlannerPro.index([first, second]),
      DateTime(2026, 9, 23),
    );

    expect(PlannerPro.collisions(blocks), hasLength(1));
  });

  test('Recurring completion advances due date and frees time block', () {
    final task = TaskDetails.empty()
        .withEditorValues(
          due: '2026-09-23',
          priority: 0,
          repeat: 'DAILY',
          linkedNoteId: null,
          plannedDate: '2026-09-23',
          plannedTime: '08:00',
          plannedMinutes: 30,
        )
        .toggleCompleted(
          completed: true,
          today: DateTime(2026, 9, 23),
          nowMillis: 1234,
        );

    expect(task.due, '2026-09-24');
    expect(task.completed, isFalse);
    expect(task.completedCycles, 1);
    expect(task.plannedDate, isNull);
    expect(task.plannedTime, isNull);
    expect(task.plannedMinutes, 30);
  });
}

Note _note({required String id, required String task}) => Note(
      id: id,
      title: id,
      body: '',
      favorite: false,
      createdAt: 1,
      updatedAt: 1,
      pinned: false,
      archived: false,
      tags: const [],
      taskJson: task,
    );
