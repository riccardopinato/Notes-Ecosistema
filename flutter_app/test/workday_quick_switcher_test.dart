import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/planner.dart';
import 'package:notes_ecosistema/src/domain/quick_switcher.dart';
import 'package:notes_ecosistema/src/domain/workday.dart';

void main() {
  Note task(
    String id, {
    String? due,
    String? plannedDate,
    String? plannedTime,
    int priority = 0,
  }) {
    final details = TaskDetails.empty().copyWith(
      due: due,
      plannedDate: plannedDate,
      plannedTime: plannedTime,
      priority: priority,
    );
    return Note(
      id: id,
      title: 'Task $id',
      body: '',
      favorite: false,
      createdAt: 1,
      updatedAt: 2,
      pinned: false,
      archived: false,
      tags: const [],
      taskJson: details.encode(),
    );
  }

  test('daily briefing aggregates without creating a new entity', () {
    final now = DateTime(2026, 9, 26, 10);
    final notes = [
      task(
        'meeting',
        due: '2026-09-26',
        plannedDate: '2026-09-26',
        plannedTime: '09:00',
      ),
      task('late', due: '2026-09-25'),
      task(
        'review',
        plannedDate: '2026-09-26',
        plannedTime: '14:30',
        priority: 3,
      ),
      const Note(
        id: 'inbox',
        title: 'Idea',
        body: 'x',
        favorite: false,
        createdAt: 1,
        updatedAt: 20,
        pinned: false,
        archived: false,
        tags: [],
      ),
    ];

    final briefing = Workday.build(
      notes: notes,
      now: now,
      sharedUnread: 2,
    );

    expect(briefing.items.map((item) => item.time), ['09:00', '14:30']);
    expect(briefing.dueToday, 1);
    expect(briefing.overdue, 1);
    expect(briefing.inbox.single.id, 'inbox');
    expect(briefing.sharedUnread, 2);
  });

  test('quick switcher ranks exact and prefix matches', () {
    final notes = [
      const Note(
        id: 'alpha',
        title: 'Progetto Alpha',
        body: '',
        favorite: false,
        createdAt: 1,
        updatedAt: 1,
        pinned: false,
        archived: false,
        tags: [],
      ),
    ];
    final results = QuickSwitcher.search(
      query: 'progetto a',
      notes: notes,
      collections: const [],
    );
    expect(results.first.id, 'alpha');
  });
}
