import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/screens/study_sprint_concept_preview.dart';

void main() {
  for (final width in <double>[320, 360, 600]) {
    for (final scale in <double>[1, 2]) {
      testWidgets('Study Sprint responsive $width / text scale $scale',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 760));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 760),
                textScaler: TextScaler.linear(scale),
              ),
              child: const StudySprintConceptPreview(),
            ),
          ),
        );
        expect(find.byKey(const ValueKey('study-sprint-native-preview')),
            findsOneWidget);
        for (var step = 0; step < 3; step++) {
          final next = find.byKey(const ValueKey('study-sprint-next'));
          await tester.ensureVisible(next);
          await tester.pumpAndSettle();
          await tester.tap(next);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(find.byKey(const ValueKey('study-sprint-simulate')),
            findsOneWidget);
        final confirm = find.byType(CheckboxListTile).last;
        await tester.ensureVisible(confirm);
        await tester.pumpAndSettle();
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        await tester
            .ensureVisible(find.byKey(const ValueKey('study-sprint-simulate')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('study-sprint-simulate')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('study-sprint-done')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
