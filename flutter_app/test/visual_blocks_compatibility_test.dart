import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/attachments.dart';
import 'package:notes_ecosistema/src/domain/blocks.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/visual_documents.dart';

void main() {
  test('Universal blocks round-trip canonical Markdown', () {
    final grave = String.fromCharCode(0x60);
    final markdown = [
      '# Titolo',
      '',
      'Paragrafo **ricco**',
      '',
      '- [ ] Attività',
      '',
      '> Citazione',
      '',
      '${List<String>.filled(3, grave).join()}dart',
      'print("ok");',
      List<String>.filled(3, grave).join(),
      '',
      '---',
    ].join('\n');

    final blocks = BlockEditorCodec.parse(
      'note-1',
      markdown,
      now: 100,
    );
    final encoded = BlockEditorCodec.toMarkdown(blocks);

    expect(blocks.first.type, ContentBlockType.heading);
    expect(
      blocks.any((block) => block.type == ContentBlockType.checklist),
      isTrue,
    );
    expect(
      blocks.any((block) => block.type == ContentBlockType.code),
      isTrue,
    );
    expect(encoded, markdown);
  });

  test('Block visual links preserve Kotlin metadata contract', () {
    final drawing = BlockEditorCodec.newBlock(
      'note',
      ContentBlockType.drawing,
      0,
      now: 1,
    ).copyWith(
      text: 'Idea',
      metadataJson: BlockEditorCodec.drawingMetadata('abc-123'),
    );
    final board = BlockEditorCodec.newBlock(
      'note',
      ContentBlockType.whiteboard,
      1,
      now: 1,
    ).copyWith(
      text: 'Mappa',
      metadataJson: BlockEditorCodec.whiteboardMetadata('board-1'),
    );

    final markdown = BlockEditorCodec.toMarkdown([drawing, board]);

    expect(
      markdown,
      '[Sketch: Idea](notes-sketch://abc-123)\n\n'
      '[Whiteboard: Mappa](notes-board://board-1)',
    );
    final decoded = BlockEditorCodec.parse('note', markdown, now: 2);
    expect(BlockEditorCodec.sketchId(decoded.first), 'abc-123');
    expect(BlockEditorCodec.whiteboardId(decoded.last), 'board-1');
  });

  test('Attachment reference uses SHA-256 Kotlin key format', () {
    final bytes = Uint8List.fromList(utf8.encode('hello'));
    final key = Attachments.key(bytes, AttachmentType.text);
    expect(
      key,
      '2cf24dba5fb0a30e26e83b2ac5b9e29e'
      '1b161e5c1fa7425e73043362938b9824.txt',
    );

    final body = Attachments.append('', key, 'nota.txt');
    final refs = Attachments.refs(body);
    expect(refs.single.key, key);
    expect(refs.single.name, 'nota.txt');
    expect(Attachments.remove(body, key).trim(), isEmpty);
  });

  test('Sketch v2 JSON is readable after round trip', () {
    final document = SketchDocument(
      pages: [
        SketchPage(
          paper: SketchPaper.grid,
          strokes: [
            InkStroke(
              color: 0xFF112233,
              width: 6,
              marker: false,
              points: const [
                InkPoint(10, 20, 1000),
                InkPoint(40, 60, 900),
              ],
            ),
          ],
          shapes: [
            SketchShape(
              kind: SketchShapeKind.rectangle,
              color: 0xFF000000,
              width: 4,
              x1: 100,
              y1: 100,
              x2: 300,
              y2: 240,
            ),
          ],
          texts: [
            SketchText(
              text: 'Ciao',
              color: 0xFF000000,
              x: 80,
              y: 90,
            ),
          ],
        ),
      ],
    );

    final encoded = SketchCodec.encode(document);
    final root = jsonDecode(encoded) as Map<String, dynamic>;
    expect(root['format'], 'notes-sketch');
    expect(root['version'], 2);
    expect(root['width'], 1000);
    expect(root['height'], 1400);

    final decoded = SketchCodec.decode(encoded);
    expect(decoded.page.paper, SketchPaper.grid);
    expect(decoded.page.strokes.single.points, hasLength(2));
    expect(decoded.page.shapes.single.kind, SketchShapeKind.rectangle);
    expect(decoded.page.texts.single.text, 'Ciao');
  });

  test('Whiteboard mind map uses Kotlin wire values', () {
    var document = WhiteboardOps.empty(WhiteboardMode.mindMap);
    document = WhiteboardOps.addMindChild(
      document,
      document.nodes.first.id,
      text: 'Figlio',
    );
    document = WhiteboardOps.autoLayoutMindMap(document);

    final encoded = WhiteboardCodec.encode(document);
    final root = jsonDecode(encoded) as Map<String, dynamic>;
    expect(root['format'], 'notes-whiteboard');
    expect(root['version'], 1);
    expect(root['mode'], 'MIND_MAP');

    final decoded = WhiteboardCodec.decode(encoded);
    expect(decoded.mode, WhiteboardMode.mindMap);
    expect(decoded.nodes, hasLength(2));
    expect(decoded.edges.single.kind, BoardEdgeKind.arrow);
  });

  test('Visual metadata remains compatible with Note visual kind', () {
    final raw = const VisualInfo(
      linkedNoteId: 'note-1',
      kind: VisualInfoKind.whiteboard,
    ).encode();
    final note = Note(
      id: 'visual',
      title: 'Board',
      body: '{}',
      favorite: false,
      createdAt: 1,
      updatedAt: 1,
      pinned: false,
      archived: false,
      tags: const [],
      sketchJson: raw,
    );
    expect(note.visualKind, VisualDocumentKind.whiteboard);
    final info = VisualInfo.decode(raw);
    expect(info.linkedNoteId, 'note-1');
    expect(info.kind, VisualInfoKind.whiteboard);
  });
}
