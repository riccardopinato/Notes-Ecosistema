import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/planner.dart';
import 'package:notes_ecosistema/src/domain/planner_insights.dart';

Note task(String id,
    {String? due,
    int priority = 0,
    int? completedAt,
    bool archived = false,
    int? deletedAt}) {
  final details = TaskDetails.empty().copyWith(
    due: due,
    priority: priority,
    completedAt: completedAt,
  );
  return Note(
    id: id,
    title: id,
    body: '',
    favorite: false,
    createdAt: 1000,
    updatedAt: 1000,
    pinned: false,
    archived: archived,
    deletedAt: deletedAt,
    tags: const [],
    taskJson: details.encode(),
  );
}

void main() {
  final today = DateTime(2026, 11, 3);
  test('Eisenhower uses explicit priority and due dates, never opaque scores',
      () {
    final notes = [
      task('do', due: '2026-11-04', priority: 3),
      task('plan', due: '2026-11-20', priority: 2),
      task('urgent', due: '2026-11-03', priority: 1),
      task('later', due: '2026-11-25', priority: 1),
      task('missing priority', due: '2026-11-04'),
      task('missing due', priority: 3),
    ];
    final groups = PlannerInsights.eisenhower(notes, today);
    expect(groups[EisenhowerGroup.urgentImportant]!.single.id, 'do');
    expect(groups[EisenhowerGroup.importantNotUrgent]!.single.id, 'plan');
    expect(groups[EisenhowerGroup.urgentNotImportant]!.single.id, 'urgent');
    expect(groups[EisenhowerGroup.notUrgentNotImportant]!.single.id, 'later');
    expect(groups[EisenhowerGroup.needsDetails]!.map((e) => e.id),
        containsAll(['missing priority', 'missing due']));
  });

  test('Weekly Review uses Monday week and actual completion timestamps', () {
    final monday = DateTime(2026, 11, 2);
    final notes = [
      task('completed',
          completedAt:
              monday.add(const Duration(hours: 9)).millisecondsSinceEpoch),
      task('before',
          completedAt:
              monday.subtract(const Duration(days: 1)).millisecondsSinceEpoch),
      task('due', due: '2026-11-04', priority: 3),
      task('overdue', due: '2026-10-31'),
      task('no deadline'),
      task('next week', due: '2026-11-09', priority: 1),
    ];
    final review = PlannerInsights.weeklyReview(notes, today);
    expect(review.weekStart, monday);
    expect(review.completedThisWeek.map((e) => e.id), ['completed']);
    expect(review.dueThisWeek.map((e) => e.id), ['due']);
    expect(review.overdueBeforeWeek.map((e) => e.id), ['overdue']);
    expect(review.missingDueDate.map((e) => e.id), ['no deadline']);
    expect(review.highPriorityOpen.map((e) => e.id), ['due']);
  });

  test('completed, deleted and archived tasks never appear in active matrix',
      () {
    final notes = [
      task('completed',
          due: '2026-11-04',
          priority: 3,
          completedAt: today.millisecondsSinceEpoch),
      task('deleted', due: '2026-11-04', priority: 3, deletedAt: 1234),
      task('archived', due: '2026-11-04', priority: 3, archived: true),
    ];
    final groups = PlannerInsights.eisenhower(notes, today);
    expect(groups.values.expand((list) => list), isEmpty);
    final review = PlannerInsights.weeklyReview(notes, today);
    expect(review.completedThisWeek.map((e) => e.id), ['completed']);
  });

  test('does not invent a due date or completion date from updatedAt', () {
    final open = task('missing', priority: 1);
    final result = PlannerInsights.weeklyReview([open], today);
    expect(result.completedThisWeek, isEmpty);
    expect(result.missingDueDate.single.id, 'missing');
    expect(
        PlannerInsights.eisenhower([open], today)[EisenhowerGroup.needsDetails]!
            .single
            .id,
        'missing');
  });

  test('invalid urgency bounds are rejected and outputs immutable', () {
    expect(
      () => PlannerInsights.eisenhower(const [], today, urgentWithinDays: -1),
      throwsFormatException,
    );
    final matrix = PlannerInsights.eisenhower(
        [task('urgent', due: '2026-11-03', priority: 3)], today);
    expect(
      () => matrix[EisenhowerGroup.urgentImportant]!.clear(),
      throwsUnsupportedError,
    );
  });
}
