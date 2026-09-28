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
  select,
  pen,
  highlighter,
  eraser,
  line,
  rectangle,
  ellipse,
  arrow,
  text,
}

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
  static const _snapGrid = 40;

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
  Offset? _lassoStart;
  Offset? _lassoEnd;

  final Set<String> _selectedNodeIds = {};
  final Set<String> _selectedTextIds = {};
  final Set<String> _draggedNodeIds = {};
  final Set<String> _draggedTextIds = {};
  bool _snapToGrid = false;

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
  bool _objectPointerActive = false;
  int? _objectPointer;
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

  void _expandCanvasHalf(double target) {
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

  void _growCanvasToFit(WhiteboardDocument document) {
    _expandCanvasHalf(_targetHalfExtent(document));
  }

  void _growCanvasForViewport() {
    final size = _lastViewportSize;
    if (size == null || size.isEmpty) return;
    final corners = <Offset>[
      _viewport.toScene(Offset.zero),
      _viewport.toScene(Offset(size.width, 0)),
      _viewport.toScene(Offset(0, size.height)),
      _viewport.toScene(Offset(size.width, size.height)),
    ];
    var extent = 0.0;
    for (final scene in corners) {
      final world = scene - Offset(_origin, _origin);
      extent = math.max(extent, math.max(world.dx.abs(), world.dy.abs()));
    }
    if (extent < _canvasHalfExtent - _canvasContentMargin / 2) return;
    final required = extent + _canvasContentMargin;
    final target = (required / _canvasGrowth).ceil() * _canvasGrowth;
    _expandCanvasHalf(target);
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
    bool validate = true,
    bool rebuildStrokeBounds = true,
  }) {
    if (validate) {
      try {
        WhiteboardRules.validate(next);
      } catch (error) {
        setState(() => _error = userErrorText(error));
        return false;
      }
    }
    if (identical(next, _document)) return true;

    final previous = _document;
    if (recordHistory) _pushUndo(previous);
    setState(() {
      _document = next;
      _error = null;
    });
    if (rebuildStrokeBounds) _rebuildStrokeBounds();
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

  bool get _selectionMode => _tool == _WhiteboardTool.select;

  Rect _nodeWorldRect(BoardNode node) => Rect.fromLTWH(
        node.x.toDouble(),
        node.y.toDouble(),
        node.width.toDouble(),
        node.height.toDouble(),
      );

  Rect _textWorldRect(SketchText text) => Rect.fromLTWH(
        text.x.toDouble(),
        text.y.toDouble(),
        math.min(
          800.0,
          math.max(140.0, text.text.length * text.size * 0.55),
        ),
        math.max(72.0, text.size * 2.8),
      );

  void _clearSelection() {
    if (_selectedNodeIds.isEmpty && _selectedTextIds.isEmpty) return;
    setState(() {
      _selectedNodeIds.clear();
      _selectedTextIds.clear();
    });
  }

  void _selectAllObjects() {
    setState(() {
      _selectedNodeIds
        ..clear()
        ..addAll(_document.nodes.map((node) => node.id));
      _selectedTextIds
        ..clear()
        ..addAll(_document.texts.map((text) => text.id));
    });
  }

  void _toggleNodeSelection(BoardNode node) {
    setState(() {
      if (!_selectedNodeIds.remove(node.id)) {
        _selectedNodeIds.add(node.id);
      }
    });
  }

  void _toggleTextSelection(SketchText text) {
    setState(() {
      if (!_selectedTextIds.remove(text.id)) {
        _selectedTextIds.add(text.id);
      }
    });
  }

  void _onNodePointerDown(BoardNode node, PointerDownEvent event) {
    if (widget.readOnly ||
        (_tool != _WhiteboardTool.navigate && !_selectionMode)) {
      return;
    }
    _objectPointer = event.pointer;
    final moveSelection = _selectionMode && _selectedNodeIds.contains(node.id);
    _draggedNodeIds
      ..clear()
      ..addAll(moveSelection ? _selectedNodeIds : <String>{node.id});
    _draggedTextIds
      ..clear()
      ..addAll(moveSelection ? _selectedTextIds : const <String>{});
    _beginGestureHistory();
    if (!_objectPointerActive) {
      setState(() => _objectPointerActive = true);
    }
  }

  void _onTextPointerDown(SketchText text, PointerDownEvent event) {
    if (widget.readOnly ||
        (_tool != _WhiteboardTool.navigate && !_selectionMode)) {
      return;
    }
    _objectPointer = event.pointer;
    final moveSelection = _selectionMode && _selectedTextIds.contains(text.id);
    _draggedTextIds
      ..clear()
      ..addAll(moveSelection ? _selectedTextIds : <String>{text.id});
    _draggedNodeIds
      ..clear()
      ..addAll(moveSelection ? _selectedNodeIds : const <String>{});
    _beginGestureHistory();
    if (!_objectPointerActive) {
      setState(() => _objectPointerActive = true);
    }
  }

  int _snapValue(int value) => ((value / _snapGrid).round().clamp(
                -WhiteboardRules.maxCoordinate ~/ _snapGrid,
                WhiteboardRules.maxCoordinate ~/ _snapGrid,
              ) *
          _snapGrid)
      .toInt();

  void _snapDraggedObjects() {
    if (!_snapToGrid || (_draggedNodeIds.isEmpty && _draggedTextIds.isEmpty)) {
      return;
    }
    final nextNodes = _document.nodes
        .map(
          (node) => _draggedNodeIds.contains(node.id)
              ? node.copyWith(
                  x: _snapValue(node.x),
                  y: _snapValue(node.y),
                )
              : node,
        )
        .toList();
    final nextTexts = _document.texts
        .map(
          (text) => _draggedTextIds.contains(text.id)
              ? text.copyWith(
                  x: _snapValue(text.x),
                  y: _snapValue(text.y),
                )
              : text,
        )
        .toList();
    _setDocument(
      _document.copyWith(nodes: nextNodes, texts: nextTexts),
      recordHistory: false,
      ensureCanvas: false,
      validate: false,
      rebuildStrokeBounds: false,
    );
    _markGestureChanged();
  }

  void _onObjectPointerEnd(PointerEvent event) {
    if (event.pointer != _objectPointer) return;
    _objectPointer = null;
    _snapDraggedObjects();
    _finishGestureHistory();
    _draggedNodeIds.clear();
    _draggedTextIds.clear();
    if (_objectPointerActive) {
      setState(() => _objectPointerActive = false);
    }
  }

  void _selectLasso(Rect worldRect) {
    final normalized = Rect.fromLTRB(
      math.min(worldRect.left, worldRect.right),
      math.min(worldRect.top, worldRect.bottom),
      math.max(worldRect.left, worldRect.right),
      math.max(worldRect.top, worldRect.bottom),
    );
    setState(() {
      _selectedNodeIds
        ..clear()
        ..addAll(
          _document.nodes
              .where((node) => _nodeWorldRect(node).overlaps(normalized))
              .map((node) => node.id),
        );
      _selectedTextIds
        ..clear()
        ..addAll(
          _document.texts
              .where((text) => _textWorldRect(text).overlaps(normalized))
              .map((text) => text.id),
        );
    });
  }

  void _duplicateSelection() {
    if (_selectedNodeIds.isEmpty && _selectedTextIds.isEmpty) return;
    const offset = 48;
    final idMap = <String, String>{};
    final duplicates = <BoardNode>[];

    for (final node in _document.nodes) {
      if (!_selectedNodeIds.contains(node.id)) continue;
      final clone = BoardNode(
        kind: node.kind,
        text: node.text,
        x: node.x + offset,
        y: node.y + offset,
        width: node.width,
        height: node.height,
        color: node.color,
        linkedNoteId: node.linkedNoteId,
      );
      idMap[node.id] = clone.id;
      duplicates.add(clone);
    }

    final duplicateTexts = <SketchText>[];
    for (final source in _document.texts) {
      if (!_selectedTextIds.contains(source.id)) continue;
      duplicateTexts.add(
        SketchText(
          text: source.text,
          color: source.color,
          x: source.x + offset,
          y: source.y + offset,
          size: source.size,
        ),
      );
    }

    final duplicateEdges = _document.edges
        .where(
          (edge) =>
              idMap.containsKey(edge.fromNodeId) &&
              idMap.containsKey(edge.toNodeId),
        )
        .map(
          (edge) => BoardEdge(
            fromNodeId: idMap[edge.fromNodeId]!,
            toNodeId: idMap[edge.toNodeId]!,
            kind: edge.kind,
            color: edge.color,
            width: edge.width,
            label: edge.label,
          ),
        )
        .toList();

    final next = _document.copyWith(
      nodes: [..._document.nodes, ...duplicates],
      texts: [..._document.texts, ...duplicateTexts],
      edges: [..._document.edges, ...duplicateEdges],
    );
    if (!_setDocument(next)) return;
    setState(() {
      _selectedNodeIds
        ..clear()
        ..addAll(duplicates.map((node) => node.id));
      _selectedTextIds
        ..clear()
        ..addAll(duplicateTexts.map((text) => text.id));
    });
  }

  void _deleteSelection() {
    if (_selectedNodeIds.isEmpty && _selectedTextIds.isEmpty) return;
    final removedNodes = Set<String>.from(_selectedNodeIds);
    final next = _document.copyWith(
      nodes: _document.nodes
          .where((node) => !removedNodes.contains(node.id))
          .toList(),
      texts: _document.texts
          .where((text) => !_selectedTextIds.contains(text.id))
          .toList(),
      edges: _document.edges
          .where(
            (edge) =>
                !removedNodes.contains(edge.fromNodeId) &&
                !removedNodes.contains(edge.toNodeId),
          )
          .toList(),
    );
    if (!_setDocument(next)) return;
    _clearSelection();
  }

  void _resizeSelection(int delta) {
    if (_selectedNodeIds.isEmpty) return;
    final nextNodes = _document.nodes.map((node) {
      if (!_selectedNodeIds.contains(node.id)) return node;
      final width = (node.width + delta).clamp(120, 720).toInt();
      final height =
          (node.height + (delta * 0.65).round()).clamp(80, 520).toInt();
      return node.copyWith(
        x: node.x - ((width - node.width) / 2).round(),
        y: node.y - ((height - node.height) / 2).round(),
        width: width,
        height: height,
      );
    }).toList();
    _setDocument(_document.copyWith(nodes: nextNodes));
  }

  Set<ui.PointerDeviceKind> get _drawingDevices => {
        ui.PointerDeviceKind.stylus,
        ui.PointerDeviceKind.invertedStylus,
        ui.PointerDeviceKind.mouse,
        if (_fingerDraw) ui.PointerDeviceKind.touch,
      };

  Set<ui.PointerDeviceKind> get _canvasGestureDevices => _selectionMode
      ? {
          ui.PointerDeviceKind.touch,
          ui.PointerDeviceKind.stylus,
          ui.PointerDeviceKind.invertedStylus,
          ui.PointerDeviceKind.mouse,
        }
      : _drawingDevices;

  int get _workingColor {
    if (_tool == _WhiteboardTool.highlighter) {
      return VisualInkDefaults.translucentMarker(_highlighterColor);
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
      _lassoStart = null;
      _lassoEnd = null;
      if (tool != _WhiteboardTool.select) {
        _selectedNodeIds.clear();
        _selectedTextIds.clear();
      }
    });
  }

  Rect? get _lassoWorldRect {
    final start = _lassoStart;
    final end = _lassoEnd;
    if (start == null || end == null) return null;
    return Rect.fromPoints(start, end);
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
    if (_selectionMode) {
      final offset = Offset(point.x.toDouble(), point.y.toDouble());
      setState(() {
        _lassoStart = offset;
        _lassoEnd = offset;
      });
      return;
    }
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
    if (_selectionMode && _lassoStart != null) {
      setState(() {
        _lassoEnd = Offset(point.x.toDouble(), point.y.toDouble());
      });
      return;
    }
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
    if (_selectionMode && _lassoWorldRect != null) {
      final rect = _lassoWorldRect!;
      _selectLasso(rect);
      setState(() {
        _lassoStart = null;
        _lassoEnd = null;
      });
      return;
    }

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
      _lassoStart = null;
      _lassoEnd = null;
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
                  children: VisualInkDefaults.palette
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

  void _moveDraggedByDelta(Offset delta) {
    if (_draggedNodeIds.isEmpty && _draggedTextIds.isEmpty) return;
    final limit = WhiteboardRules.maxCoordinate;
    final dx = delta.dx.round();
    final dy = delta.dy.round();

    final nextNodes = _document.nodes
        .map(
          (node) => _draggedNodeIds.contains(node.id)
              ? node.copyWith(
                  x: (node.x + dx).clamp(-limit, limit).toInt(),
                  y: (node.y + dy).clamp(-limit, limit).toInt(),
                )
              : node,
        )
        .toList();
    final nextTexts = _document.texts
        .map(
          (text) => _draggedTextIds.contains(text.id)
              ? text.copyWith(
                  x: (text.x + dx).clamp(-limit, limit).toInt(),
                  y: (text.y + dy).clamp(-limit, limit).toInt(),
                )
              : text,
        )
        .toList();

    if (_setDocument(
      _document.copyWith(nodes: nextNodes, texts: nextTexts),
      recordHistory: false,
      ensureCanvas: false,
      validate: false,
      rebuildStrokeBounds: false,
    )) {
      _markGestureChanged();
    }
  }

  void _moveTextByDelta(SketchText text, Offset delta) {
    if (!_draggedTextIds.contains(text.id)) return;
    _moveDraggedByDelta(delta);
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
      validate: false,
      rebuildStrokeBounds: false,
    )) {
      final liveIds = strokes.map((stroke) => stroke.id).toSet();
      _strokeBounds.removeWhere((id, _) => !liveIds.contains(id));
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

  void _moveNodeByDelta(BoardNode node, Offset delta) {
    if (!_draggedNodeIds.contains(node.id)) return;
    _moveDraggedByDelta(delta);
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
      return VisualInkDefaults.highlighterWidths;
    }
    if (_isShapeTool) return VisualInkDefaults.shapeWidths;
    return VisualInkDefaults.penWidths;
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
        itemBuilder: (_) => VisualInkDefaults.palette
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

  Rect _overviewBounds() {
    Rect? bounds;

    void include(Rect rect) {
      final current = bounds;
      if (current == null) {
        bounds = rect;
        return;
      }
      bounds = Rect.fromLTRB(
        math.min(current.left, rect.left),
        math.min(current.top, rect.top),
        math.max(current.right, rect.right),
        math.max(current.bottom, rect.bottom),
      );
    }

    for (final node in _document.nodes) {
      include(_nodeWorldRect(node));
    }
    for (final text in _document.texts) {
      include(_textWorldRect(text));
    }
    for (final shape in _document.shapes) {
      include(
        Rect.fromPoints(
          Offset(shape.x1.toDouble(), shape.y1.toDouble()),
          Offset(shape.x2.toDouble(), shape.y2.toDouble()),
        ).inflate(shape.width.toDouble() + 12),
      );
    }
    for (final stroke in _document.strokes) {
      include(_boundsForStroke(stroke));
    }

    final content = bounds ??
        Rect.fromCenter(
          center: Offset.zero,
          width: 1800,
          height: 1200,
        );
    return content.inflate(280);
  }

  Rect _currentVisibleWorldRect() {
    final size = _lastViewportSize;
    if (size == null || size.isEmpty) {
      return Rect.fromCenter(
        center: Offset.zero,
        width: 1200,
        height: 800,
      );
    }
    final points = <Offset>[
      _viewport.toScene(Offset.zero),
      _viewport.toScene(Offset(size.width, 0)),
      _viewport.toScene(Offset(0, size.height)),
      _viewport.toScene(Offset(size.width, size.height)),
    ].map((point) => point - Offset(_origin, _origin)).toList();
    return Rect.fromLTRB(
      points.map((point) => point.dx).reduce(math.min),
      points.map((point) => point.dy).reduce(math.min),
      points.map((point) => point.dx).reduce(math.max),
      points.map((point) => point.dy).reduce(math.max),
    );
  }

  Widget _miniMapWidget() => IgnorePointer(
        child: Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            key: const ValueKey('whiteboard-minimap'),
            width: 168,
            height: 112,
            child: AnimatedBuilder(
              animation: _viewport,
              builder: (context, _) => CustomPaint(
                painter: _MiniMapPainter(
                  document: _document,
                  bounds: _overviewBounds(),
                  viewport: _currentVisibleWorldRect(),
                ),
              ),
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
                  IconButton.filledTonal(
                    key: const ValueKey('whiteboard-undo'),
                    onPressed: _undoStack.isEmpty ? null : _undo,
                    tooltip: 'Annulla',
                    icon: const Icon(Icons.undo),
                  ),
                  IconButton.filledTonal(
                    key: const ValueKey('whiteboard-redo'),
                    onPressed: _redoStack.isEmpty ? null : _redo,
                    tooltip: 'Ripristina',
                    icon: const Icon(Icons.redo),
                  ),
                  const VerticalDivider(),
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
                      _workingVersion++;
                      _shapeStart = null;
                      _shapeEnd = null;
                    }),
                    isSelected: _connectMode,
                    tooltip: 'Collega due elementi',
                    icon: const Icon(Icons.timeline),
                  ),
                  if (_document.mode == WhiteboardMode.mindMap)
                    IconButton.filledTonal(
                      onPressed: () => _setDocument(
                        WhiteboardOps.autoLayoutMindMap(_document),
                      ),
                      tooltip: 'Layout automatico',
                      icon: const Icon(Icons.auto_awesome_mosaic),
                    ),
                  const VerticalDivider(),
                  _toolButton(
                    Icons.pan_tool,
                    'Naviga',
                    _WhiteboardTool.navigate,
                  ),
                  _toolButton(
                    Icons.select_all,
                    'Seleziona',
                    _WhiteboardTool.select,
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
                  if (_isInkTool) _colorControl(),
                  if (_isInkTool) _widthControl(),
                  if (_tool != _WhiteboardTool.navigate &&
                      _tool != _WhiteboardTool.select &&
                      _tool != _WhiteboardTool.text)
                    IconButton.filledTonal(
                      onPressed: () =>
                          setState(() => _fingerDraw = !_fingerDraw),
                      isSelected: _fingerDraw,
                      tooltip: _fingerDraw
                          ? 'Dito: disegna'
                          : 'Dito: naviga, penna: disegna',
                      icon: const Icon(Icons.touch_app),
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
          if (!widget.readOnly && _selectionMode)
            SizedBox(
              height: 52,
              child: ListView(
                key: const ValueKey('whiteboard-selection-bar'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '${_selectedNodeIds.length + _selectedTextIds.length} selezionati',
                        key: const ValueKey('whiteboard-selection-count'),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    key: const ValueKey('whiteboard-select-all'),
                    onPressed: _selectAllObjects,
                    tooltip: 'Seleziona tutto',
                    icon: const Icon(Icons.done_all),
                  ),
                  IconButton.filledTonal(
                    onPressed:
                        _selectedNodeIds.isEmpty && _selectedTextIds.isEmpty
                            ? null
                            : _clearSelection,
                    tooltip: 'Deseleziona tutto',
                    icon: const Icon(Icons.deselect),
                  ),
                  const VerticalDivider(),
                  IconButton.filledTonal(
                    key: const ValueKey('whiteboard-duplicate-selection'),
                    onPressed:
                        _selectedNodeIds.isEmpty && _selectedTextIds.isEmpty
                            ? null
                            : _duplicateSelection,
                    tooltip: 'Duplica selezione',
                    icon: const Icon(Icons.copy_all_outlined),
                  ),
                  IconButton.filledTonal(
                    key: const ValueKey('whiteboard-resize-smaller'),
                    onPressed: _selectedNodeIds.isEmpty
                        ? null
                        : () => _resizeSelection(-40),
                    tooltip: 'Riduci post-it',
                    icon: const Icon(Icons.zoom_in_map),
                  ),
                  IconButton.filledTonal(
                    key: const ValueKey('whiteboard-resize-larger'),
                    onPressed: _selectedNodeIds.isEmpty
                        ? null
                        : () => _resizeSelection(40),
                    tooltip: 'Ingrandisci post-it',
                    icon: const Icon(Icons.zoom_out_map),
                  ),
                  IconButton.filledTonal(
                    key: const ValueKey('whiteboard-snap-grid'),
                    onPressed: () => setState(() => _snapToGrid = !_snapToGrid),
                    isSelected: _snapToGrid,
                    tooltip: _snapToGrid
                        ? 'Snap griglia attivo'
                        : 'Snap griglia disattivo',
                    icon: const Icon(Icons.grid_4x4),
                  ),
                  IconButton.filledTonal(
                    key: const ValueKey('whiteboard-delete-selection'),
                    onPressed:
                        _selectedNodeIds.isEmpty && _selectedTextIds.isEmpty
                            ? null
                            : _deleteSelection,
                    tooltip: 'Elimina selezione',
                    icon: const Icon(Icons.delete_outline),
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
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: InteractiveViewer.builder(
                          key: const ValueKey('whiteboard-viewport'),
                          transformationController: _viewport,
                          minScale: 0.2,
                          maxScale: 3.2,
                          boundaryMargin: const EdgeInsets.all(double.infinity),
                          panEnabled: !_stylusInContact &&
                              !_objectPointerActive &&
                              (widget.readOnly ||
                                  _tool == _WhiteboardTool.navigate ||
                                  _tool == _WhiteboardTool.text ||
                                  (!_selectionMode && !_fingerDraw)),
                          scaleEnabled:
                              !_stylusInContact && !_objectPointerActive,
                          onInteractionEnd: (_) => _growCanvasForViewport(),
                          builder: (context, viewport) {
                            final xs = <double>[
                              viewport.point0.x,
                              viewport.point1.x,
                              viewport.point2.x,
                              viewport.point3.x,
                            ];
                            final ys = <double>[
                              viewport.point0.y,
                              viewport.point1.y,
                              viewport.point2.y,
                              viewport.point3.y,
                            ];
                            final visibleRect = Rect.fromLTRB(
                              xs.reduce(math.min),
                              ys.reduce(math.min),
                              xs.reduce(math.max),
                              ys.reduce(math.max),
                            ).inflate(160);

                            return Listener(
                              onPointerDown: _onPointerDown,
                              onPointerMove: _onPointerMove,
                              onPointerUp: _onPointerEnd,
                              onPointerCancel: _onPointerEnd,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                supportedDevices: _canvasGestureDevices,
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
                                onPanCancel: widget.readOnly ||
                                        _tool == _WhiteboardTool.navigate ||
                                        _tool == _WhiteboardTool.text
                                    ? null
                                    : _drawCancel,
                                onTapUp: widget.readOnly ||
                                        _tool != _WhiteboardTool.text
                                    ? null
                                    : _tapCanvas,
                                child: RepaintBoundary(
                                  key: _exportKey,
                                  child: SizedBox(
                                    key: const ValueKey('whiteboard-canvas'),
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
                                              workingVersion: _workingVersion,
                                              workingColor: _workingColor,
                                              workingWidth: _workingWidth,
                                              workingMarker: _tool ==
                                                  _WhiteboardTool.highlighter,
                                              previewShape: _previewShape,
                                              lassoWorldRect: _lassoWorldRect,
                                              visibleRect: visibleRect,
                                              strokeBounds: _strokeBounds,
                                            ),
                                          ),
                                        ),
                                        ..._document.texts.map(_textWidget),
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
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: _miniMapWidget(),
                      ),
                    ],
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

  Widget _textWidget(SketchText text) {
    final canManipulate = !widget.readOnly &&
        (_tool == _WhiteboardTool.navigate || _selectionMode);
    final selected = _selectedTextIds.contains(text.id);
    final width = math.min(
      800.0,
      math.max(140.0, text.text.length * text.size * 0.55),
    );
    final height = math.max(72.0, text.size * 2.8);
    return Positioned(
      left: _origin + text.x,
      top: _origin + text.y,
      width: width,
      height: height,
      child: Listener(
        onPointerDown:
            canManipulate ? (event) => _onTextPointerDown(text, event) : null,
        onPointerMove: canManipulate
            ? (event) => _moveTextByDelta(text, event.localDelta)
            : null,
        onPointerUp: canManipulate ? _onObjectPointerEnd : null,
        onPointerCancel: canManipulate ? _onObjectPointerEnd : null,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: canManipulate
              ? () {
                  if (_selectionMode) {
                    _toggleTextSelection(text);
                  } else {
                    _editText(text);
                  }
                }
              : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: selected
                  ? Border.all(
                      width: 2,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: selected ? const EdgeInsets.all(4) : EdgeInsets.zero,
                child: Text(
                  text.text,
                  maxLines: 6,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    color: Color(text.color),
                    fontSize: text.size.toDouble(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _nodeWidget(BoardNode node) {
    final connectSelected = _connectFrom == node.id;
    final selected = _selectedNodeIds.contains(node.id);
    final canManipulate = !widget.readOnly &&
        (_tool == _WhiteboardTool.navigate || _selectionMode);
    return Positioned(
      left: _origin + node.x,
      top: _origin + node.y,
      width: node.width.toDouble(),
      height: node.height.toDouble(),
      child: Listener(
        onPointerDown:
            canManipulate ? (event) => _onNodePointerDown(node, event) : null,
        onPointerMove: canManipulate
            ? (event) => _moveNodeByDelta(node, event.localDelta)
            : null,
        onPointerUp: canManipulate ? _onObjectPointerEnd : null,
        onPointerCancel: canManipulate ? _onObjectPointerEnd : null,
        child: GestureDetector(
          onTap: canManipulate
              ? () {
                  if (_selectionMode) {
                    _toggleNodeSelection(node);
                  } else {
                    _nodeTap(node);
                  }
                }
              : null,
          onLongPress: !widget.readOnly && _tool == _WhiteboardTool.navigate
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
                width: selected || connectSelected ? 4 : 1,
                color: selected || connectSelected
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
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  const _BoardPainter({
    required this.document,
    required this.origin,
    required this.working,
    required this.workingVersion,
    required this.workingColor,
    required this.workingWidth,
    required this.workingMarker,
    required this.previewShape,
    required this.lassoWorldRect,
    required this.visibleRect,
    required this.strokeBounds,
  });

  final WhiteboardDocument document;
  final double origin;
  final List<InkPoint> working;
  final int workingVersion;
  final int workingColor;
  final int workingWidth;
  final bool workingMarker;
  final BoardShape? previewShape;
  final Rect? lassoWorldRect;
  final Rect visibleRect;
  final Map<String, Rect> strokeBounds;

  Rect get _worldVisible => visibleRect.shift(Offset(-origin, -origin));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white,
    );

    final canvasRect = Offset.zero & size;
    final visible = visibleRect.intersect(canvasRect);
    if (!visible.isEmpty) _paper(canvas, visible);

    for (final stroke in document.strokes) {
      final bounds = strokeBounds[stroke.id];
      if (bounds != null && !bounds.overlaps(_worldVisible)) continue;
      _stroke(canvas, stroke);
    }

    if (working.isNotEmpty) {
      _stroke(
        canvas,
        InkStroke(
          color: workingColor,
          width: workingWidth,
          marker: workingMarker,
          points: working,
        ),
      );
    }

    for (final shape in document.shapes) {
      final bounds = Rect.fromPoints(
        Offset(shape.x1.toDouble(), shape.y1.toDouble()),
        Offset(shape.x2.toDouble(), shape.y2.toDouble()),
      ).inflate(shape.width.toDouble() + 30);
      if (!bounds.overlaps(_worldVisible)) continue;
      _shape(canvas, shape);
    }
    if (previewShape != null) _shape(canvas, previewShape!);

    if (lassoWorldRect != null) {
      final rect = lassoWorldRect!.shift(Offset(origin, origin));
      final fill = Paint()
        ..color = const Color(0x1A1976D2)
        ..style = PaintingStyle.fill;
      final border = Paint()
        ..color = const Color(0xFF1976D2)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, border);
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
      if (!Rect.fromPoints(start, end).inflate(40).overlaps(visibleRect)) {
        continue;
      }
      final paint = Paint()
        ..color = Color(edge.color)
        ..strokeWidth = edge.width.toDouble()
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(start, end, paint);

      if (edge.kind == BoardEdgeKind.arrow) {
        _arrowHead(canvas, start, end, paint, 24);
      }
    }
  }

  void _paper(Canvas canvas, Rect visible) {
    final line = Paint()
      ..color = const Color(0x1A455A64)
      ..strokeWidth = 1;

    double first(double value, double spacing) =>
        (value / spacing).floorToDouble() * spacing;

    switch (document.paper) {
      case WhiteboardPaper.plain:
        return;
      case WhiteboardPaper.ruled:
        for (double y = first(visible.top, 70); y <= visible.bottom; y += 70) {
          canvas.drawLine(
            Offset(visible.left, y),
            Offset(visible.right, y),
            line,
          );
        }
        return;
      case WhiteboardPaper.grid:
        for (double x = first(visible.left, 80); x <= visible.right; x += 80) {
          canvas.drawLine(
            Offset(x, visible.top),
            Offset(x, visible.bottom),
            line,
          );
        }
        for (double y = first(visible.top, 80); y <= visible.bottom; y += 80) {
          canvas.drawLine(
            Offset(visible.left, y),
            Offset(visible.right, y),
            line,
          );
        }
        return;
      case WhiteboardPaper.dots:
        final dot = Paint()..color = const Color(0x33455A64);
        for (double x = first(visible.left, 40); x <= visible.right; x += 40) {
          for (double y = first(visible.top, 40);
              y <= visible.bottom;
              y += 40) {
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

    final variablePressure =
        !stroke.marker && stroke.points.any((point) => point.pressure < 990);
    if (!variablePressure) {
      final path = Path()
        ..moveTo(
          origin + stroke.points.first.x,
          origin + stroke.points.first.y,
        );
      for (final point in stroke.points.skip(1)) {
        path.lineTo(origin + point.x, origin + point.y);
      }
      canvas.drawPath(path, paint);
      return;
    }

    var previous = stroke.points.first;
    for (final point in stroke.points.skip(1)) {
      final pressure =
          ((previous.pressure + point.pressure) / 2000).clamp(0.05, 1.0);
      final factor = (0.30 + pressure * 0.70).clamp(0.30, 1.0).toDouble();
      paint.strokeWidth = stroke.width * factor;
      canvas.drawLine(
        Offset(origin + previous.x, origin + previous.y),
        Offset(origin + point.x, origin + point.y),
        paint,
      );
      previous = point;
    }
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
  bool shouldRepaint(covariant _BoardPainter oldDelegate) =>
      oldDelegate.document != document ||
      oldDelegate.origin != origin ||
      oldDelegate.workingVersion != workingVersion ||
      oldDelegate.workingColor != workingColor ||
      oldDelegate.workingWidth != workingWidth ||
      oldDelegate.workingMarker != workingMarker ||
      oldDelegate.previewShape != previewShape ||
      oldDelegate.lassoWorldRect != lassoWorldRect ||
      oldDelegate.visibleRect != visibleRect;
}

class _MiniMapPainter extends CustomPainter {
  const _MiniMapPainter({
    required this.document,
    required this.bounds,
    required this.viewport,
  });

  final WhiteboardDocument document;
  final Rect bounds;
  final Rect viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFFF7F8FA);
    canvas.drawRect(Offset.zero & size, background);

    if (bounds.width <= 0 || bounds.height <= 0) return;
    const padding = 8.0;
    final scale = math.min(
      (size.width - padding * 2) / bounds.width,
      (size.height - padding * 2) / bounds.height,
    );
    if (!scale.isFinite || scale <= 0) return;

    final usedWidth = bounds.width * scale;
    final usedHeight = bounds.height * scale;
    final dx = (size.width - usedWidth) / 2;
    final dy = (size.height - usedHeight) / 2;

    Offset mapPoint(Offset point) => Offset(
          dx + (point.dx - bounds.left) * scale,
          dy + (point.dy - bounds.top) * scale,
        );

    Rect mapRect(Rect rect) => Rect.fromPoints(
          mapPoint(rect.topLeft),
          mapPoint(rect.bottomRight),
        );

    final inkPaint = Paint()
      ..color = const Color(0x8052606D)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final stroke in document.strokes) {
      if (stroke.points.isEmpty) continue;
      final step = math.max(1, stroke.points.length ~/ 60).toInt();
      final path = Path();
      final first = stroke.points.first;
      path.moveTo(
        mapPoint(Offset(first.x.toDouble(), first.y.toDouble())).dx,
        mapPoint(Offset(first.x.toDouble(), first.y.toDouble())).dy,
      );
      for (var i = step; i < stroke.points.length; i += step) {
        final point = stroke.points[i];
        final mapped = mapPoint(
          Offset(point.x.toDouble(), point.y.toDouble()),
        );
        path.lineTo(mapped.dx, mapped.dy);
      }
      canvas.drawPath(path, inkPaint);
    }

    final nodePaint = Paint()
      ..color = const Color(0xFF90A4AE)
      ..style = PaintingStyle.fill;
    for (final node in document.nodes) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          mapRect(
            Rect.fromLTWH(
              node.x.toDouble(),
              node.y.toDouble(),
              node.width.toDouble(),
              node.height.toDouble(),
            ),
          ),
          const Radius.circular(2),
        ),
        nodePaint,
      );
    }

    final textPaint = Paint()
      ..color = const Color(0xFF607D8B)
      ..style = PaintingStyle.fill;
    for (final text in document.texts) {
      final point = mapPoint(Offset(text.x.toDouble(), text.y.toDouble()));
      canvas.drawCircle(point, 1.8, textPaint);
    }

    final viewportPaint = Paint()
      ..color = const Color(0xFF1976D2)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(mapRect(viewport), viewportPaint);
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) =>
      oldDelegate.document != document ||
      oldDelegate.bounds != bounds ||
      oldDelegate.viewport != viewport;
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
