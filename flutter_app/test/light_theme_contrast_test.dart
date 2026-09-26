import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/theme/notes_theme.dart';
import 'package:notes_ecosistema/src/widgets/editorial.dart';

void main() {
  test('light theme uses brand blue for editorial hierarchy', () {
    final theme = NotesTheme.light();
    final colors = theme.colorScheme;

    expect(theme.textTheme.displayMedium?.color, colors.primary);
    expect(theme.textTheme.headlineLarge?.color, colors.primary);
    expect(theme.textTheme.headlineMedium?.color, colors.primary);
    expect(theme.textTheme.headlineSmall?.color, colors.primary);
    expect(theme.textTheme.titleLarge?.color, colors.onSurface);
    expect(theme.textTheme.bodyMedium?.color, colors.onSurfaceVariant);
    expect(theme.textTheme.headlineLarge?.color, isNot(Colors.white));
  });

  test('dark theme keeps readable light text instead of brand-forcing', () {
    final theme = NotesTheme.dark();
    final colors = theme.colorScheme;

    expect(theme.textTheme.headlineLarge?.color, colors.onSurface);
    expect(theme.textTheme.headlineMedium?.color, colors.onSurface);
    expect(theme.textTheme.headlineSmall?.color, colors.onSurface);
    expect(theme.textTheme.titleLarge?.color, colors.onSurface);
    expect(theme.textTheme.bodyMedium?.color, colors.onSurfaceVariant);
  });

  testWidgets('editorial app title is blue in light mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NotesTheme.light(),
        home: Scaffold(
          appBar: AppBar(
            title: const EditorialAppTitle('Note'),
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('Note'));
    final theme = NotesTheme.light();
    expect(title.style?.color, theme.colorScheme.primary);
  });
}
