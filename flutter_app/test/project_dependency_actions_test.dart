import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/project_dependency_actions.dart';
import 'package:notes_ecosistema/src/domain/project_workspace.dart';

void main() {
  ProjectWorkItem task(String id,
      {List<String> tags = const [],
      bool completed = false,
      bool archived = false}) {
    final note = Note(
      id: id,
      title: id,
      body: '',
      favorite: false,
      createdAt: 10,
      updatedAt: 20,
      pinned: false,
      archived: archived,
      tags: tags,
      taskJson: '{"stage":"TODO"}',
    );
    return ProjectWorkItem(
      note: note,
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
  }

  test('writes canonical dep tags without moving tasks or mutating input', () {
    final items = [
      task('a', tags: ['work']),
      task('b'),
      task('c', completed: true),
    ];
    final next = ProjectDependencyActions.update(
      source: items.first.note,
      scopedItems: items,
      selectedTargetIds: ['b'],
      nowMilliseconds: 21,
    );
    expect(next.tags, ['dep_b', 'work']);
    expect(next.taskJson, items.first.note.taskJson);
    expect(items.first.note.tags, ['work']);
    expect(
        ProjectDependencyActions.existingVisibleTargets(
            next,
            ProjectDependencyActions.eligibleTargets(next, [
              ProjectWorkItem.from(
                  next,
                  ProjectItemLink(
                      projectId: 'p',
                      noteId: next.id,
                      position: 0,
                      addedAt: 1,
                      updatedAt: 1)),
              items[1],
              items[2],
            ])),
        ['b']);
  });

  test('rejects cross-project or completed target and cycle', () {
    final a = task('a');
    final b = task('b', tags: ['dep_a']);
    for (final target in ['a', 'hidden']) {
      expect(
          () => ProjectDependencyActions.update(
                source: a.note,
                scopedItems: [a, b],
                selectedTargetIds: [target],
                nowMilliseconds: 21,
              ),
          throwsFormatException);
    }
    expect(
        () => ProjectDependencyActions.update(
              source: a.note,
              scopedItems: [a, b],
              selectedTargetIds: ['b'],
              nowMilliseconds: 21,
            ),
        throwsFormatException);
    expect(
        () => ProjectDependencyActions.update(
              source: a.note,
              scopedItems: [a, task('done', completed: true)],
              selectedTargetIds: ['done'],
              nowMilliseconds: 21,
            ),
        throwsFormatException);
  });

  test('keeps unavailable historical dependency when changing visible links',
      () {
    final a = task('a', tags: ['dep_hidden', 'work']);
    final b = task('b');
    final output = ProjectDependencyActions.update(
      source: a.note,
      scopedItems: [a, b],
      selectedTargetIds: ['b'],
      nowMilliseconds: 21,
    );
    expect(output.tags, ['dep_b', 'dep_hidden', 'work']);
  });

  test('rejects stale source and duplicate identity, allows explicit clear',
      () {
    final a = task('a', tags: ['dep_b']);
    final b = task('b');
    final cleared = ProjectDependencyActions.update(
      source: a.note,
      scopedItems: [a, b],
      selectedTargetIds: const [],
      nowMilliseconds: 21,
    );
    expect(cleared.tags, isEmpty);
    expect(
        () => ProjectDependencyActions.update(
              source: a.note,
              scopedItems: [a.note.copyWith(updatedAt: 22)].map((note) =>
                  ProjectWorkItem.from(
                      note,
                      ProjectItemLink(
                          projectId: 'p',
                          noteId: note.id,
                          position: 0,
                          addedAt: 1,
                          updatedAt: 1))),
              selectedTargetIds: ['b'],
              nowMilliseconds: 21,
            ),
        throwsFormatException);
    expect(
        () => ProjectDependencyActions.update(
              source: a.note,
              scopedItems: [a, a, b],
              selectedTargetIds: ['b'],
              nowMilliseconds: 21,
            ),
        throwsFormatException);
  });
}
