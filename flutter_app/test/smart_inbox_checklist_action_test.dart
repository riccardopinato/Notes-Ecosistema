import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/note_to_checklist.dart';
import 'package:notes_ecosistema/src/domain/smart_inbox_checklist_action.dart';

void main() {
  Note source({
    String body = '- [ ] Alpha\n- [ ] Beta\n- [x] Done',
    String id = 'source-1',
  }) => Note(
        id: id,
        title: 'Fonte',
        body: body,
        favorite: false,
        createdAt: 10,
        updatedAt: 20,
        pinned: false,
        archived: false,
        tags: const [],
      );

  test('selection is explicit, checked against the source and bounded', () {
    final note = source();
    expect(SmartInboxChecklistAction.selectedItems(note, ['Alpha', 'Beta']),
        ['Alpha', 'Beta']);
    for (final invalid in [
      <String>[],
      ['Done'],
      ['Invented'],
      ['Alpha', 'Alpha'],
    ]) {
      expect(() => SmartInboxChecklistAction.selectedItems(note, invalid),
          throwsFormatException);
    }
    expect(note.body, contains('- [x] Done'));
  });

  test('duplicate selection from same linked source is rejected', () {
    final a = source();
    final created = NoteToChecklist.buildTask(
      source: a,
      selected: ['Alpha', 'Beta'],
      taskId: 'task-1',
      nowMilliseconds: 1000,
    );
    expect(
        SmartInboxChecklistAction.alreadyCreated(
            [created], a.id, ['Beta', 'Alpha']),
        isTrue);
    expect(
        SmartInboxChecklistAction.alreadyCreated(
            [created], 'other-source', ['Beta', 'Alpha']),
        isFalse);
    expect(
        SmartInboxChecklistAction.alreadyCreated(
            [created], a.id, ['Alpha']),
        isFalse);
    expect(
        SmartInboxChecklistAction.alreadyCreated(
            [created.copyWith(deletedAt: 1001)], a.id, ['Alpha', 'Beta']),
        isFalse);
  });

  test('undo only applies to the untouched derived canonical task', () {
    final a = source();
    final task = NoteToChecklist.buildTask(
      source: a,
      selected: ['Alpha'],
      taskId: 'task-2',
      nowMilliseconds: 3000,
    );
    expect(SmartInboxChecklistAction.canUndo(task, task), isTrue);
    expect(SmartInboxChecklistAction.canUndo(
        task, task.copyWith(updatedAt: 3001)), isFalse);
    expect(SmartInboxChecklistAction.canUndo(
        task, task.copyWith(title: 'Modified')), isFalse);
    expect(SmartInboxChecklistAction.canUndo(
        task, task.copyWith(deletedAt: 4000)), isFalse);
    expect(SmartInboxChecklistAction.canUndo(
        task, task.copyWith(archived: true)), isFalse);
  });
}
