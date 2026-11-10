import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/screens/study_sprint_concept_preview.dart';

void main() {
  testWidgets(
      'Study Sprint uses real newlines and limits manual topics to eight',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: StudySprintConceptPreview()),
    );

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('study-sprint-next')));
      await tester.pumpAndSettle();
    }

    var preview =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(preview, contains('- Domanda e offerta\n- Mercati\n- Inflazione'));
    expect(preview, isNot(contains(r'\n')));

    await tester.tap(find.byKey(const ValueKey('study-sprint-back')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      List.generate(9, (i) => 'Tema ${i + 1}').join('\n'),
    );
    await tester.tap(find.byKey(const ValueKey('study-sprint-next')));
    await tester.pumpAndSettle();

    preview = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(preview, contains('- Tema 8'));
    expect(preview, isNot(contains('Tema 9')));
    expect(preview, isNot(contains(r'\n')));
  });
}
