import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/note_to_checklist.dart';
import 'package:notes_ecosistema/src/domain/planner.dart';

Note note({
  String id = 'source-1',
  String title = 'Appunti',
  String body = '- [ ] Telefonare\n- Preparare slides\n1. Spedire email',
  String? taskJson,
  int? deletedAt,
  String? sketchJson,
}) =>
    Note(
      id: id,
      title: title,
      body: body,
      favorite: false,
      createdAt: 1000,
      updatedAt: 1000,
      pinned: false,
      archived: false,
      tags: const ['private-note'],
      taskJson: taskJson,
      deletedAt: deletedAt,
      sketchJson: sketchJson,
    );

void main() {
  test('extracts only explicit list items, no implicit prose tasks', () {
    final input = note(body: '''
Riunione; ricordarsi di chiamare.
- [ ] Telefonare
- Preparare slides
1. Spedire email
#urgente
- [x] Completato
''');
    expect(NoteToChecklist.candidates(input),
        ['Telefonare', 'Preparare slides', 'Spedire email']);
  });

  test('deduplicates case-insensitively and limits bounded preview', () {
    final input = note(
        body: [
      '- [ ] Invia report',
      '- [ ] invia report',
      for (var i = 0; i < 50; i++) '- [ ] Attività $i',
    ].join('\n'));
    final items = NoteToChecklist.candidates(input);
    expect(items.length, NoteToChecklist.maxItems);
    expect(items.first, 'Invia report');
    expect(items[1], 'Attività 0');
    expect(() => items.add('non permesso'), throwsUnsupportedError);
  });

  test('creates one linked canonical task with subtasks after selection', () {
    final source = note();
    final selected = NoteToChecklist.candidates(source).take(2).toList();
    final created = NoteToChecklist.buildTask(
      source: source,
      selected: selected,
      taskId: 'new-task-1',
      nowMilliseconds: 2000,
    );
    final task = TaskDetails.decode(created.taskJson!);
    expect(created.isTask, isTrue);
    expect(task.linkedNoteId, source.id);
    expect(task.subtasks.map((e) => e.title).toList(), selected);
    expect(task.subtasks.every((e) => !e.completed), isTrue);
    expect(task.due, isNull);
    expect(created.body, isEmpty);
    expect(created.tags, isEmpty);
    expect(created.id, isNot(source.id));
    expect(
        source.body, '- [ ] Telefonare\n- Preparare slides\n1. Spedire email');
  });

  test('rejects unreviewed items, duplicate selection or empty confirmation',
      () {
    final source = note();
    for (final selection in [
      <String>[],
      ['Inventa un evento'],
      ['Telefonare', 'Telefonare'],
    ]) {
      expect(
        () => NoteToChecklist.buildTask(
          source: source,
          selected: selection,
          taskId: 'task-2',
          nowMilliseconds: 4000,
        ),
        throwsFormatException,
      );
    }
  });

  test('never offers private deleted, visual, or task records for conversion',
      () {
    expect(NoteToChecklist.candidates(note(deletedAt: 10)), isEmpty);
    expect(
        NoteToChecklist.candidates(
            note(taskJson: TaskDetails.empty().encode())),
        isEmpty);
    expect(
        NoteToChecklist.candidates(note(sketchJson: '{"kind":"WHITEBOARD"}')),
        isEmpty);
  });
}
