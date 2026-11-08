import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/app_locale.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/screens/home_screen.dart';
import 'package:notes_ecosistema/src/theme/notes_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Synthetic and read-only: no external account, backend, or real user data.
  Note note(int n) => Note(
        id: 'synthetic-$n',
        title: 'A long synthetic notebook page $n',
        body: 'A synthetic local body.',
        favorite: false,
        createdAt: 1000 + n,
        updatedAt: 1000 + n,
        pinned: false,
        archived: false,
        tags: const [],
      );

  for (final width in [320.0, 360.0, 393.0, 600.0, 900.0, 1280.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('UI5 renders at width $width dark=$dark scale=$scale',
            (tester) async {
          tester.view.devicePixelRatio = 1.0;
          tester.view.physicalSize = Size(width, 840);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(MaterialApp(
            locale: const Locale('it'),
            supportedLocales: AppLocale.supportedLocales,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: NotesTheme.light(),
            darkTheme: NotesTheme.dark(),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: HomeScreen(
                ui5Preview: true,
                notes: [note(1), note(2)],
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
          expect(find.byKey(const ValueKey('ui5-home-root')), findsOneWidget);
          expect(tester.takeException(), isNull,
              reason: 'No render exceptions/overflows at $width dp, scale $scale');
        });
      }
    }
  }

  testWidgets('UI5 read-only projection handles 5000 synthetic notes',
      (tester) async {
    final source = List.generate(5000, note, growable: false);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeScreen(
          ui5Preview: true,
          notes: source,
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
    expect(find.byKey(const ValueKey('ui5-home-root')), findsOneWidget);
    expect(source.length, 5000);
    expect(tester.takeException(), isNull);
  });
}
