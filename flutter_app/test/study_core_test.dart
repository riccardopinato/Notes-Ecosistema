import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/study.dart';

void main() {
  LearningItem item(String id, {int createdAt = 0}) => LearningItem(
        id: id,
        sourceNoteId: 'note-$id',
        prompt: 'Prompt $id',
        answer: 'Answer $id',
        sourceSnapshot: 'Historical source',
        sourceUpdatedAt: 1,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

  test('ReviewState is derived from canonical ReviewLog history', () {
    const scheduler = SimpleStudyScheduler();
    final source = item('1', createdAt: 100);
    final first = scheduler.stateFor(source, const [], now: 1000);
    expect(first.reviewCount, 0);
    expect(first.dueAt, 100);

    const log = ReviewLog(
      id: 'r1',
      itemId: '1',
      reviewedAt: 2000,
      rating: StudyRating.good,
      intervalDays: 3,
    );
    final next = scheduler.stateFor(source, const [log], now: 3000);
    expect(next.reviewCount, 1);
    expect(next.intervalDays, 3);
    expect(next.dueAt, 2000 + 3 * SimpleStudyScheduler.dayMillis);
  });

  test('simple scheduler is deterministic and bounded', () {
    const scheduler = SimpleStudyScheduler();
    const state = ReviewState(
      itemId: 'x',
      dueAt: 0,
      intervalDays: 10,
      reviewCount: 5,
    );
    expect(scheduler.nextIntervalDays(state, StudyRating.again), 1);
    expect(scheduler.nextIntervalDays(state, StudyRating.hard), 15);
    expect(scheduler.nextIntervalDays(state, StudyRating.good), 22);
    expect(scheduler.nextIntervalDays(state, StudyRating.easy), 30);
  });

  test('queue caps daily review debt at 30 by default', () {
    final items = [
      for (var i = 0; i < 60; i++) item('$i', createdAt: i),
    ];
    final due = StudyQueue.due(
      items: items,
      logs: const [],
      now: 1000,
    );
    expect(due.length, StudyQueue.defaultDailyLimit);
    expect(due.first.id, '0');
  });

  test('historical studied evidence does not depend on live source body', () {
    final source = item('history');
    expect(source.sourceSnapshot, 'Historical source');
    StudyRules.validateItem(source);
  });
}
