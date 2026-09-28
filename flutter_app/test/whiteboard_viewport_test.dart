import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/screens/whiteboard_screen.dart';

void main() {
  testWidgets('whiteboard opens with logical canvas center in viewport center',
      (tester) async {
    final note = Note(
      id: 'whiteboard-1',
      title: 'Lavagna',
      body: '',
      favorite: false,
      createdAt: 1,
      updatedAt: 2,
      pinned: false,
      archived: false,
      tags: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardScreen(
          note: note,
          onSave: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byType(InteractiveViewer);
    expect(finder, findsOneWidget);

    final viewer = tester.widget<InteractiveViewer>(finder);
    final controller = viewer.transformationController;
    expect(controller, isNotNull);

    final viewport = tester.getSize(finder);
    const canvasSize = 4200.0;
    expect(
      controller!.value.storage[12],
      closeTo((viewport.width - canvasSize) / 2, 0.01),
    );
    expect(
      controller.value.storage[13],
      closeTo((viewport.height - canvasSize) / 2, 0.01),
    );
  });
}
