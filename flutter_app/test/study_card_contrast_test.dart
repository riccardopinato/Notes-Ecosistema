import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notes_ecosistema/src/screens/home_screen.dart';
import 'package:notes_ecosistema/src/theme/notes_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final theme in [NotesTheme.light(), NotesTheme.dark()]) {
    testWidgets('Study blue card uses onTertiary for all text and icons',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: HomeScreen(
              notes: const [],
              collections: const [],
              onCreate: () {},
              onNotes: () {},
              onAgenda: () {},
              onTasks: () {},
              onSketch: () {},
              onCollection: (_) {},
              onOpenNote: (_) {},
              onProjects: () {},
              projectCount: 0,
              onStudy: () {},
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
          find.text('Ripassa dalle tue note.'), 100);
      final foreground = theme.colorScheme.onTertiary;
      final title = tester.widget<Text>(find.text('Ripassa dalle tue note.'));
      final body = tester.widget<Text>(
        find.text('LearningItem source-linked e coda giornaliera semplice.'),
      );
      final eyebrow = tester.widget<Text>(find.text('STUDY'));
      expect(title.style?.color, foreground);
      expect(body.style?.color, foreground);
      expect(eyebrow.style?.color, foreground);
      final studyCard = find
          .ancestor(
            of: find.text('Ripassa dalle tue note.'),
            matching: find.byType(Material),
          )
          .first;
      final material = tester.widget<Material>(studyCard);
      expect(material.color, theme.colorScheme.tertiaryContainer);
      final icons = find.descendant(
        of: studyCard,
        matching: find.byType(Icon),
      );
      expect(icons, findsWidgets);
      for (final icon in tester.widgetList<Icon>(icons)) {
        expect(icon.color, foreground);
      }
    });
  }
}
