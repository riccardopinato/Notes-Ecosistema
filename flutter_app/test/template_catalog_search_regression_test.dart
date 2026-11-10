import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/templates.dart';
import 'package:notes_ecosistema/src/screens/templates_screen.dart';

void main() {
  test('All free built-in Notes templates use real paragraph breaks', () {
    for (final template in PageTemplates.all) {
      expect(template.body, contains('\n\n'), reason: template.key);
      expect(template.body, isNot(contains(r'\n')), reason: template.key);
      expect(template.body.trim(), isNotEmpty);
    }
    final daily = PageTemplates.daily(DateTime(2026, 11, 10));
    expect(daily.body, contains('\n\n'));
    expect(daily.body, isNot(contains(r'\n')));
    expect(daily.body, contains('## Appunti della giornata'));
  });

  testWidgets(
      'Free catalog searches all built-in models, not only Book Tracker',
      (tester) async {
    final created = <TemplateContent>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TemplatesScreen(
          notes: const <Note>[],
          onUse: created.add,
          onEdit: (_) {},
        ),
      ),
    );

    final search = find.byType(TextField).first;
    await tester.enterText(search, 'riunione');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('builtin:meeting')), findsOneWidget);
    expect(find.byKey(const ValueKey('builtin:project')), findsNothing);
    expect(find.byKey(const ValueKey('builtin:study')), findsNothing);
    expect(find.byKey(const ValueKey('builtin:book_tracker')), findsNothing);
    expect(created, isEmpty);

    final meeting = find.byKey(const ValueKey('builtin:meeting'));
    await tester.tap(find.descendant(
      of: meeting,
      matching: find.text('Usa modello'),
    ));
    await tester.pumpAndSettle();
    expect(created, hasLength(1));
    expect(created.single.title, 'Riunione');
    expect(created.single.body, contains('\n\n## Decisioni'));

    await tester.enterText(search, 'zz-non-existent');
    await tester.pumpAndSettle();
    expect(find.text('Nessun modello trovato nel catalogo.'), findsOneWidget);
    expect(find.byKey(const ValueKey('builtin:meeting')), findsNothing);
    expect(created, hasLength(1));
  });
}
