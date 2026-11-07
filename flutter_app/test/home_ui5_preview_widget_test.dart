import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('UI5 preview keeps read-only recent links and explicit actions',
      (tester) async {
    var newNotes = 0;
    var tasksOpened = 0;
    String? opened;
    final source = Note(
      id: 'recent-note',
      title: 'Recent page',
      body: 'Source content stays canonical.',
      favorite: false,
      createdAt: 1,
      updatedAt: DateTime(2026, 11, 7).millisecondsSinceEpoch,
      pinned: false,
      archived: false,
      tags: const [],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeScreen(
          ui5Preview: true,
          notes: [source],
          collections: const [],
          projectCount: 0,
          onCreate: () => newNotes++,
          onNotes: () {},
          onAgenda: () {},
          onTasks: () => tasksOpened++,
          onSketch: () {},
          onCollection: (_) {},
          onOpenNote: (note) => opened = note.id,
          onProjects: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ui5-home-root')), findsOneWidget);
    expect(find.text('Today, your space.'), findsOneWidget);
    expect(find.text('Recent page'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ui5-new-note')));
    await tester.tap(find.byKey(const ValueKey('ui5-open-tasks')));
    expect(newNotes, 1);
    expect(tasksOpened, 1);

    await tester.ensureVisible(
      find.byKey(const ValueKey('ui5-recent-recent-note')),
    );
    await tester.tap(find.byKey(const ValueKey('ui5-recent-recent-note')));
    expect(opened, 'recent-note');
    expect(tester.takeException(), isNull);
  });

  testWidgets('UI5 tools are collapsed by default, remain reachable',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeScreen(
          ui5Preview: true,
          notes: const [],
          collections: const [],
          projectCount: 0,
          onCreate: () {},
          onNotes: () {},
          onAgenda: () {},
          onTasks: () {},
          onSketch: () {},
          onCollection: (_) {},
          onOpenNote: (_) {},
          onProjects: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('ui5-tools')));
    await tester.tap(find.text('Your tools'));
    await tester.pumpAndSettle();
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Compare notes'), findsOneWidget);
    expect(find.text('Privacy copy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
