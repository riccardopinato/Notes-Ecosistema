import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/templates.dart';
import 'package:notes_ecosistema/src/screens/templates_screen.dart';

void main() {
  testWidgets('Free catalog and personal templates are distinct, no paywall',
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

    expect(find.text('Catalogo gratuito'), findsOneWidget);
    expect(find.text('Libreria personale · Gratuito'), findsOneWidget);
    expect(find.text('Acquista'), findsNothing);

    await tester.tap(find.text('I miei'));
    await tester.pumpAndSettle();

    expect(find.text('I miei modelli'), findsOneWidget);
    expect(find.text('Libreria personale · Gratuito'), findsNothing);
    expect(find.textContaining('Nessun modello personale'), findsOneWidget);
    expect(created, isEmpty);

    await tester.tap(find.text('Catalogo'));
    await tester.pumpAndSettle();
    expect(find.text('Libreria personale · Gratuito'), findsOneWidget);
  });
}
