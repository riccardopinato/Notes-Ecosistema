import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/focus.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/planner.dart';

void main() {
  test('Focus clock survives encode decode and pause resume', () {
    final clock = FocusClock.start(
      sessionId: 's1',
      taskId: 'task',
      minutes: 25,
      now: 1000,
    );
    expect(clock.remaining(1000), 1500);

    final paused = clock.pause(61000);
    expect(paused.remaining(999999), 1440);

    final resumed = paused.resume(100000);
    expect(resumed.pausedMillis, isNull);
    expect(resumed.remaining(100000), 1440);

    final decoded = FocusClock.decode(resumed.encode());
    expect(decoded.taskId, 'task');
    expect(decoded.durationSeconds, 1500);
  });

  test('Focus next interval follows Pomodoro 4-block rule', () {
    var clock = FocusClock.start(
      sessionId: 's1',
      taskId: 'task',
      minutes: 25,
      now: 0,
      shortBreak: 5,
      longBreak: 15,
    );

    clock = clock.copyWith(deadline: 0).next(0, 'b1');
    expect(clock.phase, FocusPhase.breakTime);
    expect(clock.durationSeconds, 5 * 60);
    expect(clock.completedBlocks, 1);

    clock = clock.copyWith(deadline: 0).next(0, 'w2');
    expect(clock.phase, FocusPhase.work);

    clock = clock.copyWith(
      deadline: 0,
      phase: FocusPhase.work,
      completedBlocks: 3,
    ).next(0, 'b4');
    expect(clock.phase, FocusPhase.breakTime);
    expect(clock.durationSeconds, 15 * 60);
    expect(clock.completedBlocks, 4);
  });

  test('Kanban status changes preserve task validation', () {
    final task = TaskDetails.empty();
    final doing = changeTaskStatus(
      task,
      TaskStatus.doing,
      now: 100,
      today: DateTime(2026, 9, 23),
    );
    expect(doing.stage, 'DOING');
    expect(doing.completed, isFalse);

    final done = changeTaskStatus(
      doing,
      TaskStatus.done,
      now: 200,
      today: DateTime(2026, 9, 23),
    );
    expect(done.completed, isTrue);
  });

  test('Focus history is deduplicated and weekly totals aggregate', () {
    final details = TaskDetails.empty()
        .addFocusSession(
          sessionId: 'one',
          seconds: 120,
          endedAt: DateTime(2026, 9, 23, 10).millisecondsSinceEpoch,
        )
        .addFocusSession(
          sessionId: 'two',
          seconds: 180,
          endedAt: DateTime(2026, 9, 23, 11).millisecondsSinceEpoch,
        );

    final note = Note(
      id: 'task',
      title: 'Studio',
      body: '',
      favorite: false,
      createdAt: 1,
      updatedAt: 1,
      pinned: false,
      archived: false,
      tags: const [],
      taskJson: details.encode(),
    );

    final history = focusHistory([note]);
    expect(history, hasLength(2));

    final week = weeklyFocus([note], DateTime(2026, 9, 23));
    expect(week.last.value, 300);
  });
}
