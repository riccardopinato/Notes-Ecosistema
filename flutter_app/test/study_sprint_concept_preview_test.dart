import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/templates.dart';
import 'package:notes_ecosistema/src/screens/templates_screen.dart';

void main() {
  testWidgets('Study Sprint concept is interactive but cannot write a note',
      (tester) async {
    final writes = <TemplateContent>[];
    await tester.pumpWidget(MaterialApp(home: TemplatesScreen(
      notes: const <Note>[], onUse: writes.add, onEdit: (_) {})));
    await tester.tap(find.byKey(const ValueKey('study-sprint-concept-card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('study-sprint-native-preview')), findsOneWidget);
    for (var index = 0; index < 3; index++) {
      await tester.tap(find.byKey(const ValueKey('study-sprint-next')));
      await tester.pumpAndSettle();
    }
    expect(tester.widget<FilledButton>(
      find.byKey(const ValueKey('study-sprint-simulate'))).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('study-sprint-simulate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('study-sprint-done')), findsOneWidget);
    expect(writes, isEmpty);
  });
}
