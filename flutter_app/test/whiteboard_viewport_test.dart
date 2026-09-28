import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/visual_documents.dart';
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

  testWidgets('pen draws persistent ink on the centered whiteboard',
      (tester) async {
    Note? saved;
    final note = Note(
      id: 'whiteboard-ink',
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
          onSave: (value) async {
            saved = value;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Penna'));
    await tester.pump();

    final viewer = find.byType(InteractiveViewer);
    final center = tester.getCenter(viewer);
    await tester.dragFrom(center, const Offset(90, 45));
    await tester.pump();

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    final decoded = WhiteboardCodec.decode(saved!.body);
    expect(decoded.strokes, hasLength(1));
    expect(decoded.strokes.single.points.length, greaterThan(1));
  });
}
