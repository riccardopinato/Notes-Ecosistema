import 'dart:convert';

import 'package:uuid/uuid.dart';

enum VisualInfoKind { sketch, whiteboard }

class VisualInfo {
  const VisualInfo({this.linkedNoteId, required this.kind});
  final String? linkedNoteId;
  final VisualInfoKind kind;

  String encode() => jsonEncode({
        'linkedNoteId': linkedNoteId,
        'kind': kind.name.toUpperCase(),
      });

  factory VisualInfo.decode(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final kindRaw = (map['kind']?.toString() ?? 'SKETCH').toLowerCase();
    return VisualInfo(
      linkedNoteId: map['linkedNoteId']?.toString(),
      kind: kindRaw == 'whiteboard'
          ? VisualInfoKind.whiteboard
          : VisualInfoKind.sketch,
    );
  }
}

enum SketchPaper { plain, ruled, grid, dots, cornell }

enum SketchShapeKind { line, rectangle, ellipse, arrow }

class InkPoint {
  const InkPoint(this.x, this.y, [this.pressure = 1000]);
  final int x;
  final int y;
  final int pressure;
}

class InkStroke {
  InkStroke({
    required this.color,
    required this.width,
    required this.marker,
    required this.points,
    String? id,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final int color;
  final int width;
  final bool marker;
  final List<InkPoint> points;
}

class SketchShape {
  SketchShape({
    required this.kind,
    required this.color,
    required this.width,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    String? id,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final SketchShapeKind kind;
  final int color;
  final int width;
  final int x1;
  final int y1;
  final int x2;
  final int y2;
}

class SketchText {
  SketchText({
    required this.text,
    required this.color,
    required this.x,
    required this.y,
    this.size = 32,
    String? id,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String text;
  final int color;
  final int x;
  final int y;
  final int size;
}

class SketchPage {
  SketchPage({
    List<InkStroke>? strokes,
    this.paper = SketchPaper.plain,
    List<SketchShape>? shapes,
    List<SketchText>? texts,
    String? id,
  })  : id = id ?? const Uuid().v4(),
        strokes = strokes ?? const [],
        shapes = shapes ?? const [],
        texts = texts ?? const [];

  final String id;
  final SketchPaper paper;
  final List<InkStroke> strokes;
  final List<SketchShape> shapes;
  final List<SketchText> texts;

  SketchPage copyWith({
    List<InkStroke>? strokes,
    SketchPaper? paper,
    List<SketchShape>? shapes,
    List<SketchText>? texts,
  }) =>
      SketchPage(
        id: id,
        strokes: strokes ?? this.strokes,
        paper: paper ?? this.paper,
        shapes: shapes ?? this.shapes,
        texts: texts ?? this.texts,
      );
}

class SketchDocument {
  SketchDocument({List<SketchPage>? pages, this.activePage = 0})
      : pages = pages ?? [SketchPage()];

  final List<SketchPage> pages;
  final int activePage;

  SketchPage get page => pages[activePage];

  SketchDocument copyWith({
    List<SketchPage>? pages,
    int? activePage,
  }) =>
      SketchDocument(
        pages: pages ?? this.pages,
        activePage: activePage ?? this.activePage,
      );
}

abstract final class SketchRules {
  static const width = 1000;
  static const height = 1400;
  static const maxPoints = 24000;
  static const maxStrokes = 1500;
  static const maxShapes = 400;
  static const maxTexts = 200;
  static const maxPages = 64;

  static SketchDocument validate(SketchDocument document) {
    if (document.pages.isEmpty ||
        document.pages.length > maxPages ||
        document.activePage < 0 ||
        document.activePage >= document.pages.length) {
      throw const FormatException('Documento sketch non valido.');
    }
    for (final page in document.pages) {
      if (page.strokes.length > maxStrokes ||
          page.shapes.length > maxShapes ||
          page.texts.length > maxTexts ||
          page.strokes.fold<int>(
                0,
                (sum, stroke) => sum + stroke.points.length,
              ) >
              maxPoints) {
        throw const FormatException('Pagina sketch troppo complessa.');
      }
      for (final stroke in page.strokes) {
        if (stroke.id.isEmpty ||
            stroke.width < 1 ||
            stroke.width > 80 ||
            stroke.points.isEmpty) {
          throw const FormatException('Tratto non valido.');
        }
        for (final point in stroke.points) {
          if (point.x < 0 ||
              point.x > width ||
              point.y < 0 ||
              point.y > height ||
              point.pressure < 0 ||
              point.pressure > 1000) {
            throw const FormatException('Punto fuori pagina.');
          }
        }
      }
    }
    return document;
  }
}

abstract final class SketchCodec {
  static const maxBytes = 1024 * 1024;

  static String encode(SketchDocument document) {
    SketchRules.validate(document);
    final raw = jsonEncode({
      'format': 'notes-sketch',
      'version': 2,
      'width': SketchRules.width,
      'height': SketchRules.height,
      'activePage': document.activePage,
      'pages': document.pages
          .map(
            (page) => {
              'id': page.id,
              'paper': page.paper.name.toUpperCase(),
              'strokes': page.strokes
                  .map(
                    (stroke) => {
                      'id': stroke.id,
                      'color': stroke.color,
                      'width': stroke.width,
                      'marker': stroke.marker,
                      'points': [
                        for (final point in stroke.points) ...[
                          point.x,
                          point.y,
                          point.pressure,
                        ],
                      ],
                    },
                  )
                  .toList(),
              'shapes': page.shapes
                  .map(
                    (shape) => {
                      'id': shape.id,
                      'kind': shape.kind.name.toUpperCase(),
                      'color': shape.color,
                      'width': shape.width,
                      'x1': shape.x1,
                      'y1': shape.y1,
                      'x2': shape.x2,
                      'y2': shape.y2,
                    },
                  )
                  .toList(),
              'texts': page.texts
                  .map(
                    (text) => {
                      'id': text.id,
                      'text': text.text,
                      'color': text.color,
                      'x': text.x,
                      'y': text.y,
                      'size': text.size,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
    });
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Disegno oltre 1 MiB.');
    }
    return raw;
  }

  static SketchDocument decode(String raw) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Disegno oltre 1 MiB.');
    }
    final root = jsonDecode(raw) as Map<String, dynamic>;
    if (root['format'] != 'notes-sketch') {
      throw const FormatException('Formato disegno non supportato.');
    }
    final version = (root['version'] as num?)?.toInt() ?? 0;
    if ((root['width'] as num?)?.toInt() != SketchRules.width ||
        (root['height'] as num?)?.toInt() != SketchRules.height) {
      throw const FormatException('Dimensioni sketch non supportate.');
    }

    if (version == 1) {
      final strokes = <InkStroke>[];
      for (final value in (root['strokes'] as List? ?? const [])) {
        final map = value as Map<String, dynamic>;
        final pointsRaw = (map['points'] as List).cast<num>();
        final points = <InkPoint>[];
        for (var i = 0; i + 1 < pointsRaw.length; i += 2) {
          points.add(
            InkPoint(pointsRaw[i].toInt(), pointsRaw[i + 1].toInt()),
          );
        }
        strokes.add(
          InkStroke(
            color: (map['color'] as num).toInt(),
            width: (map['width'] as num).toInt(),
            marker: map['marker'] == true,
            points: points,
          ),
        );
      }
      return SketchRules.validate(
        SketchDocument(pages: [SketchPage(strokes: strokes)]),
      );
    }

    if (version != 2) {
      throw const FormatException('Versione disegno non supportata.');
    }

    final pages = <SketchPage>[];
    for (final value in (root['pages'] as List? ?? const [])) {
      final map = value as Map<String, dynamic>;
      final strokes = <InkStroke>[];
      for (final strokeValue in (map['strokes'] as List? ?? const [])) {
        final stroke = strokeValue as Map<String, dynamic>;
        final rawPoints = (stroke['points'] as List).cast<num>();
        final points = <InkPoint>[];
        for (var i = 0; i + 2 < rawPoints.length; i += 3) {
          points.add(
            InkPoint(
              rawPoints[i].toInt(),
              rawPoints[i + 1].toInt(),
              rawPoints[i + 2].toInt().clamp(0, 1000),
            ),
          );
        }
        strokes.add(
          InkStroke(
            id: stroke['id']?.toString(),
            color: (stroke['color'] as num).toInt(),
            width: (stroke['width'] as num).toInt(),
            marker: stroke['marker'] == true,
            points: points,
          ),
        );
      }

      final shapes = <SketchShape>[];
      for (final shapeValue in (map['shapes'] as List? ?? const [])) {
        final shape = shapeValue as Map<String, dynamic>;
        shapes.add(
          SketchShape(
            id: shape['id']?.toString(),
            kind: SketchShapeKind.values.firstWhere(
              (value) =>
                  value.name.toUpperCase() ==
                  shape['kind']?.toString().toUpperCase(),
            ),
            color: (shape['color'] as num).toInt(),
            width: (shape['width'] as num).toInt(),
            x1: (shape['x1'] as num).toInt(),
            y1: (shape['y1'] as num).toInt(),
            x2: (shape['x2'] as num).toInt(),
            y2: (shape['y2'] as num).toInt(),
          ),
        );
      }

      final texts = <SketchText>[];
      for (final textValue in (map['texts'] as List? ?? const [])) {
        final text = textValue as Map<String, dynamic>;
        texts.add(
          SketchText(
            id: text['id']?.toString(),
            text: text['text']?.toString() ?? '',
            color: (text['color'] as num).toInt(),
            x: (text['x'] as num).toInt(),
            y: (text['y'] as num).toInt(),
            size: (text['size'] as num?)?.toInt() ?? 32,
          ),
        );
      }

      pages.add(
        SketchPage(
          id: map['id']?.toString(),
          paper: SketchPaper.values.firstWhere(
            (value) =>
                value.name.toUpperCase() ==
                (map['paper']?.toString() ?? 'PLAIN').toUpperCase(),
            orElse: () => SketchPaper.plain,
          ),
          strokes: strokes,
          shapes: shapes,
          texts: texts,
        ),
      );
    }

    return SketchRules.validate(
      SketchDocument(
        pages: pages,
        activePage: ((root['activePage'] as num?)?.toInt() ?? 0)
            .clamp(0, pages.length - 1),
      ),
    );
  }
}

enum WhiteboardMode { freeform, mindMap }

enum BoardNodeKind { sticky, text, noteLink, taskLink, mindNode }

enum BoardShapeKind { rectangle, ellipse }

enum BoardEdgeKind { line, arrow }

class BoardPoint {
  const BoardPoint(this.x, this.y, [this.pressure = 1000]);
  final int x;
  final int y;
  final int pressure;
}

class BoardNode {
  BoardNode({
    required this.kind,
    required this.text,
    required this.x,
    required this.y,
    this.width = 260,
    this.height = 160,
    this.color = 0xFFFFE7A3,
    this.linkedNoteId,
    String? id,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final BoardNodeKind kind;
  final String text;
  final int x;
  final int y;
  final int width;
  final int height;
  final int color;
  final String? linkedNoteId;

  BoardNode copyWith({String? text, int? x, int? y}) => BoardNode(
        id: id,
        kind: kind,
        text: text ?? this.text,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width,
        height: height,
        color: color,
        linkedNoteId: linkedNoteId,
      );
}

class BoardEdge {
  BoardEdge({
    required this.fromNodeId,
    required this.toNodeId,
    this.kind = BoardEdgeKind.arrow,
    this.color = 0xFF52606D,
    this.width = 3,
    this.label = '',
    String? id,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String fromNodeId;
  final String toNodeId;
  final BoardEdgeKind kind;
  final int color;
  final int width;
  final String label;
}

class BoardStroke {
  BoardStroke({
    required this.color,
    required this.width,
    required this.marker,
    required this.points,
    String? id,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final int color;
  final int width;
  final bool marker;
  final List<BoardPoint> points;
}

class BoardShape {
  BoardShape({
    required this.kind,
    required this.color,
    required this.width,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    String? id,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final BoardShapeKind kind;
  final int color;
  final int width;
  final int x1;
  final int y1;
  final int x2;
  final int y2;
}

class WhiteboardCamera {
  const WhiteboardCamera({this.x = 0, this.y = 0, this.zoom = 1});
  final double x;
  final double y;
  final double zoom;
}

class WhiteboardDocument {
  WhiteboardDocument({
    this.mode = WhiteboardMode.freeform,
    List<BoardNode>? nodes,
    List<BoardEdge>? edges,
    List<BoardStroke>? strokes,
    List<BoardShape>? shapes,
    this.camera = const WhiteboardCamera(),
  })  : nodes = nodes ?? const [],
        edges = edges ?? const [],
        strokes = strokes ?? const [],
        shapes = shapes ?? const [];

  final WhiteboardMode mode;
  final List<BoardNode> nodes;
  final List<BoardEdge> edges;
  final List<BoardStroke> strokes;
  final List<BoardShape> shapes;
  final WhiteboardCamera camera;

  WhiteboardDocument copyWith({
    WhiteboardMode? mode,
    List<BoardNode>? nodes,
    List<BoardEdge>? edges,
    List<BoardStroke>? strokes,
    List<BoardShape>? shapes,
    WhiteboardCamera? camera,
  }) =>
      WhiteboardDocument(
        mode: mode ?? this.mode,
        nodes: nodes ?? this.nodes,
        edges: edges ?? this.edges,
        strokes: strokes ?? this.strokes,
        shapes: shapes ?? this.shapes,
        camera: camera ?? this.camera,
      );
}

abstract final class WhiteboardOps {
  static WhiteboardDocument empty(WhiteboardMode mode) {
    if (mode == WhiteboardMode.mindMap) {
      return WhiteboardDocument(
        mode: mode,
        nodes: [
          BoardNode(
            kind: BoardNodeKind.mindNode,
            text: 'Idea principale',
            x: -140,
            y: -80,
            width: 280,
            height: 160,
            color: 0xFFDDEBFF,
          ),
        ],
      );
    }
    return WhiteboardDocument(mode: mode);
  }

  static WhiteboardDocument addNode(
    WhiteboardDocument source, {
    required BoardNodeKind kind,
    required String text,
    required int x,
    required int y,
    int color = 0xFFFFE7A3,
    String? linkedNoteId,
  }) =>
      source.copyWith(
        nodes: [
          ...source.nodes,
          BoardNode(
            kind: kind,
            text: text,
            x: x.clamp(-100000, 100000),
            y: y.clamp(-100000, 100000),
            color: color,
            linkedNoteId: linkedNoteId,
          ),
        ],
      );

  static WhiteboardDocument updateNode(
    WhiteboardDocument source,
    BoardNode node,
  ) =>
      source.copyWith(
        nodes: source.nodes
            .map((value) => value.id == node.id ? node : value)
            .toList(),
      );

  static WhiteboardDocument deleteNode(
    WhiteboardDocument source,
    String id,
  ) =>
      source.copyWith(
        nodes: source.nodes.where((node) => node.id != id).toList(),
        edges: source.edges
            .where(
              (edge) =>
                  edge.fromNodeId != id && edge.toNodeId != id,
            )
            .toList(),
      );

  static WhiteboardDocument connect(
    WhiteboardDocument source,
    String from,
    String to, {
    BoardEdgeKind kind = BoardEdgeKind.arrow,
  }) {
    if (from == to ||
        source.edges.any(
          (edge) =>
              edge.fromNodeId == from && edge.toNodeId == to,
        )) {
      return source;
    }
    return source.copyWith(
      edges: [
        ...source.edges,
        BoardEdge(fromNodeId: from, toNodeId: to, kind: kind),
      ],
    );
  }

  static WhiteboardDocument addMindChild(
    WhiteboardDocument source,
    String parentId, {
    String text = 'Nuova idea',
  }) {
    final parent =
        source.nodes.firstWhere((node) => node.id == parentId);
    final count =
        source.edges.where((edge) => edge.fromNodeId == parentId).length;
    final child = BoardNode(
      kind: BoardNodeKind.mindNode,
      text: text,
      x: parent.x + parent.width + 180,
      y: parent.y + count * 190,
      width: 260,
      height: 140,
      color: 0xFFE7F4E8,
    );
    return connect(
      source.copyWith(nodes: [...source.nodes, child]),
      parent.id,
      child.id,
    );
  }

  static WhiteboardDocument autoLayoutMindMap(
    WhiteboardDocument source,
  ) {
    if (source.mode != WhiteboardMode.mindMap ||
        source.nodes.isEmpty) {
      return source;
    }
    final incoming = <String, List<BoardEdge>>{};
    final outgoing = <String, List<BoardEdge>>{};
    for (final edge in source.edges) {
      incoming.putIfAbsent(edge.toNodeId, () => []).add(edge);
      outgoing.putIfAbsent(edge.fromNodeId, () => []).add(edge);
    }
    final root = source.nodes.firstWhere(
      (node) => (incoming[node.id] ?? const []).isEmpty,
      orElse: () => source.nodes.first,
    );
    final depth = <String, int>{root.id: 0};
    final queue = <String>[root.id];
    while (queue.isNotEmpty) {
      final id = queue.removeAt(0);
      final currentDepth = depth[id] ?? 0;
      for (final edge in outgoing[id] ?? const []) {
        if (!depth.containsKey(edge.toNodeId)) {
          depth[edge.toNodeId] = currentDepth + 1;
          queue.add(edge.toNodeId);
        }
      }
    }
    final maxDepth =
        depth.values.fold<int>(0, (a, b) => a > b ? a : b);
    for (final node in source.nodes) {
      depth.putIfAbsent(node.id, () => maxDepth + 1);
    }
    final byDepth = <int, List<BoardNode>>{};
    for (final node in source.nodes) {
      byDepth.putIfAbsent(depth[node.id]!, () => []).add(node);
    }
    final nodes = source.nodes.map((node) {
      final d = depth[node.id]!;
      final column = byDepth[d]!;
      final index = column.indexWhere((value) => value.id == node.id);
      final total = column.length;
      return node.copyWith(
        x: d * 430 - 140,
        y: (((index - (total - 1) / 2) * 210) - 80).round(),
      );
    }).toList();
    return source.copyWith(nodes: nodes);
  }
}

abstract final class WhiteboardCodec {
  static const maxBytes = 2 * 1024 * 1024;

  static String encode(WhiteboardDocument document) {
    final raw = jsonEncode({
      'format': 'notes-whiteboard',
      'version': 1,
      'mode': document.mode == WhiteboardMode.mindMap
          ? 'MIND_MAP'
          : 'FREEFORM',
      'camera': {
        'x': document.camera.x,
        'y': document.camera.y,
        'zoom': document.camera.zoom,
      },
      'nodes': document.nodes
          .map(
            (node) => {
              'id': node.id,
              'kind': switch (node.kind) {
                BoardNodeKind.sticky => 'STICKY',
                BoardNodeKind.text => 'TEXT',
                BoardNodeKind.noteLink => 'NOTE_LINK',
                BoardNodeKind.taskLink => 'TASK_LINK',
                BoardNodeKind.mindNode => 'MIND_NODE',
              },
              'text': node.text,
              'x': node.x,
              'y': node.y,
              'width': node.width,
              'height': node.height,
              'color': node.color,
              'linkedNoteId': node.linkedNoteId,
            },
          )
          .toList(),
      'edges': document.edges
          .map(
            (edge) => {
              'id': edge.id,
              'from': edge.fromNodeId,
              'to': edge.toNodeId,
              'kind': edge.kind == BoardEdgeKind.arrow
                  ? 'ARROW'
                  : 'LINE',
              'color': edge.color,
              'width': edge.width,
              'label': edge.label,
            },
          )
          .toList(),
      'strokes': document.strokes
          .map(
            (stroke) => {
              'id': stroke.id,
              'color': stroke.color,
              'width': stroke.width,
              'marker': stroke.marker,
              'points': [
                for (final point in stroke.points) ...[
                  point.x,
                  point.y,
                  point.pressure,
                ],
              ],
            },
          )
          .toList(),
      'shapes': document.shapes
          .map(
            (shape) => {
              'id': shape.id,
              'kind': shape.kind == BoardShapeKind.rectangle
                  ? 'RECTANGLE'
                  : 'ELLIPSE',
              'color': shape.color,
              'width': shape.width,
              'x1': shape.x1,
              'y1': shape.y1,
              'x2': shape.x2,
              'y2': shape.y2,
            },
          )
          .toList(),
    });
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Lavagna oltre 2 MiB.');
    }
    return raw;
  }

  static WhiteboardDocument decode(String raw) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Lavagna oltre 2 MiB.');
    }
    final root = jsonDecode(raw) as Map<String, dynamic>;
    if (root['format'] != 'notes-whiteboard' ||
        (root['version'] as num?)?.toInt() != 1) {
      throw const FormatException('Formato lavagna non supportato.');
    }
    final camera = root['camera'] as Map<String, dynamic>? ?? const {};
    final nodes = <BoardNode>[];
    for (final value in (root['nodes'] as List? ?? const [])) {
      final node = value as Map<String, dynamic>;
      nodes.add(
        BoardNode(
          id: node['id']?.toString(),
          kind: switch (node['kind']?.toString()) {
            'TEXT' => BoardNodeKind.text,
            'NOTE_LINK' => BoardNodeKind.noteLink,
            'TASK_LINK' => BoardNodeKind.taskLink,
            'MIND_NODE' => BoardNodeKind.mindNode,
            _ => BoardNodeKind.sticky,
          },
          text: node['text']?.toString() ?? '',
          x: (node['x'] as num?)?.toInt() ?? 0,
          y: (node['y'] as num?)?.toInt() ?? 0,
          width: (node['width'] as num?)?.toInt() ?? 260,
          height: (node['height'] as num?)?.toInt() ?? 160,
          color: (node['color'] as num?)?.toInt() ?? 0xFFFFE7A3,
          linkedNoteId: node['linkedNoteId']?.toString(),
        ),
      );
    }
    final edges = <BoardEdge>[];
    for (final value in (root['edges'] as List? ?? const [])) {
      final edge = value as Map<String, dynamic>;
      edges.add(
        BoardEdge(
          id: edge['id']?.toString(),
          fromNodeId: edge['from']?.toString() ?? '',
          toNodeId: edge['to']?.toString() ?? '',
          kind: edge['kind']?.toString() == 'LINE'
              ? BoardEdgeKind.line
              : BoardEdgeKind.arrow,
          color: (edge['color'] as num?)?.toInt() ?? 0xFF52606D,
          width: (edge['width'] as num?)?.toInt() ?? 3,
          label: edge['label']?.toString() ?? '',
        ),
      );
    }
    final strokes = <BoardStroke>[];
    for (final value in (root['strokes'] as List? ?? const [])) {
      final stroke = value as Map<String, dynamic>;
      final rawPoints = (stroke['points'] as List? ?? const []).cast<num>();
      final points = <BoardPoint>[];
      for (var i = 0; i + 2 < rawPoints.length; i += 3) {
        points.add(
          BoardPoint(
            rawPoints[i].toInt(),
            rawPoints[i + 1].toInt(),
            rawPoints[i + 2].toInt(),
          ),
        );
      }
      strokes.add(
        BoardStroke(
          id: stroke['id']?.toString(),
          color: (stroke['color'] as num?)?.toInt() ?? 0xFF000000,
          width: (stroke['width'] as num?)?.toInt() ?? 4,
          marker: stroke['marker'] == true,
          points: points,
        ),
      );
    }
    final shapes = <BoardShape>[];
    for (final value in (root['shapes'] as List? ?? const [])) {
      final shape = value as Map<String, dynamic>;
      shapes.add(
        BoardShape(
          id: shape['id']?.toString(),
          kind: shape['kind']?.toString() == 'ELLIPSE'
              ? BoardShapeKind.ellipse
              : BoardShapeKind.rectangle,
          color: (shape['color'] as num?)?.toInt() ?? 0xFF000000,
          width: (shape['width'] as num?)?.toInt() ?? 4,
          x1: (shape['x1'] as num?)?.toInt() ?? 0,
          y1: (shape['y1'] as num?)?.toInt() ?? 0,
          x2: (shape['x2'] as num?)?.toInt() ?? 0,
          y2: (shape['y2'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return WhiteboardDocument(
      mode: root['mode']?.toString() == 'MIND_MAP'
          ? WhiteboardMode.mindMap
          : WhiteboardMode.freeform,
      nodes: nodes,
      edges: edges,
      strokes: strokes,
      shapes: shapes,
      camera: WhiteboardCamera(
        x: (camera['x'] as num?)?.toDouble() ?? 0,
        y: (camera['y'] as num?)?.toDouble() ?? 0,
        zoom: (camera['zoom'] as num?)?.toDouble() ?? 1,
      ),
    );
  }
}
