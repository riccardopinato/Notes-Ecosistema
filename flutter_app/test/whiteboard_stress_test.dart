import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/visual_documents.dart';

void main() {
  test('whiteboard codec handles a 20k-point stress document within budget', () {
    final strokes = List.generate(
      200,
      (strokeIndex) => InkStroke(
        color: 0xFF111111,
        width: 6,
        points: List.generate(
          100,
          (pointIndex) => InkPoint(
            -9000 + (pointIndex * 70 + strokeIndex * 11) % 18000,
            -7000 + (pointIndex * 43 + strokeIndex * 17) % 14000,
            300 + (pointIndex * 7) % 701,
          ),
        ),
      ),
    );
    final document = WhiteboardDocument(
      paper: WhiteboardPaper.dots,
      strokes: strokes,
      nodes: List.generate(
        80,
        (index) => BoardNode(
          kind: BoardNodeKind.sticky,
          text: 'Stress node $index',
          x: -8000 + (index % 16) * 1000,
          y: -5000 + (index ~/ 16) * 1800,
        ),
      ),
    );

    final stopwatch = Stopwatch()..start();
    final encoded = WhiteboardCodec.encode(document);
    final decoded = WhiteboardCodec.decode(encoded);
    stopwatch.stop();

    expect(WhiteboardRules.pointCount(decoded), 20000);
    expect(decoded.nodes, hasLength(80));
    expect(encoded.length, lessThan(2 * 1024 * 1024));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 8)));
  });

  test('whiteboard validation remains stable near the 50k point ceiling', () {
    final strokes = List.generate(
      500,
      (strokeIndex) => InkStroke(
        color: 0xFF111111,
        width: 4,
        points: List.generate(
          100,
          (pointIndex) => InkPoint(
            -10000 + (strokeIndex * 13 + pointIndex * 5) % 20000,
            -10000 + (strokeIndex * 7 + pointIndex * 11) % 20000,
          ),
        ),
      ),
    );
    final document = WhiteboardDocument(strokes: strokes);

    expect(
      WhiteboardRules.pointCount(WhiteboardRules.validate(document)),
      WhiteboardRules.maxPoints,
    );
  });
}
