import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/contextual_work_insights.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/planner.dart';
import 'package:notes_ecosistema/src/domain/project_workspace.dart';

void main() {
  Note note(String id, String body, {List<String> tags = const []}) => Note(
        id: id,
        title: 'Note $id',
        body: body,
        favorite: false,
        createdAt: 1,
        updatedAt: 2,
        pinned: false,
        archived: false,
        tags: tags,
      );

  ProjectWorkItem work(Note note) => ProjectWorkItem(
        note: note,
        kind: note.isTask ? ProjectWorkItemKind.task : ProjectWorkItemKind.note,
        position: 0,
        stage: note.isTask ? 'TODO' : 'REFERENCE',
        completed: false,
        priority: 0,
        due: null,
        plannedDate: null,
        plannedTime: null,
        plannedMinutes: 30,
      );

  test('project with only notes suggests a next action, not an auto task', () {
    final insights = NextActionInsights.forProject([
      work(note('n1', 'Research source')),
    ]);
    expect(insights.single.kind, NextActionKind.missingNextAction);
    expect(insights.single.sourceId, isNull);
    expect(NextActionInsights.forProject([]), isEmpty);
  });

  test('existing active task prevents fabricated missing-action alert', () {
    final n = Note(
      id: 'task',
      title: 'Existing task',
      body: '',
      favorite: false,
      createdAt: 1,
      updatedAt: 2,
      pinned: false,
      archived: false,
      tags: const [],
      taskJson: TaskDetails.empty().encode(),
    );
    expect(NextActionInsights.forProject([work(n)]), isEmpty);
  });

  test('review is limited to explicit content and excludes archived', () {
    final source = note('a', '- [ ] Buy notebook');
    final tags = note('b', 'Idea #studio');
    final result = SmartInboxReview.suggest([
      source,
      tags,
      note('c', 'Freeform journal'),
    ]);
    expect(result.map((s) => s.reasonCode), [
      'EXPLICIT_UNCHECKED_LIST',
      'EXPLICIT_HASHTAGS_NOT_APPLIED',
    ]);
    expect(
      SmartInboxReview.suggest([
        source.copyWith(archived: true),
      ]),
      isEmpty,
    );
    expect(
        () => SmartInboxReview.suggest([], limit: -1), throwsFormatException);
  });
}
