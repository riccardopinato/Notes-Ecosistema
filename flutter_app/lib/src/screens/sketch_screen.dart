import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/note.dart';
import '../domain/visual_documents.dart';

enum _SketchTool {
  pen,
  highlighter,
  eraser,
  line,
  rectangle,
  ellipse,
  arrow,
  text,
}

class SketchScreen extends StatefulWidget {
  const SketchScreen({
    required this.note,
    required this.onSave,
    super.key,
  });

  final Note note;
  final Future<void> Function(Note note) onSave;

  @override
  State<SketchScreen> createState() => _SketchScreenState();
}

class _SketchScreenState extends State<SketchScreen> {
  late final TextEditingController _title;
  late SketchDocument _document;
  _SketchTool _tool = _SketchTool.pen;
  bool _saving = false;
  String? _error;

  final List<InkPoint> _workingPoints = [];
  Offset? _shapeStart;
  Offset? _shapeEnd;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note.title);
    try {
      _document = widget.note.body.trim().isEmpty
          ? SketchDocument()
          : SketchCodec.decode(widget.note.body);
    } catch (error) {
      _document = SketchDocument();
      _error = error.toString().replaceFirst('FormatException: ', '');
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  SketchPage get _page => _document.page;

  void _replacePage(SketchPage page) {
    final pages = [..._document.pages];
    pages[_document.activePage] = page;
    setState(() {
      _document = SketchRules.validate(
        _document.copyWith(pages: pages),
      );
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final oldInfo = widget.note.sketchJson == null
          ? null
          : VisualInfo.decode(widget.note.sketchJson!);
      final next = widget.note.copyWith(
        title: _title.text.trim().isEmpty
            ? 'Nuovo disegno'
            : _title.text.trim(),
        body: SketchCodec.encode(_document),
        sketchJson: VisualInfo(
          linkedNoteId: oldInfo?.linkedNoteId,
          kind: VisualInfoKind.sketch,
        ).encode(),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await widget.onSave(next);
      if (mounted) Navigator.pop(context, next);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString().replaceFirst('FormatException: ', '');
        });
      }
    }
  }

  void _addPage() {
    if (_document.pages.length >= SketchRules.maxPages) return;
    setState(() {
      final pages = [..._document.pages, SketchPage(paper: _page.paper)];
      _document = SketchDocument(
        pages: pages,
        activePage: pages.length - 1,
      );
    });
  }

  void _duplicatePage() {
    if (_document.pages.length >= SketchRules.maxPages) return;
    final source = _page;
    final copy = SketchPage(
      paper: source.paper,
      strokes: source.strokes
          .map(
            (stroke) => InkStroke(
              color: stroke.color,
              width: stroke.width,
              marker: stroke.marker,
              points: [...stroke.points],
            ),
          )
          .toList(),
      shapes: source.shapes
          .map(
            (shape) => SketchShape(
              kind: shape.kind,
              color: shape.color,
              width: shape.width,
              x1: shape.x1,
              y1: shape.y1,
              x2: shape.x2,
              y2: shape.y2,
            ),
          )
          .toList(),
      texts: source.texts
          .map(
            (text) => SketchText(
              text: text.text,
              color: text.color,
              x: text.x,
              y: text.y,
              size: text.size,
            ),
          )
          .toList(),
    );
    setState(() {
      final pages = [..._document.pages];
      pages.insert(_document.activePage + 1, copy);
      _document = SketchDocument(
        pages: pages,
        activePage: _document.activePage + 1,
      );
    });
  }

  void _deletePage() {
    setState(() {
      if (_document.pages.length == 1) {
        _document = SketchDocument(
          pages: [SketchPage(paper: _page.paper)],
        );
        return;
      }
      final pages = [..._document.pages]..removeAt(_document.activePage);
      _document = SketchDocument(
        pages: pages,
        activePage: _document.activePage.clamp(0, pages.length - 1),
      );
    });
  }

  void _setPaper(SketchPaper paper) {
    _replacePage(_page.copyWith(paper: paper));
  }

  InkPoint _point(Offset local) => InkPoint(
        local.dx.round().clamp(0, SketchRules.width),
        local.dy.round().clamp(0, SketchRules.height),
      );

  void _panStart(DragStartDetails details) {
    final point = _point(details.localPosition);
    if (_tool == _SketchTool.pen ||
        _tool == _SketchTool.highlighter) {
      _workingPoints
        ..clear()
        ..add(point);
    } else if (_tool == _SketchTool.eraser) {
      _erase(point);
    } else if (_tool != _SketchTool.text) {
      _shapeStart = Offset(point.x.toDouble(), point.y.toDouble());
      _shapeEnd = _shapeStart;
      setState(() {});
    }
  }

  void _panUpdate(DragUpdateDetails details) {
    final point = _point(details.localPosition);
    if (_tool == _SketchTool.pen ||
        _tool == _SketchTool.highlighter) {
      _workingPoints.add(point);
      setState(() {});
    } else if (_tool == _SketchTool.eraser) {
      _erase(point);
    } else if (_tool != _SketchTool.text) {
      _shapeEnd = Offset(point.x.toDouble(), point.y.toDouble());
      setState(() {});
    }
  }

  void _panEnd(DragEndDetails details) {
    if ((_tool == _SketchTool.pen ||
            _tool == _SketchTool.highlighter) &&
        _workingPoints.isNotEmpty) {
      final stroke = InkStroke(
        color: _tool == _SketchTool.highlighter
            ? 0x88FFD54F
            : 0xFF111111,
        width: _tool == _SketchTool.highlighter ? 24 : 6,
        marker: _tool == _SketchTool.highlighter,
        points: [..._workingPoints],
      );
      _workingPoints.clear();
      _replacePage(
        _page.copyWith(strokes: [..._page.strokes, stroke]),
      );
      return;
    }

    if (_shapeStart != null && _shapeEnd != null) {
      final start = _shapeStart!;
      final end = _shapeEnd!;
      final kind = switch (_tool) {
        _SketchTool.line => SketchShapeKind.line,
        _SketchTool.rectangle => SketchShapeKind.rectangle,
        _SketchTool.ellipse => SketchShapeKind.ellipse,
        _SketchTool.arrow => SketchShapeKind.arrow,
        _ => null,
      };
      if (kind != null) {
        _replacePage(
          _page.copyWith(
            shapes: [
              ..._page.shapes,
              SketchShape(
                kind: kind,
                color: 0xFF111111,
                width: 5,
                x1: start.dx.round(),
                y1: start.dy.round(),
                x2: end.dx.round(),
                y2: end.dy.round(),
              ),
            ],
          ),
        );
      }
    }
    _shapeStart = null;
    _shapeEnd = null;
    setState(() {});
  }

  Future<void> _tap(TapUpDetails details) async {
    if (_tool != _SketchTool.text) return;
    final point = _point(details.localPosition);
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Inserisci testo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 4000,
          decoration: const InputDecoration(labelText: 'Testo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Inserisci'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty || !mounted) return;
    _replacePage(
      _page.copyWith(
        texts: [
          ..._page.texts,
          SketchText(
            text: text,
            color: 0xFF111111,
            x: point.x,
            y: point.y,
          ),
        ],
      ),
    );
  }

  void _erase(InkPoint point) {
    const radius = 34.0;
    bool hitStroke(InkStroke stroke) {
      for (final candidate in stroke.points) {
        final dx = candidate.x - point.x;
        final dy = candidate.y - point.y;
        if (math.sqrt(dx * dx + dy * dy) <= radius + stroke.width / 2) {
          return true;
        }
      }
      return false;
    }

    final shapes = _page.shapes.where((shape) {
      final left = math.min(shape.x1, shape.x2) - radius;
      final right = math.max(shape.x1, shape.x2) + radius;
      final top = math.min(shape.y1, shape.y2) - radius;
      final bottom = math.max(shape.y1, shape.y2) + radius;
      return !(point.x >= left &&
          point.x <= right &&
          point.y >= top &&
          point.y <= bottom);
    }).toList();

    final texts = _page.texts.where((text) {
      return !((point.x - text.x).abs() < 220 &&
          (point.y - text.y).abs() < 70);
    }).toList();

    _replacePage(
      _page.copyWith(
        strokes: _page.strokes.where((stroke) => !hitStroke(stroke)).toList(),
        shapes: shapes,
        texts: texts,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewShape = _shapeStart != null && _shapeEnd != null
        ? SketchShape(
            kind: switch (_tool) {
              _SketchTool.rectangle => SketchShapeKind.rectangle,
              _SketchTool.ellipse => SketchShapeKind.ellipse,
              _SketchTool.arrow => SketchShapeKind.arrow,
              _ => SketchShapeKind.line,
            },
            color: 0xFF111111,
            width: 5,
            x1: _shapeStart!.dx.round(),
            y1: _shapeStart!.dy.round(),
            x2: _shapeEnd!.dx.round(),
            y2: _shapeEnd!.dy.round(),
          )
        : null;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _title,
          decoration: const InputDecoration(
            hintText: 'Nuovo disegno',
            border: InputBorder.none,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Salvataggio…' : 'Salva'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_saving) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _toolButton(Icons.edit, 'Penna', _SketchTool.pen),
                _toolButton(
                  Icons.border_color,
                  'Evidenziatore',
                  _SketchTool.highlighter,
                ),
                _toolButton(
                  Icons.auto_fix_normal,
                  'Gomma',
                  _SketchTool.eraser,
                ),
                _toolButton(Icons.show_chart, 'Linea', _SketchTool.line),
                _toolButton(
                  Icons.rectangle_outlined,
                  'Rettangolo',
                  _SketchTool.rectangle,
                ),
                _toolButton(
                  Icons.circle_outlined,
                  'Ellisse',
                  _SketchTool.ellipse,
                ),
                _toolButton(
                  Icons.arrow_forward,
                  'Freccia',
                  _SketchTool.arrow,
                ),
                _toolButton(Icons.text_fields, 'Testo', _SketchTool.text),
                const VerticalDivider(),
                PopupMenuButton<SketchPaper>(
                  tooltip: 'Tipo carta',
                  onSelected: _setPaper,
                  itemBuilder: (_) => SketchPaper.values
                      .map(
                        (paper) => PopupMenuItem(
                          value: paper,
                          child: Text(_paperLabel(paper)),
                        ),
                      )
                      .toList(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Center(child: Icon(Icons.grid_on)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: InteractiveViewer(
                minScale: 0.35,
                maxScale: 3.5,
                constrained: false,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: _panStart,
                  onPanUpdate: _panUpdate,
                  onPanEnd: _panEnd,
                  onTapUp: _tap,
                  child: CustomPaint(
                    size: const Size(
                      SketchRules.width.toDouble(),
                      SketchRules.height.toDouble(),
                    ),
                    painter: _SketchPainter(
                      page: _page,
                      working: _workingPoints,
                      previewShape: previewShape,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: SizedBox(
              height: 58,
              child: Row(
                children: [
                  IconButton(
                    onPressed: _document.activePage > 0
                        ? () => setState(() {
                              _document = _document.copyWith(
                                activePage: _document.activePage - 1,
                              );
                            })
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Pagina ${_document.activePage + 1}/${_document.pages.length}',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _document.activePage < _document.pages.length - 1
                        ? () => setState(() {
                              _document = _document.copyWith(
                                activePage: _document.activePage + 1,
                              );
                            })
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                  IconButton(
                    onPressed: _addPage,
                    tooltip: 'Nuova pagina',
                    icon: const Icon(Icons.note_add),
                  ),
                  IconButton(
                    onPressed: _duplicatePage,
                    tooltip: 'Duplica pagina',
                    icon: const Icon(Icons.copy),
                  ),
                  IconButton(
                    onPressed: _deletePage,
                    tooltip: 'Elimina pagina',
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolButton(
    IconData icon,
    String tooltip,
    _SketchTool tool,
  ) =>
      IconButton.filledTonal(
        onPressed: () => setState(() => _tool = tool),
        tooltip: tooltip,
        isSelected: _tool == tool,
        icon: Icon(icon),
      );
}

class _SketchPainter extends CustomPainter {
  const _SketchPainter({
    required this.page,
    required this.working,
    required this.previewShape,
  });

  final SketchPage page;
  final List<InkPoint> working;
  final SketchShape? previewShape;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white,
    );
    _paper(canvas, size);

    for (final stroke in page.strokes) {
      _stroke(canvas, stroke);
    }
    if (working.isNotEmpty) {
      _stroke(
        canvas,
        InkStroke(
          color: 0xFF111111,
          width: 6,
          marker: false,
          points: working,
        ),
      );
    }
    for (final shape in page.shapes) {
      _shape(canvas, shape);
    }
    if (previewShape != null) _shape(canvas, previewShape!);

    for (final text in page.texts) {
      final painter = TextPainter(
        text: TextSpan(
          text: text.text,
          style: TextStyle(
            color: Color(text.color),
            fontSize: text.size.toDouble(),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 600);
      painter.paint(canvas, Offset(text.x.toDouble(), text.y.toDouble()));
    }
  }

  void _paper(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0x1A455A64)
      ..strokeWidth = 1;
    if (page.paper == SketchPaper.ruled ||
        page.paper == SketchPaper.cornell) {
      for (double y = 70; y < size.height; y += 70) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      }
      if (page.paper == SketchPaper.cornell) {
        canvas.drawLine(
          const Offset(220, 0),
          Offset(220, size.height),
          linePaint..strokeWidth = 2,
        );
      }
    } else if (page.paper == SketchPaper.grid) {
      for (double x = 50; x < size.width; x += 50) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
      }
      for (double y = 50; y < size.height; y += 50) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      }
    } else if (page.paper == SketchPaper.dots) {
      final dot = Paint()..color = const Color(0x33455A64);
      for (double x = 40; x < size.width; x += 40) {
        for (double y = 40; y < size.height; y += 40) {
          canvas.drawCircle(Offset(x, y), 1.8, dot);
        }
      }
    }
  }

  void _stroke(Canvas canvas, InkStroke stroke) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..color = Color(stroke.color)
      ..strokeWidth = stroke.width.toDouble()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(
        stroke.points.first.x.toDouble(),
        stroke.points.first.y.toDouble(),
      );
    for (final point in stroke.points.skip(1)) {
      path.lineTo(point.x.toDouble(), point.y.toDouble());
    }
    canvas.drawPath(path, paint);
  }

  void _shape(Canvas canvas, SketchShape shape) {
    final paint = Paint()
      ..color = Color(shape.color)
      ..strokeWidth = shape.width.toDouble()
      ..style = PaintingStyle.stroke;
    final a = Offset(shape.x1.toDouble(), shape.y1.toDouble());
    final b = Offset(shape.x2.toDouble(), shape.y2.toDouble());
    switch (shape.kind) {
      case SketchShapeKind.line:
        canvas.drawLine(a, b, paint);
        break;
      case SketchShapeKind.rectangle:
        canvas.drawRect(Rect.fromPoints(a, b), paint);
        break;
      case SketchShapeKind.ellipse:
        canvas.drawOval(Rect.fromPoints(a, b), paint);
        break;
      case SketchShapeKind.arrow:
        canvas.drawLine(a, b, paint);
        final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
        const length = 28.0;
        final left = Offset(
          b.dx - length * math.cos(angle - math.pi / 6),
          b.dy - length * math.sin(angle - math.pi / 6),
        );
        final right = Offset(
          b.dx - length * math.cos(angle + math.pi / 6),
          b.dy - length * math.sin(angle + math.pi / 6),
        );
        canvas.drawLine(b, left, paint);
        canvas.drawLine(b, right, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _SketchPainter oldDelegate) => true;
}

String _paperLabel(SketchPaper paper) => switch (paper) {
      SketchPaper.plain => 'Bianco',
      SketchPaper.ruled => 'Righe',
      SketchPaper.grid => 'Griglia',
      SketchPaper.dots => 'Puntini',
      SketchPaper.cornell => 'Cornell',
    };
