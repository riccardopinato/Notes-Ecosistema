import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../domain/note.dart';
import '../domain/visual_documents.dart';
import '../platform/visual_share_bridge.dart';
import '../widgets/ui_resilience.dart';

enum _WhiteboardTool {
  navigate,
  pen,
  highlighter,
  eraser,
  line,
  rectangle,
  ellipse,
  arrow,
  text,
}

class WhiteboardScreen extends StatefulWidget {
  const WhiteboardScreen({
    required this.note,
    required this.onSave,
    this.readOnly = false,
    super.key,
  });

  final Note note;
  final Future<void> Function(Note note) onSave;
  final bool readOnly;

  @override
  State<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends State<WhiteboardScreen> {
  static const _canvasSize = 4200.0;
  static const _origin = _canvasSize / 2;

  late final TextEditingController _title;
  late WhiteboardDocument _document;
  bool _saving = false;
  bool _connectMode = false;
  String? _connectFrom;
  String? _error;
  final GlobalKey _exportKey = GlobalKey();
  final TransformationController _viewport = TransformationController();
  Size? _lastViewportSize;
  bool _initialViewportCentered = false;
  _WhiteboardTool _tool = _WhiteboardTool.navigate;
  final List<InkPoint> _workingPoints = [];
  Offset? _shapeStart;
  Offset? _shapeEnd;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note.title);
    try {
      _document = widget.note.body.trim().isEmpty
          ? WhiteboardOps.empty(WhiteboardMode.freeform)
          : WhiteboardCodec.decode(widget.note.body);
    } catch (error) {
      _document = WhiteboardOps.empty(WhiteboardMode.freeform);
      _error = userErrorText(error);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _viewport.dispose();
    super.dispose();
  }

  void _centerViewport(Size viewportSize) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) return;
    final dx = (viewportSize.width - _canvasSize) / 2;
    final dy = (viewportSize.height - _canvasSize) / 2;
    _viewport.value = Matrix4.identity()..setTranslationRaw(dx, dy, 0);
  }

  void _scheduleInitialCenter(Size viewportSize) {
    _lastViewportSize = viewportSize;
    if (_initialViewportCentered) return;
    _initialViewportCentered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _centerViewport(_lastViewportSize ?? viewportSize);
    });
  }

  void _setTool(_WhiteboardTool tool) {
    setState(() {
      _tool = tool;
      _connectMode = false;
      _connectFrom = null;
      _workingPoints.clear();
      _shapeStart = null;
      _shapeEnd = null;
    });
  }

  void _setPaper(WhiteboardPaper paper) {
    setState(() {
      _document = _document.copyWith(paper: paper);
    });
  }

  InkPoint _boardPoint(Offset local) {
    final limit = _origin.toInt();
    return InkPoint(
      (local.dx - _origin).round().clamp(-limit, limit).toInt(),
      (local.dy - _origin).round().clamp(-limit, limit).toInt(),
    );
  }

  void _drawStart(DragStartDetails details) {
    final point = _boardPoint(details.localPosition);
    if (_tool == _WhiteboardTool.pen ||
        _tool == _WhiteboardTool.highlighter) {
      _workingPoints
        ..clear()
        ..add(point);
      setState(() {});
      return;
    }
    if (_tool == _WhiteboardTool.eraser) {
      _eraseInk(point);
      return;
    }
    if (_tool == _WhiteboardTool.line ||
        _tool == _WhiteboardTool.rectangle ||
        _tool == _WhiteboardTool.ellipse ||
        _tool == _WhiteboardTool.arrow) {
      _shapeStart = Offset(point.x.toDouble(), point.y.toDouble());
      _shapeEnd = _shapeStart;
      setState(() {});
    }
  }

  void _drawUpdate(DragUpdateDetails details) {
    final point = _boardPoint(details.localPosition);
    if (_tool == _WhiteboardTool.pen ||
        _tool == _WhiteboardTool.highlighter) {
      _workingPoints.add(point);
      setState(() {});
      return;
    }
    if (_tool == _WhiteboardTool.eraser) {
      _eraseInk(point);
      return;
    }
    if (_shapeStart != null) {
      _shapeEnd = Offset(point.x.toDouble(), point.y.toDouble());
      setState(() {});
    }
  }

  void _drawEnd(DragEndDetails details) {
    if ((_tool == _WhiteboardTool.pen ||
            _tool == _WhiteboardTool.highlighter) &&
        _workingPoints.isNotEmpty) {
      final stroke = InkStroke(
        color: _tool == _WhiteboardTool.highlighter
            ? 0x88FFD54F
            : 0xFF111111,
        width: _tool == _WhiteboardTool.highlighter ? 24 : 6,
        marker: _tool == _WhiteboardTool.highlighter,
        points: [..._workingPoints],
      );
      setState(() {
        _document = _document.copyWith(
          strokes: [..._document.strokes, stroke],
        );
        _workingPoints.clear();
      });
      return;
    }

    if (_shapeStart != null && _shapeEnd != null) {
      final start = _shapeStart!;
      final end = _shapeEnd!;
      final kind = switch (_tool) {
        _WhiteboardTool.line => BoardShapeKind.line,
        _WhiteboardTool.rectangle => BoardShapeKind.rectangle,
        _WhiteboardTool.ellipse => BoardShapeKind.ellipse,
        _WhiteboardTool.arrow => BoardShapeKind.arrow,
        _ => null,
      };
      if (kind != null) {
        setState(() {
          _document = _document.copyWith(
            shapes: [
              ..._document.shapes,
              BoardShape(
                kind: kind,
                color: 0xFF111111,
                width: 5,
                x1: start.dx.round(),
                y1: start.dy.round(),
                x2: end.dx.round(),
                y2: end.dy.round(),
              ),
            ],
          );
        });
      }
    }
    _shapeStart = null;
    _shapeEnd = null;
    if (mounted) setState(() {});
  }

  Future<void> _tapCanvas(TapUpDetails details) async {
    if (_tool != _WhiteboardTool.text) return;
    final point = _boardPoint(details.localPosition);
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Inserisci testo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 4000,
          maxLines: 5,
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
    if (value == null || value.isEmpty || !mounted) return;
    setState(() {
      _document = _document.copyWith(
        texts: [
          ..._document.texts,
          SketchText(
            text: value,
            color: 0xFF111111,
            x: point.x,
            y: point.y,
          ),
        ],
      );
    });
  }

  void _eraseInk(InkPoint point) {
    const radius = 38.0;

    bool hitsStroke(InkStroke stroke) {
      for (final candidate in stroke.points) {
        final dx = candidate.x - point.x;
        final dy = candidate.y - point.y;
        if (math.sqrt(dx * dx + dy * dy) <= radius + stroke.width / 2) {
          return true;
        }
      }
      return false;
    }

    final shapes = _document.shapes.where((shape) {
      final left = math.min(shape.x1, shape.x2) - radius;
      final right = math.max(shape.x1, shape.x2) + radius;
      final top = math.min(shape.y1, shape.y2) - radius;
      final bottom = math.max(shape.y1, shape.y2) + radius;
      return !(point.x >= left &&
          point.x <= right &&
          point.y >= top &&
          point.y <= bottom);
    }).toList();

    final texts = _document.texts.where((text) {
      return !((point.x - text.x).abs() < 260 &&
          (point.y - text.y).abs() < 90);
    }).toList();

    setState(() {
      _document = _document.copyWith(
        strokes:
            _document.strokes.where((stroke) => !hitsStroke(stroke)).toList(),
        shapes: shapes,
        texts: texts,
      );
    });
  }

  BoardShape? get _previewShape {
    if (_shapeStart == null || _shapeEnd == null) return null;
    final kind = switch (_tool) {
      _WhiteboardTool.line => BoardShapeKind.line,
      _WhiteboardTool.rectangle => BoardShapeKind.rectangle,
      _WhiteboardTool.ellipse => BoardShapeKind.ellipse,
      _WhiteboardTool.arrow => BoardShapeKind.arrow,
      _ => null,
    };
    if (kind == null) return null;
    return BoardShape(
      kind: kind,
      color: 0xFF111111,
      width: 5,
      x1: _shapeStart!.dx.round(),
      y1: _shapeStart!.dy.round(),
      x2: _shapeEnd!.dx.round(),
      y2: _shapeEnd!.dy.round(),
    );
  }

  Future<void> _save() async {
    if (_saving || widget.readOnly) return;
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
            ? (_document.mode == WhiteboardMode.mindMap
                ? 'Nuova mind map'
                : 'Nuova lavagna')
            : _title.text.trim(),
        body: WhiteboardCodec.encode(_document),
        sketchJson: VisualInfo(
          linkedNoteId: oldInfo?.linkedNoteId,
          kind: VisualInfoKind.whiteboard,
        ).encode(),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await widget.onSave(next);
      if (mounted) Navigator.pop(context, next);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = userErrorText(error);
        });
      }
    }
  }

  Future<Uint8List> _renderPng() async {
    final boundary =
        _exportKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw const FormatException('Lavagna non ancora pronta per export.');
    }
    final image = await boundary.toImage(pixelRatio: 0.5);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw const FormatException('Impossibile creare il PNG.');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _exportPng() async {
    try {
      final bytes = await _renderPng();
      final fallback =
          _document.mode == WhiteboardMode.mindMap ? 'mind-map' : 'lavagna';
      final raw = _title.text.trim();
      final cleaned = raw
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '')
          .toLowerCase();
      final title = cleaned.isEmpty ? fallback : cleaned;
      await FilePicker.platform.saveFile(
        dialogTitle: 'Esporta lavagna PNG',
        fileName: '$title.png',
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lavagna esportata in PNG.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(error),
          ),
        ),
      );
    }
  }

  Future<void> _sharePng() async {
    try {
      final bytes = await _renderPng();
      final fallback = _document.mode == WhiteboardMode.mindMap
          ? 'Mind map Notes'
          : 'Lavagna Notes';
      final title = _title.text.trim().isEmpty ? fallback : _title.text.trim();
      await VisualShareBridge.sharePng(bytes, title: title);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(error),
          ),
        ),
      );
    }
  }

  Future<void> _addNode({
    BoardNodeKind kind = BoardNodeKind.sticky,
    BoardNode? parent,
  }) async {
    final controller = TextEditingController(
      text: kind == BoardNodeKind.mindNode ? 'Nuova idea' : '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          kind == BoardNodeKind.mindNode ? 'Nuova idea' : 'Nuovo elemento',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 8000,
          decoration: const InputDecoration(labelText: 'Testo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Aggiungi'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;

    setState(() {
      if (parent != null && _document.mode == WhiteboardMode.mindMap) {
        _document = WhiteboardOps.addMindChild(
          _document,
          parent.id,
          text: value.isEmpty ? 'Nuova idea' : value,
        );
      } else {
        _document = WhiteboardOps.addNode(
          _document,
          kind: kind,
          text: value,
          x: 0,
          y: 0,
        );
      }
    });
  }

  Future<void> _editNode(BoardNode node) async {
    final controller = TextEditingController(text: node.text);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifica elemento'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 8000,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Testo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, '__DELETE__'),
            child: Text(
              'Elimina',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    setState(() {
      _document = value == '__DELETE__'
          ? WhiteboardOps.deleteNode(_document, node.id)
          : WhiteboardOps.updateNode(
              _document,
              node.copyWith(text: value),
            );
    });
  }

  void _nodeTap(BoardNode node) {
    if (!_connectMode) {
      _editNode(node);
      return;
    }
    if (_connectFrom == null) {
      setState(() => _connectFrom = node.id);
      return;
    }
    if (_connectFrom == node.id) {
      setState(() => _connectFrom = null);
      return;
    }
    setState(() {
      _document = WhiteboardOps.connect(
        _document,
        _connectFrom!,
        node.id,
      );
      _connectFrom = null;
      _connectMode = false;
    });
  }

  void _moveNode(BoardNode node, DragUpdateDetails details) {
    final scale = _viewport.value.getMaxScaleOnAxis().clamp(0.2, 3.2);
    setState(() {
      _document = WhiteboardOps.updateNode(
        _document,
        node.copyWith(
          x: node.x + (details.delta.dx / scale).round(),
          y: node.y + (details.delta.dy / scale).round(),
        ),
      );
    });
  }

  void _setMode(WhiteboardMode mode) {
    setState(() {
      if (mode == _document.mode) return;
      if (mode == WhiteboardMode.mindMap && _document.nodes.isEmpty) {
        final root = WhiteboardOps.empty(mode);
        _document = _document.copyWith(
          mode: mode,
          nodes: root.nodes,
        );
      } else {
        _document = _document.copyWith(mode: mode);
      }
      _connectMode = false;
      _connectFrom = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _title,
          readOnly: widget.readOnly,
          decoration: InputDecoration(
            hintText: _document.mode == WhiteboardMode.mindMap
                ? 'Nuova mind map'
                : 'Nuova lavagna',
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _saving ? null : _exportPng,
            tooltip: 'Salva PNG',
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            onPressed: _saving ? null : _sharePng,
            tooltip: 'Condividi PNG',
            icon: const Icon(Icons.share_outlined),
          ),
          if (!widget.readOnly)
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
          if (!widget.readOnly)
            SizedBox(
              height: 62,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: SegmentedButton<WhiteboardMode>(
                      segments: const [
                        ButtonSegment(
                          value: WhiteboardMode.freeform,
                          icon: Icon(Icons.dashboard),
                          label: Text('Lavagna'),
                        ),
                        ButtonSegment(
                          value: WhiteboardMode.mindMap,
                          icon: Icon(Icons.account_tree),
                          label: Text('Mind Map'),
                        ),
                      ],
                      selected: {_document.mode},
                      onSelectionChanged: (value) => _setMode(value.first),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _document.mode == WhiteboardMode.mindMap
                        ? () => _addNode(kind: BoardNodeKind.mindNode)
                        : () => _addNode(),
                    tooltip: 'Aggiungi elemento',
                    icon: const Icon(Icons.add),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => setState(() {
                      _tool = _WhiteboardTool.navigate;
                      _connectMode = !_connectMode;
                      _connectFrom = null;
                      _workingPoints.clear();
                      _shapeStart = null;
                      _shapeEnd = null;
                    }),
                    isSelected: _connectMode,
                    tooltip: 'Collega due elementi',
                    icon: const Icon(Icons.timeline),
                  ),
                  if (_document.mode == WhiteboardMode.mindMap)
                    IconButton.filledTonal(
                      onPressed: () => setState(() {
                        _document = WhiteboardOps.autoLayoutMindMap(_document);
                      }),
                      tooltip: 'Layout automatico',
                      icon: const Icon(Icons.auto_awesome_mosaic),
                    ),
                  const VerticalDivider(),
                  _toolButton(
                    Icons.pan_tool,
                    'Naviga',
                    _WhiteboardTool.navigate,
                  ),
                  _toolButton(Icons.edit, 'Penna', _WhiteboardTool.pen),
                  _toolButton(
                    Icons.border_color,
                    'Evidenziatore',
                    _WhiteboardTool.highlighter,
                  ),
                  _toolButton(
                    Icons.auto_fix_normal,
                    'Gomma',
                    _WhiteboardTool.eraser,
                  ),
                  _toolButton(
                    Icons.show_chart,
                    'Linea',
                    _WhiteboardTool.line,
                  ),
                  _toolButton(
                    Icons.rectangle_outlined,
                    'Rettangolo',
                    _WhiteboardTool.rectangle,
                  ),
                  _toolButton(
                    Icons.circle_outlined,
                    'Ellisse',
                    _WhiteboardTool.ellipse,
                  ),
                  _toolButton(
                    Icons.arrow_forward,
                    'Freccia',
                    _WhiteboardTool.arrow,
                  ),
                  _toolButton(
                    Icons.text_fields,
                    'Testo',
                    _WhiteboardTool.text,
                  ),
                  PopupMenuButton<WhiteboardPaper>(
                    tooltip: 'Sfondo',
                    onSelected: _setPaper,
                    itemBuilder: (_) => WhiteboardPaper.values
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
                  IconButton.filledTonal(
                    onPressed: () {
                      final size = _lastViewportSize;
                      if (size != null) _centerViewport(size);
                    },
                    tooltip: 'Torna al centro',
                    icon: const Icon(Icons.center_focus_strong),
                  ),
                ],
              ),
            ),
          if (_connectMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                _connectFrom == null
                    ? 'Tocca il primo elemento da collegare.'
                    : 'Ora tocca il secondo elemento.',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          Expanded(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewportSize = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  _scheduleInitialCenter(viewportSize);
                  return InteractiveViewer(
                    transformationController: _viewport,
                    minScale: 0.2,
                    maxScale: 3.2,
                    boundaryMargin: const EdgeInsets.all(1200),
                    constrained: false,
                    panEnabled:
                        widget.readOnly || _tool == _WhiteboardTool.navigate,
                    scaleEnabled: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: widget.readOnly ||
                              _tool == _WhiteboardTool.navigate ||
                              _tool == _WhiteboardTool.text
                          ? null
                          : _drawStart,
                      onPanUpdate: widget.readOnly ||
                              _tool == _WhiteboardTool.navigate ||
                              _tool == _WhiteboardTool.text
                          ? null
                          : _drawUpdate,
                      onPanEnd: widget.readOnly ||
                              _tool == _WhiteboardTool.navigate ||
                              _tool == _WhiteboardTool.text
                          ? null
                          : _drawEnd,
                      onTapUp: widget.readOnly ||
                              _tool != _WhiteboardTool.text
                          ? null
                          : _tapCanvas,
                      child: RepaintBoundary(
                        key: _exportKey,
                        child: SizedBox(
                          width: _canvasSize,
                          height: _canvasSize,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _BoardPainter(
                                    document: _document,
                                    origin: _origin,
                                    working: _workingPoints,
                                    previewShape: _previewShape,
                                  ),
                                ),
                              ),
                              ..._document.nodes.map(_nodeWidget),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
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
    _WhiteboardTool tool,
  ) =>
      IconButton.filledTonal(
        onPressed: widget.readOnly ? null : () => _setTool(tool),
        tooltip: tooltip,
        isSelected: _tool == tool,
        icon: Icon(icon),
      );

  Widget _nodeWidget(BoardNode node) {
    final selected = _connectFrom == node.id;
    final canEditNode =
        !widget.readOnly && _tool == _WhiteboardTool.navigate;
    return Positioned(
      left: _origin + node.x,
      top: _origin + node.y,
      width: node.width.toDouble(),
      height: node.height.toDouble(),
      child: GestureDetector(
        onPanUpdate:
            canEditNode ? (details) => _moveNode(node, details) : null,
        onTap: canEditNode ? () => _nodeTap(node) : null,
        onLongPress: canEditNode
            ? () {
                if (_document.mode == WhiteboardMode.mindMap) {
                  _addNode(kind: BoardNodeKind.mindNode, parent: node);
                } else {
                  _editNode(node);
                }
              }
            : null,
        child: Card(
          color: Color(node.color),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              width: selected ? 4 : 1,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  node.kind == BoardNodeKind.mindNode
                      ? Icons.account_tree
                      : node.kind == BoardNodeKind.text
                          ? Icons.text_fields
                          : Icons.sticky_note_2,
                  size: 20,
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    node.text.isEmpty ? 'Elemento' : node.text,
                    overflow: TextOverflow.fade,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _contrast(Color(node.color)),
                        ),
                  ),
                ),
                if (_document.mode == WhiteboardMode.mindMap)
                  Text(
                    'Pressione lunga: aggiungi figlio',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _contrast(Color(node.color)),
                        ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  const _BoardPainter({
    required this.document,
    required this.origin,
    required this.working,
    required this.previewShape,
  });

  final WhiteboardDocument document;
  final double origin;
  final List<InkPoint> working;
  final BoardShape? previewShape;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white,
    );
    _paper(canvas, size);

    for (final stroke in document.strokes) {
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
    for (final shape in document.shapes) {
      _shape(canvas, shape);
    }
    if (previewShape != null) _shape(canvas, previewShape!);

    for (final text in document.texts) {
      final painter = TextPainter(
        text: TextSpan(
          text: text.text,
          style: TextStyle(
            color: Color(text.color),
            fontSize: text.size.toDouble(),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 800);
      painter.paint(
        canvas,
        Offset(origin + text.x, origin + text.y),
      );
    }

    for (final edge in document.edges) {
      BoardNode? from;
      BoardNode? to;
      for (final node in document.nodes) {
        if (node.id == edge.fromNodeId) from = node;
        if (node.id == edge.toNodeId) to = node;
      }
      if (from == null || to == null) continue;

      final start = Offset(
        origin + from.x + from.width / 2,
        origin + from.y + from.height / 2,
      );
      final end = Offset(
        origin + to.x + to.width / 2,
        origin + to.y + to.height / 2,
      );
      final paint = Paint()
        ..color = Color(edge.color)
        ..strokeWidth = edge.width.toDouble()
        ..style = PaintingStyle.stroke;
      canvas.drawLine(start, end, paint);

      if (edge.kind == BoardEdgeKind.arrow) {
        _arrowHead(canvas, start, end, paint, 24);
      }
    }
  }

  void _paper(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x1A455A64)
      ..strokeWidth = 1;
    switch (document.paper) {
      case WhiteboardPaper.plain:
        return;
      case WhiteboardPaper.ruled:
        for (double y = 0; y < size.height; y += 70) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
        return;
      case WhiteboardPaper.grid:
        for (double x = 0; x < size.width; x += 80) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        }
        for (double y = 0; y < size.height; y += 80) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
        return;
      case WhiteboardPaper.dots:
        final dot = Paint()..color = const Color(0x33455A64);
        for (double x = 40; x < size.width; x += 40) {
          for (double y = 40; y < size.height; y += 40) {
            canvas.drawCircle(Offset(x, y), 1.8, dot);
          }
        }
        return;
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
        origin + stroke.points.first.x,
        origin + stroke.points.first.y,
      );
    for (final point in stroke.points.skip(1)) {
      path.lineTo(origin + point.x, origin + point.y);
    }
    canvas.drawPath(path, paint);
  }

  void _shape(Canvas canvas, BoardShape shape) {
    final paint = Paint()
      ..color = Color(shape.color)
      ..strokeWidth = shape.width.toDouble()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final a = Offset(origin + shape.x1, origin + shape.y1);
    final b = Offset(origin + shape.x2, origin + shape.y2);
    switch (shape.kind) {
      case BoardShapeKind.line:
        canvas.drawLine(a, b, paint);
        break;
      case BoardShapeKind.rectangle:
        canvas.drawRect(Rect.fromPoints(a, b), paint);
        break;
      case BoardShapeKind.ellipse:
        canvas.drawOval(Rect.fromPoints(a, b), paint);
        break;
      case BoardShapeKind.arrow:
        canvas.drawLine(a, b, paint);
        _arrowHead(canvas, a, b, paint, 28);
        break;
    }
  }

  void _arrowHead(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    double length,
  ) {
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final left = Offset(
      end.dx - length * math.cos(angle - math.pi / 6),
      end.dy - length * math.sin(angle - math.pi / 6),
    );
    final right = Offset(
      end.dx - length * math.cos(angle + math.pi / 6),
      end.dy - length * math.sin(angle + math.pi / 6),
    );
    canvas.drawLine(end, left, paint);
    canvas.drawLine(end, right, paint);
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) => true;
}

Color _contrast(Color background) {
  final luminance = background.computeLuminance();
  return luminance > 0.5 ? Colors.black87 : Colors.white;
}


String _paperLabel(WhiteboardPaper paper) => switch (paper) {
      WhiteboardPaper.plain => 'Bianco',
      WhiteboardPaper.ruled => 'Righe',
      WhiteboardPaper.grid => 'Griglia',
      WhiteboardPaper.dots => 'Puntini',
    };
