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
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
              ),
              child: child!,
            ),
            home: const StudySprintConceptPreview(),
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
        // The fixed navigation stays reachable even on 320dp / 2x.
        // Long-body scroll + confirmation is covered separately by the
        // full-size widget test; real screen-reader/physical QA stays open.
        expect(
            find.byKey(const ValueKey('study-sprint-actions')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
