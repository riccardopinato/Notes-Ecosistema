import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/visual_documents.dart';

void main() {
  test('Sketch and Whiteboard share the same ink primitive', () {
    final stroke = InkStroke(
      id: 'stroke-1',
      color: 0xFF112233,
      width: 7,
      marker: true,
      points: const [
        InkPoint(10, 20, 700),
        InkPoint(30, 40, 800),
      ],
    );
    final BoardStroke boardStroke = stroke;
    final BoardPoint boardPoint = const InkPoint(1, 2, 900);

    expect(boardStroke.id, 'stroke-1');
    expect(boardPoint.pressure, 900);
  });

  test('shared ink wire representation roundtrips', () {
    final source = InkStroke(
      id: 'stroke-1',
      color: 0xFF000000,
      width: 4,
      marker: false,
      points: const [InkPoint(1, 2, 500), InkPoint(3, 4, 700)],
    );
    final decoded = VisualInkCodec.decode(
      VisualInkCodec.encode(source).cast<String, dynamic>(),
    );
    expect(decoded.id, source.id);
    expect(decoded.points.length, 2);
    expect(decoded.points.last.pressure, 700);
  });

  test('legacy Sketch and Whiteboard codec formats remain separate', () {
    final sketch = SketchDocument(
      pages: [
        SketchPage(
          strokes: [
            InkStroke(
              id: 's',
              color: 1,
              width: 2,
              marker: false,
              points: const [InkPoint(1, 2, 3)],
            ),
          ],
        ),
      ],
    );
    final board = WhiteboardDocument(
      strokes: [
        InkStroke(
          id: 'b',
          color: 1,
          width: 2,
          marker: false,
          points: const [InkPoint(1, 2, 3)],
        ),
      ],
    );

    final sketchRaw = SketchCodec.encode(sketch);
    final boardRaw = WhiteboardCodec.encode(board);
    expect(SketchCodec.decode(sketchRaw).pages.single.strokes.single.id, 's');
    expect(WhiteboardCodec.decode(boardRaw).strokes.single.id, 'b');
    expect(sketchRaw, contains('notes-sketch'));
    expect(boardRaw, contains('notes-whiteboard'));
  });
}
