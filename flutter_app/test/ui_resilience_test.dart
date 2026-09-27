import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/widgets/ui_resilience.dart';

void main() {
  test('userErrorText preserves intentional validation messages', () {
    expect(
      userErrorText(const FormatException('Titolo non valido.')),
      'Titolo non valido.',
    );
  });

  test('userErrorText hides native stack traces and obfuscated internals', () {
    final error = PlatformException(
      code: 'error',
      message:
          'Attempt to invoke virtual method java.lang.Class java.lang.Object.getClass() on a null object reference, java.lang.NullPointerException at s92.<init>(r8-map-id:abc:62)',
    );

    expect(
      userErrorText(error, fallback: 'Acquisizione non disponibile.'),
      'Acquisizione non disponibile.',
    );
  });

  testWidgets('long bottom sheet remains scrollable to the last action',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showNotesBottomSheet<void>(
                  context: context,
                  expand: true,
                  builder: (_) => ListView.builder(
                    itemCount: 50,
                    itemBuilder: (_, index) => ListTile(
                      title: Text('Azione $index'),
                    ),
                  ),
                ),
                child: const Text('Apri'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Apri'));
    await tester.pumpAndSettle();

    expect(find.text('Azione 0'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -2400));
    await tester.pumpAndSettle();

    expect(find.text('Azione 49'), findsOneWidget);
  });
}
