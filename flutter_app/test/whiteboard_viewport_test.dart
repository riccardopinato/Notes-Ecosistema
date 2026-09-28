import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/visual_documents.dart';
import 'package:notes_ecosistema/src/screens/whiteboard_screen.dart';

void main() {
  Note whiteboardNote({
    required String id,
    String body = '',
  }) =>
      Note(
        id: id,
        title: 'Lavagna',
        body: body,
        favorite: false,
        createdAt: 1,
        updatedAt: 2,
        pinned: false,
        archived: false,
        tags: const [],
      );

  testWidgets('whiteboard opens with logical canvas center in viewport center',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardScreen(
          note: whiteboardNote(id: 'whiteboard-1'),
          onSave: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final viewportFinder = find.byKey(const ValueKey('whiteboard-viewport'));
    final canvasFinder = find.byKey(const ValueKey('whiteboard-canvas'));
    expect(viewportFinder, findsOneWidget);
    expect(canvasFinder, findsOneWidget);

    final viewer = tester.widget<InteractiveViewer>(viewportFinder);
    final controller = viewer.transformationController;
    expect(controller, isNotNull);

    final viewport = tester.getSize(viewportFinder);
    final canvas = tester.getSize(canvasFinder);
    expect(
      controller!.value.storage[12],
      closeTo(viewport.width / 2 - canvas.width / 2, 0.01),
    );
    expect(
      controller.value.storage[13],
      closeTo(viewport.height / 2 - canvas.height / 2, 0.01),
    );
  });

  testWidgets('pen draws persistent ink on the centered whiteboard',
      (tester) async {
    Note? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardScreen(
          note: whiteboardNote(id: 'whiteboard-ink'),
          onSave: (value) async {
            saved = value;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Penna'));
    await tester.pump();

    final viewer = find.byKey(const ValueKey('whiteboard-viewport'));
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

  testWidgets('undo and redo restore whiteboard ink', (tester) async {
    Note? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardScreen(
          note: whiteboardNote(id: 'whiteboard-history'),
          onSave: (value) async {
            saved = value;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Penna'));
    await tester.pump();
    final viewport = find.byKey(const ValueKey('whiteboard-viewport'));
    await tester.dragFrom(
      tester.getCenter(viewport),
      const Offset(80, 20),
    );
    await tester.pump();

    final undoFinder = find.byKey(const ValueKey('whiteboard-undo'));
    final redoFinder = find.byKey(const ValueKey('whiteboard-redo'));
    expect(tester.widget<IconButton>(undoFinder).onPressed, isNotNull);

    await tester.tap(undoFinder);
    await tester.pump();
    expect(tester.widget<IconButton>(redoFinder).onPressed, isNotNull);

    await tester.tap(redoFinder);
    await tester.pump();
    expect(tester.widget<IconButton>(undoFinder).onPressed, isNotNull);

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    final decoded = WhiteboardCodec.decode(saved!.body);
    expect(decoded.strokes, hasLength(1));
  });

  testWidgets('node drag remains correct at 2x zoom', (tester) async {
    Note? saved;
    final source = WhiteboardOps.empty(WhiteboardMode.mindMap);
    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardScreen(
          note: whiteboardNote(
            id: 'whiteboard-zoom-drag',
            body: WhiteboardCodec.encode(source),
          ),
          onSave: (value) async {
            saved = value;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final viewportFinder = find.byKey(const ValueKey('whiteboard-viewport'));
    final canvasFinder = find.byKey(const ValueKey('whiteboard-canvas'));
    final viewer = tester.widget<InteractiveViewer>(viewportFinder);
    final controller = viewer.transformationController!;
    final viewport = tester.getSize(viewportFinder);
    final canvas = tester.getSize(canvasFinder);

    final matrix = Matrix4.identity();
    matrix.storage[0] = 2;
    matrix.storage[5] = 2;
    matrix.storage[12] = viewport.width / 2 - canvas.width;
    matrix.storage[13] = viewport.height / 2 - canvas.height;
    controller.value = matrix;
    await tester.pump();

    await tester.drag(
      find.text('Idea principale'),
      const Offset(100, 0),
    );
    await tester.pump();

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    final decoded = WhiteboardCodec.decode(saved!.body);
    expect(decoded.nodes.single.x, closeTo(-90, 4));
  });

  testWidgets('deep mind map expands beyond the former fixed canvas',
      (tester) async {
    var document = WhiteboardOps.empty(WhiteboardMode.mindMap);
    var parent = document.nodes.single;
    for (var i = 0; i < 30; i++) {
      document = WhiteboardOps.addMindChild(
        document,
        parent.id,
        text: 'Livello $i',
      );
      parent = document.nodes.last;
    }
    document = WhiteboardOps.autoLayoutMindMap(document);

    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardScreen(
          note: whiteboardNote(
            id: 'whiteboard-deep',
            body: WhiteboardCodec.encode(document),
          ),
          onSave: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final canvas =
        tester.getSize(find.byKey(const ValueKey('whiteboard-canvas')));
    expect(canvas.width, greaterThan(12000));
    expect(canvas.height, canvas.width);
  });

  testWidgets('stylus input creates ink and does not require finger drawing',
      (tester) async {
    Note? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardScreen(
          note: whiteboardNote(id: 'whiteboard-stylus'),
          onSave: (value) async {
            saved = value;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Penna'));
    await tester.pump();

    final center = tester.getCenter(
      find.byKey(const ValueKey('whiteboard-viewport')),
    );
    final stylus = await tester.createGesture(
      kind: ui.PointerDeviceKind.stylus,
    );
    await stylus.down(center);
    await stylus.moveBy(const Offset(70, 30));
    await stylus.up();
    await tester.pump();

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    final decoded = WhiteboardCodec.decode(saved!.body);
    expect(decoded.strokes, hasLength(1));
  });

  testWidgets('lasso selects only objects inside the drawn area',
      (tester) async {
    final source = WhiteboardDocument(
      nodes: [
        BoardNode(
          id: 'left',
          kind: BoardNodeKind.sticky,
          text: 'Sinistra',
          x: -300,
          y: -40,
          width: 120,
          height: 80,
        ),
        BoardNode(
          id: 'right',
          kind: BoardNodeKind.sticky,
          text: 'Destra',
          x: 300,
          y: -40,
          width: 120,
          height: 80,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardScreen(
          note: whiteboardNote(
            id: 'whiteboard-lasso',
            body: WhiteboardCodec.encode(source),
          ),
          onSave: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Seleziona'));
    await tester.pump();

    final viewport = find.byKey(const ValueKey('whiteboard-viewport'));
    final center = tester.getCenter(viewport);
    await tester.dragFrom(
      center + const Offset(-360, -120),
      const Offset(340, 280),
    );
    await tester.pump();

    expect(find.text('1 selezionati'), findsOneWidget);
  });

  testWidgets('selection can duplicate and resize post-its', (tester) async {
    Note? saved;
    final source = WhiteboardDocument(
      nodes: [
        BoardNode(
          id: 'one',
          kind: BoardNodeKind.sticky,
          text: 'Uno',
          x: -320,
          y: -80,
        ),
        BoardNode(
          id: 'two',
          kind: BoardNodeKind.sticky,
          text: 'Due',
          x: 80,
          y: -80,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardScreen(
          note: whiteboardNote(
            id: 'whiteboard-selection-actions',
            body: WhiteboardCodec.encode(source),
          ),
          onSave: (value) async => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Seleziona'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('whiteboard-select-all')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('whiteboard-duplicate-selection')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('whiteboard-resize-larger')),
    );
    await tester.pump();

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    final decoded = WhiteboardCodec.decode(saved!.body);
    expect(decoded.nodes, hasLength(4));
    final duplicates = decoded.nodes
        .where((node) => node.id != 'one' && node.id != 'two')
        .toList();
    expect(duplicates, hasLength(2));
    expect(duplicates.every((node) => node.width == 300), isTrue);
    expect(duplicates.every((node) => node.height == 186), isTrue);
  });

  testWidgets('snap grid aligns moved selection to 40 px', (tester) async {
    Note? saved;
    final source = WhiteboardDocument(
      nodes: [
        BoardNode(
          id: 'snap',
          kind: BoardNodeKind.sticky,
          text: 'Snap',
          x: 13,
          y: 17,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardScreen(
          note: whiteboardNote(
            id: 'whiteboard-snap',
            body: WhiteboardCodec.encode(source),
          ),
          onSave: (value) async => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Seleziona'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('whiteboard-select-all')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('whiteboard-snap-grid')));
    await tester.pump();

    await tester.drag(find.text('Snap'), const Offset(53, 31));
    await tester.pump();
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    final node = WhiteboardCodec.decode(saved!.body).nodes.single;
    expect(node.x % 40, 0);
    expect(node.y % 40, 0);
  });

  testWidgets('mini-map is always available for board overview',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardScreen(
          note: whiteboardNote(id: 'whiteboard-minimap'),
          onSave: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('whiteboard-minimap')),
      findsOneWidget,
    );
  });

  testWidgets('history remains bounded and stable across repeated ink edits',
      (tester) async {
    Note? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: WhiteboardScreen(
          note: whiteboardNote(id: 'whiteboard-history-stress'),
          onSave: (value) async => saved = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Penna'));
    await tester.pump();

    final viewport = find.byKey(const ValueKey('whiteboard-viewport'));
    final center = tester.getCenter(viewport);
    for (var i = 0; i < 12; i++) {
      await tester.dragFrom(
        center + Offset(-180 + i * 12, -120 + i * 8),
        const Offset(45, 18),
      );
      await tester.pump();
    }

    final undo = find.byKey(const ValueKey('whiteboard-undo'));
    final redo = find.byKey(const ValueKey('whiteboard-redo'));
    for (var i = 0; i < 12; i++) {
      await tester.tap(undo);
      await tester.pump();
    }
    for (var i = 0; i < 12; i++) {
      await tester.tap(redo);
      await tester.pump();
    }

    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    expect(
      WhiteboardCodec.decode(saved!.body).strokes,
      hasLength(12),
    );
  });

}
