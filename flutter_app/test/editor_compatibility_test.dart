import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/diary.dart';
import 'package:notes_ecosistema/src/domain/editing.dart';
import 'package:notes_ecosistema/src/domain/note.dart';

void main() {
  test('Markdown toolbar preserves selection contract', () {
    final bold = MarkdownEditing.apply(
      'ciao mondo',
      5,
      10,
      MarkdownAction.bold,
    );

    expect(bold.text, 'ciao **mondo**');
    expect(bold.text.substring(bold.start, bold.end), 'mondo');

    final heading = MarkdownEditing.apply(
      'uno\ndue',
      0,
      7,
      MarkdownAction.heading,
    );
    expect(heading.text, '## uno\n## due');
  });

  test('Checklist ignores fenced code and toggles real tasks', () {
    final fence = String.fromCharCodes(List.filled(3, 0x60));
    final body = [
      '- [ ] vera',
      fence,
      '- [ ] codice',
      fence,
      '- [ ] padre',
      '  - [x] figlia',
    ].join('\n');

    final items = Checklist.parse(body);
    expect(items, hasLength(3));
    expect(items.first.label, 'vera');
    expect(items[1].label, 'padre');
    expect(items.last.label, 'figlia');
    expect(items.last.depth, 1);
    expect(items.last.parentLine, items[1].lineIndex);

    final checked = Checklist.setCompleted(body, 0, true);
    expect(checked.startsWith('- [x] vera'), isTrue);
  });

  test('Checklist append refuses an open code fence', () {
    final fence = String.fromCharCodes(List.filled(3, 0x60));
    expect(
      () => Checklist.append('$fence\ncode', 'nuova'),
      throwsFormatException,
    );
  });

  test('Tags match Kotlin limits and diary date participates in limit', () {
    expect(NoteTags.add(['lavoro'], '#Casa'), ['casa', 'lavoro']);
    expect(() => NoteTags.name('non valido!'), throwsFormatException);

    final dated = Diary.datedTags(['Casa', 'lavoro'], DateTime(2026, 9, 23));
    expect(dated, ['casa', 'diario_2026-09-23', 'lavoro']);

    final twenty = List.generate(20, (i) => 'tag$i');
    expect(
      () => Diary.datedTags(twenty, DateTime(2026, 9, 23)),
      throwsFormatException,
    );
  });

  test('Note copyWith can clear nullable Kotlin columns', () {
    const note = Note(
      id: 'n',
      title: 'Titolo',
      body: 'Body',
      collectionId: 'book',
      favorite: false,
      createdAt: 1,
      updatedAt: 2,
      deletedAt: 3,
      pinned: false,
      archived: false,
      tags: [],
      taskJson: '{}',
      sketchJson: '{}',
    );

    final cleared = note.copyWith(
      collectionId: null,
      deletedAt: null,
      taskJson: null,
      sketchJson: null,
    );

    expect(cleared.collectionId, isNull);
    expect(cleared.deletedAt, isNull);
    expect(cleared.taskJson, isNull);
    expect(cleared.sketchJson, isNull);
  });
}
