import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/backup.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/templates.dart';
import 'package:notes_ecosistema/src/screens/templates_screen.dart';

void main() {
  testWidgets('Book Tracker previews and cancels without creating content',
      (tester) async {
    final writes = <TemplateContent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TemplatesScreen(
          notes: const <Note>[],
          onUse: writes.add,
          onEdit: (_) {},
        ),
      ),
    );

    final bookCard = find.byKey(const ValueKey('builtin:book_tracker'));
    await tester.tap(
      find.descendant(of: bookCard, matching: find.text('Usa modello')),
    );
    await tester.pumpAndSettle();

    expect(writes, isEmpty);
    expect(find.text('Crea nota'), findsOneWidget);
    expect(find.textContaining('## In lettura'), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);

    await tester.tap(
      find.descendant(of: bookCard, matching: find.text('Usa modello')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '   ');
    await tester.pump();
    final create = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Crea nota'),
    );
    expect(create.onPressed, isNull);
    expect(writes, isEmpty);

    await tester.enterText(find.byType(TextField).last, '  Libri 📚  ');
    await tester.pump();
    await tester.tap(find.text('Includi "Da leggere"'));
    await tester.pump();
    await tester.tap(find.text('Crea nota'));
    await tester.pumpAndSettle();

    expect(writes, hasLength(1));
    expect(writes.single.title, 'Libri 📚');
    expect(writes.single.body, contains('## In lettura'));
    expect(writes.single.body, isNot(contains('## Da leggere')));
    expect(writes.single.tags, contains('lettura'));
  });

  test('Book Tracker data survives standard backup round trip', () {
    final content = PageTemplates.bookTracker(title: 'Libri 📚');
    final note = Note(
      id: '11111111-1111-1111-1111-111111111111',
      title: content.title,
      body: content.body,
      createdAt: 1,
      updatedAt: 2,
      tags: content.tags,
    );
    final backup = BackupSnapshot(
      notes: <Note>[note],
      collections: const <NoteCollection>[],
      drafts: const <BackupDraft>[],
    );

    final restored = BackupCodec.decode(BackupCodec.encode(backup, exportedAt: 3));
    expect(restored.notes, hasLength(1));
    expect(restored.notes.single.title, 'Libri 📚');
    expect(restored.notes.single.body, content.body);
    expect(restored.notes.single.tags, ['lettura']);
  });
}
