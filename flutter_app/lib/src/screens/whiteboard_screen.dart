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

const _inkPalette = <int>[
  0xFF111111,
  0xFF455A64,
  0xFFE53935,
  0xFFFF8F00,
  0xFFFFD54F,
  0xFF43A047,
  0xFF00897B,
  0xFF1E88E5,
  0xFF5E35B1,
  0xFFD81B60,
];

class _TextEditResult {
  const _TextEditResult({
    required this.text,
    required this.color,
    required this.size,
    this.delete = false,
  });

  final String text;
  final int color;
  final int size;
  final bool delete;
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
  static const _minCanvasHalfExtent = 6000.0;
  static const _canvasGrowth = 4000.0;
  static const _canvasContentMargin = 1600.0;
  static const _historyLimit = 50;

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

  double _canvasHalfExtent = _minCanvasHalfExtent;
  double get _canvasSize => _canvasHalfExtent * 2;
  double get _origin => _canvasHalfExtent;

  _WhiteboardTool _tool = _WhiteboardTool.navigate;
  final List<InkPoint> _workingPoints = [];
  int _workingVersion = 0;
  Offset? _shapeStart;
  Offset? _shapeEnd;

  final List<WhiteboardDocument> _undoStack = [];
  final List<WhiteboardDocument> _redoStack = [];
  WhiteboardDocument? _gestureHistoryStart;
  bool _gestureChanged = false;

  int _inkColor = 0xFF111111;
  int _highlighterColor = 0xFFFFD54F;
  int _penWidth = 6;
  int _highlighterWidth = 24;
  int _shapeWidth = 5;

  bool _fingerDraw = true;
  bool _stylusInContact = false;
  int? _stylusPointer;
  double _pointerPressure = 1;

  final Map<String, Rect> _strokeBounds = {};

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
    _canvasHalfExtent = _targetHalfExtent(_document);
    _rebuildStrokeBounds();
  }

  @override
  void dispose() {
    _title.dispose();
    _viewport.dispose();
    super.dispose();
  }

  void _centerViewport(Size viewportSize) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) return;
    final dx = viewportSize.width / 2 - _origin;
    final dy = viewportSize.height / 2 - _origin;
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

  double _targetHalfExtent(WhiteboardDocument document) {
    var extent = 0.0;

    void include(double x, double y) {
      extent = math.max(extent, math.max(x.abs(), y.abs()));
    }

    for (final node in document.nodes) {
      include(node.x.toDouble(), node.y.toDouble());
      include(
        (node.x + node.width).toDouble(),
        (node.y + node.height).toDouble(),
      );
    }
    for (final stroke in document.strokes) {
      for (final point in stroke.points) {
        include(point.x.toDouble(), point.y.toDouble());
      }
    }
    for (final shape in document.shapes) {
      include(shape.x1.toDouble(), shape.y1.toDouble());
      include(shape.x2.toDouble(), shape.y2.toDouble());
    }
    for (final text in document.texts) {
      include(text.x.toDouble(), text.y.toDouble());
      include(
        text.x + 800,
        text.y + math.max(120, text.size * 3).toDouble(),
      );
    }

    final required = math.max(
      _minCanvasHalfExtent,
      extent + _canvasContentMargin,
    );
    return (required / _canvasGrowth).ceil() * _canvasGrowth;
  }

  void _growCanvasToFit(WhiteboardDocument document) {
    final target = _targetHalfExtent(document);
    if (target <= _canvasHalfExtent) return;
    final delta = target - _canvasHalfExtent;
    setState(() => _canvasHalfExtent = target);
    if (!_initialViewportCentered) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final matrix = _viewport.value.clone();
      final scale = matrix.getMaxScaleOnAxis();
      matrix.storage[12] -= delta * scale;
      matrix.storage[13] -= delta * scale;
      _viewport.value = matrix;
    });
  }

  void _pushUndo(WhiteboardDocument snapshot) {
    if (_undoStack.length >= _historyLimit) {
      _undoStack.removeAt(0);
    }
    _undoStack.add(snapshot);
    _redoStack.clear();
  }

  bool _setDocument(
    WhiteboardDocument next, {
    bool recordHistory = true,
    bool ensureCanvas = true,
  }) {
    try {
      WhiteboardRules.validate(next);
    } catch (error) {
      setState(() => _error = userErrorText(error));
      return false;
    }
    if (identical(next, _document)) return true;

    final previous = _document;
    if (recordHistory) _pushUndo(previous);
    setState(() {
      _document = next;
      _error = null;
    });
    _rebuildStrokeBounds();
    if (ensureCanvas) _growCanvasToFit(next);
    return true;
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final previous = _undoStack.removeLast();
    if (_redoStack.length >= _historyLimit) {
      _redoStack.removeAt(0);
    }
    _redoStack.add(_document);
    setState(() {
      _document = previous;
      _workingPoints.clear();
      _workingVersion++;
      _shapeStart = null;
      _shapeEnd = null;
      _error = null;
    });
    _rebuildStrokeBounds();
    _growCanvasToFit(previous);
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final next = _redoStack.removeLast();
    if (_undoStack.length >= _historyLimit) {
      _undoStack.removeAt(0);
    }
    _undoStack.add(_document);
    setState(() {
      _document = next;
      _workingPoints.clear();
      _workingVersion++;
      _shapeStart = null;
      _shapeEnd = null;
      _error = null;
    });
    _rebuildStrokeBounds();
    _growCanvasToFit(next);
  }

  void _beginGestureHistory() {
    _gestureHistoryStart ??= _document;
    _gestureChanged = false;
  }

  void _markGestureChanged() {
    _gestureChanged = true;
  }

  void _finishGestureHistory() {
    final snapshot = _gestureHistoryStart;
    if (snapshot != null && _gestureChanged) {
      _pushUndo(snapshot);
      _growCanvasToFit(_document);
    }
    _gestureHistoryStart = null;
    _gestureChanged = false;
  }

  Rect _boundsForStroke(InkStroke stroke) {
    final cached = _strokeBounds[stroke.id];
    if (cached != null) return cached;
    var left = stroke.points.first.x.toDouble();
    var right = left;
    var top = stroke.points.first.y.toDouble();
    var bottom = top;
    for (final point in stroke.points.skip(1)) {
      left = math.min(left, point.x.toDouble());
      right = math.max(right, point.x.toDouble());
      top = math.min(top, point.y.toDouble());
      bottom = math.max(bottom, point.y.toDouble());
    }
    final padding = stroke.width / 2 + 2;
    final bounds = Rect.fromLTRB(
      left - padding,
      top - padding,
      right + padding,
      bottom + padding,
    );
    _strokeBounds[stroke.id] = bounds;
    return bounds;
  }

  void _rebuildStrokeBounds() {
    _strokeBounds
      ..clear()
      ..addEntries(
        _document.strokes.map(
          (stroke) => MapEntry(stroke.id, _computeStrokeBounds(stroke)),
        ),
      );
  }

  Rect _computeStrokeBounds(InkStroke stroke) {
    var left = stroke.points.first.x.toDouble();
    var right = left;
    var top = stroke.points.first.y.toDouble();
    var bottom = top;
    for (final point in stroke.points.skip(1)) {
      left = math.min(left, point.x.toDouble());
      right = math.max(right, point.x.toDouble());
      top = math.min(top, point.y.toDouble());
      bottom = math.max(bottom, point.y.toDouble());
    }
    final padding = stroke.width / 2 + 2;
    return Rect.fromLTRB(
      left - padding,
      top - padding,
      right + padding,
      bottom + padding,
    );
  }

  bool _isStylus(ui.PointerDeviceKind kind) =>
      kind == ui.PointerDeviceKind.stylus ||
      kind == ui.PointerDeviceKind.invertedStylus;

  double _normalizedPressure(PointerEvent event) {
    final range = event.pressureMax - event.pressureMin;
    if (range <= 0) return 1;
    return ((event.pressure - event.pressureMin) / range).clamp(0.05, 1.0);
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointerPressure = _normalizedPressure(event);
    if (!_isStylus(event.kind)) return;
    _stylusPointer = event.pointer;
    if (!_stylusInContact || _fingerDraw) {
      setState(() {
        _stylusInContact = true;
        _fingerDraw = false;
      });
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_stylusPointer == null || event.pointer == _stylusPointer) {
      _pointerPressure = _normalizedPressure(event);
    }
  }

  void _onPointerEnd(PointerEvent event) {
    if (event.pointer != _stylusPointer) return;
    _stylusPointer = null;
    _pointerPressure = 1;
    if (_stylusInContact) {
      setState(() => _stylusInContact = false);
    }
  }

  Set<ui.PointerDeviceKind> get _drawingDevices => {
        ui.PointerDeviceKind.stylus,
        ui.PointerDeviceKind.invertedStylus,
        ui.PointerDeviceKind.mouse,
        if (_fingerDraw) ui.PointerDeviceKind.touch,
      };

  int get _workingColor {
    if (_tool == _WhiteboardTool.highlighter) {
      return (_highlighterColor & 0x00FFFFFF) | 0x66000000;
    }
    return _inkColor;
  }

  int get _workingWidth => switch (_tool) {
        _WhiteboardTool.highlighter => _highlighterWidth,
        _WhiteboardTool.line ||
        _WhiteboardTool.rectangle ||
        _WhiteboardTool.ellipse ||
        _WhiteboardTool.arrow =>
          _shapeWidth,
        _ => _penWidth,
      };

  void _setTool(_WhiteboardTool tool) {
    setState(() {
      _tool = tool;
      _connectMode = false;
      _connectFrom = null;
      _workingPoints.clear();
      _workingVersion++;
      _shapeStart = null;
      _shapeEnd = null;
    });
  }

  void _setPaper(WhiteboardPaper paper) {
    if (paper == _document.paper) return;
    _setDocument(_document.copyWith(paper: paper));
  }

  InkPoint _boardPoint(Offset local) {
    final limit = WhiteboardRules.maxCoordinate;
    final pressure = (_pointerPressure * 1000).round().clamp(0, 1000);
    return InkPoint(
      (local.dx - _origin).round().clamp(-limit, limit).toInt(),
      (local.dy - _origin).round().clamp(-limit, limit).toInt(),
      pressure,
    );
  }

  void _drawStart(DragStartDetails details) {
    final point = _boardPoint(details.localPosition);
    if (_tool == _WhiteboardTool.pen || _tool == _WhiteboardTool.highlighter) {
      _workingPoints
        ..clear()
        ..add(point);
      setState(() => _workingVersion++);
      return;
    }
    if (_tool == _WhiteboardTool.eraser) {
      _beginGestureHistory();
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
    if (_tool == _WhiteboardTool.pen || _tool == _WhiteboardTool.highlighter) {
      _workingPoints.add(point);
      setState(() => _workingVersion++);
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
        color: _workingColor,
        width: _workingWidth,
        marker: _tool == _WhiteboardTool.highlighter,
        points: [..._workingPoints],
      );
      final next = _document.copyWith(
        strokes: [..._document.strokes, stroke],
      );
      final accepted = _setDocument(next);
      setState(() {
        _workingPoints.clear();
        _workingVersion++;
      });
      if (!accepted) {
        _strokeBounds.remove(stroke.id);
      }
      return;
    }

    if (_tool == _WhiteboardTool.eraser) {
      _finishGestureHistory();
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
        _setDocument(
          _document.copyWith(
            shapes: [
              ..._document.shapes,
              BoardShape(
                kind: kind,
                color: _inkColor,
                width: _shapeWidth,
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
    if (mounted) setState(() {});
  }

  void _drawCancel() {
    if (_tool == _WhiteboardTool.eraser) {
      _finishGestureHistory();
    }
    setState(() {
      _workingPoints.clear();
      _workingVersion++;
      _shapeStart = null;
      _shapeEnd = null;
    });
  }

  Future<_TextEditResult?> _showTextDialog({SketchText? source}) async {
    final controller = TextEditingController(text: source?.text ?? '');
    var color = source?.color ?? _inkColor;
    var size = (source?.size ?? 32).toDouble();

    final result = await showDialog<_TextEditResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(source == null ? 'Inserisci testo' : 'Modifica testo'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 4000,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Testo'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Colore',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _inkPalette
                      .map(
                        (value) => InkWell(
                          onTap: () => setDialogState(() => color = value),
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Color(value),
                              shape: BoxShape.circle,
                              border: Border.all(
                                width: color == value ? 3 : 1,
                                color: color == value
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Dimensione'),
                    Expanded(
                      child: Slider(
                        value: size,
                        min: 16,
                        max: 72,
                        divisions: 14,
                        label: size.round().toString(),
                        onChanged: (value) =>
                            setDialogState(() => size = value),
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text('${size.round()}'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            if (source != null)
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  _TextEditResult(
                    text: source.text,
                    color: source.color,
                    size: source.size,
                    delete: true,
                  ),
                ),
                child: Text(
                  'Elimina',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _TextEditResult(
                  text: controller.text.trim(),
                  color: color,
                  size: size.round(),
                ),
              ),
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _tapCanvas(TapUpDetails details) async {
    if (_tool != _WhiteboardTool.text) return;
    final point = _boardPoint(details.localPosition);
    final value = await _showTextDialog();
    if (value == null || value.delete || value.text.isEmpty || !mounted) return;
    _setDocument(
      _document.copyWith(
        texts: [
          ..._document.texts,
          SketchText(
            text: value.text,
            color: value.color,
            x: point.x,
            y: point.y,
            size: value.size,
          ),
        ],
      ),
    );
  }

  Future<void> _editText(SketchText text) async {
    final value = await _showTextDialog(source: text);
    if (value == null || !mounted) return;
    if (value.delete) {
      _setDocument(
        _document.copyWith(
          texts: _document.texts.where((item) => item.id != text.id).toList(),
        ),
      );
      return;
    }
    if (value.text.isEmpty) return;
    _setDocument(
      _document.copyWith(
        texts: _document.texts
            .map(
              (item) => item.id == text.id
                  ? item.copyWith(
                      text: value.text,
                      color: value.color,
                      size: value.size,
                    )
                  : item,
            )
            .toList(),
      ),
    );
  }

  void _moveText(SketchText text, DragUpdateDetails details) {
    final updated = text.copyWith(
      x: text.x + details.delta.dx.round(),
      y: text.y + details.delta.dy.round(),
    );
    if (_setDocument(
      _document.copyWith(
        texts: _document.texts
            .map((item) => item.id == text.id ? updated : item)
            .toList(),
      ),
      recordHistory: false,
      ensureCanvas: false,
    )) {
      _markGestureChanged();
    }
  }

  void _eraseInk(InkPoint point) {
    const radius = 38.0;
    final hitRect = Rect.fromCircle(
      center: Offset(point.x.toDouble(), point.y.toDouble()),
      radius: radius,
    );

    bool hitsStroke(InkStroke stroke) {
      if (!_boundsForStroke(stroke).overlaps(hitRect)) return false;
      for (final candidate in stroke.points) {
        final dx = candidate.x - point.x;
        final dy = candidate.y - point.y;
        final limit = radius + stroke.width / 2;
        if (dx * dx + dy * dy <= limit * limit) return true;
      }
      return false;
    }

    final strokes =
        _document.strokes.where((stroke) => !hitsStroke(stroke)).toList();

    final shapes = _document.shapes.where((shape) {
      final rect = Rect.fromPoints(
        Offset(shape.x1.toDouble(), shape.y1.toDouble()),
        Offset(shape.x2.toDouble(), shape.y2.toDouble()),
      ).inflate(radius + shape.width / 2);
      return !rect.contains(Offset(point.x.toDouble(), point.y.toDouble()));
    }).toList();

    final texts = _document.texts.where((text) {
      final approxWidth = math.min(
        800.0,
        math.max(120.0, text.text.length * text.size * 0.55),
      );
      final rect = Rect.fromLTWH(
        text.x.toDouble(),
        text.y.toDouble(),
        approxWidth,
        math.max(60.0, text.size * 2.5),
      ).inflate(radius);
      return !rect.contains(Offset(point.x.toDouble(), point.y.toDouble()));
    }).toList();

    final changed = strokes.length != _document.strokes.length ||
        shapes.length != _document.shapes.length ||
        texts.length != _document.texts.length;
    if (!changed) return;

    if (_setDocument(
      _document.copyWith(
        strokes: strokes,
        shapes: shapes,
        texts: texts,
      ),
      recordHistory: false,
      ensureCanvas: false,
    )) {
      _markGestureChanged();
    }
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
      color: _inkColor,
      width: _shapeWidth,
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
    final pixelRatio = (4096 / _canvasSize).clamp(0.08, 1.0);
    final image = await boundary.toImage(pixelRatio: pixelRatio);
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

    final next = parent != null && _document.mode == WhiteboardMode.mindMap
        ? WhiteboardOps.addMindChild(
            _document,
            parent.id,
            text: value.isEmpty ? 'Nuova idea' : value,
          )
        : WhiteboardOps.addNode(
            _document,
            kind: kind,
            text: value,
            x: 0,
            y: 0,
          );
    _setDocument(next);
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
    _setDocument(
      value == '__DELETE__'
          ? WhiteboardOps.deleteNode(_document, node.id)
          : WhiteboardOps.updateNode(
              _document,
              node.copyWith(text: value),
            ),
    );
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
    final next = WhiteboardOps.connect(
      _document,
      _connectFrom!,
      node.id,
    );
    _setDocument(next);
    setState(() {
      _connectFrom = null;
      _connectMode = false;
    });
  }

  void _moveNode(BoardNode node, DragUpdateDetails details) {
    final updated = node.copyWith(
      x: node.x + details.delta.dx.round(),
      y: node.y + details.delta.dy.round(),
    );
    if (_setDocument(
      WhiteboardOps.updateNode(_document, updated),
      recordHistory: false,
      ensureCanvas: false,
    )) {
      _markGestureChanged();
    }
  }

  void _setMode(WhiteboardMode mode) {
    if (mode == _document.mode) return;
    final next = mode == WhiteboardMode.mindMap && _document.nodes.isEmpty
        ? _document.copyWith(
            mode: mode,
            nodes: WhiteboardOps.empty(mode).nodes,
          )
        : _document.copyWith(mode: mode);
    _setDocument(next);
    setState(() {
      _connectMode = false;
      _connectFrom = null;
    });
  }

  bool get _isShapeTool =>
      _tool == _WhiteboardTool.line ||
      _tool == _WhiteboardTool.rectangle ||
      _tool == _WhiteboardTool.ellipse ||
      _tool == _WhiteboardTool.arrow;

  bool get _isInkTool =>
      _tool == _WhiteboardTool.pen ||
      _tool == _WhiteboardTool.highlighter ||
      _isShapeTool;

  int get _currentBaseColor =>
      _tool == _WhiteboardTool.highlighter ? _highlighterColor : _inkColor;

  List<int> get _widthOptions {
    if (_tool == _WhiteboardTool.highlighter) {
      return const [12, 18, 24, 32, 40];
    }
    if (_isShapeTool) return const [2, 4, 5, 8, 12];
    return const [2, 4, 6, 10, 14];
  }

  int get _currentWidth {
    if (_tool == _WhiteboardTool.highlighter) return _highlighterWidth;
    if (_isShapeTool) return _shapeWidth;
    return _penWidth;
  }

  void _setCurrentColor(int value) {
    setState(() {
      if (_tool == _WhiteboardTool.highlighter) {
        _highlighterColor = value;
      } else {
        _inkColor = value;
      }
    });
  }

  void _setCurrentWidth(int value) {
    setState(() {
      if (_tool == _WhiteboardTool.highlighter) {
        _highlighterWidth = value;
      } else if (_isShapeTool) {
        _shapeWidth = value;
      } else {
        _penWidth = value;
      }
    });
  }

  Widget _colorControl() => PopupMenuButton<int>(
        tooltip: 'Colore',
        onSelected: _setCurrentColor,
        itemBuilder: (_) => _inkPalette
            .map(
              (value) => PopupMenuItem(
                value: value,
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Color(value),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      value == _currentBaseColor ? 'Selezionato' : 'Colore',
                    ),
                  ],
                ),
              ),
            )
            .toList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Color(_currentBaseColor),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
          ),
        ),
      );

  Widget _widthControl() => PopupMenuButton<int>(
        tooltip: 'Spessore',
        onSelected: _setCurrentWidth,
        itemBuilder: (_) => _widthOptions
            .map(
              (value) => PopupMenuItem(
                value: value,
                child: Row(
                  children: [
                    SizedBox(
                      width: 42,
                      child: Center(
                        child: Container(
                          width: 34,
                          height: value.toDouble().clamp(2, 16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.onSurface,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('$value px'),
                  ],
                ),
              ),
            )
            .toList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Center(
            child: Text(
              '$_currentWidth px',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
      );

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
                      onTapUp: widget.readOnly || _tool != _WhiteboardTool.text
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
    final canEditNode = !widget.readOnly && _tool == _WhiteboardTool.navigate;
    return Positioned(
      left: _origin + node.x,
      top: _origin + node.y,
      width: node.width.toDouble(),
      height: node.height.toDouble(),
      child: GestureDetector(
        onPanUpdate: canEditNode ? (details) => _moveNode(node, details) : null,
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
