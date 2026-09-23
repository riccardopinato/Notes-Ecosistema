import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../domain/note.dart';
import '../domain/visual_documents.dart';
import '../platform/visual_share_bridge.dart';

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
      _error = error.toString().replaceFirst('FormatException: ', '');
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
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
          _error = error.toString().replaceFirst('FormatException: ', '');
        });
      }
    }
  }

  Future<Uint8List> _renderPng() async {
    final boundary = _exportKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
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
      final fallback = _document.mode == WhiteboardMode.mindMap
          ? 'mind-map'
          : 'lavagna';
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
            error.toString().replaceFirst('FormatException: ', ''),
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
      final title = _title.text.trim().isEmpty
          ? fallback
          : _title.text.trim();
      await VisualShareBridge.sharePng(bytes, title: title);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('FormatException: ', ''),
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
    final scale = 1.0;
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
        _document = WhiteboardOps.empty(mode);
      } else {
        _document = _document.copyWith(mode: mode);
      }
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
                    _connectMode = !_connectMode;
                    _connectFrom = null;
                  }),
                  isSelected: _connectMode,
                  tooltip: 'Collega due elementi',
                  icon: const Icon(Icons.timeline),
                ),
                if (_document.mode == WhiteboardMode.mindMap)
                  IconButton.filledTonal(
                    onPressed: () => setState(() {
                      _document =
                          WhiteboardOps.autoLayoutMindMap(_document);
                    }),
                    tooltip: 'Layout automatico',
                    icon: const Icon(Icons.auto_awesome_mosaic),
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
              child: InteractiveViewer(
                minScale: 0.2,
                maxScale: 3.2,
                boundaryMargin: const EdgeInsets.all(1200),
                constrained: false,
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
                          ),
                        ),
                      ),
                      ..._document.nodes.map(_nodeWidget),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nodeWidget(BoardNode node) {
    final selected = _connectFrom == node.id;
    return Positioned(
      left: _origin + node.x,
      top: _origin + node.y,
      width: node.width.toDouble(),
      height: node.height.toDouble(),
      child: GestureDetector(
        onPanUpdate:
            widget.readOnly ? null : (details) => _moveNode(node, details),
        onTap: widget.readOnly ? null : () => _nodeTap(node),
        onLongPress: widget.readOnly ? null : () {
          if (_document.mode == WhiteboardMode.mindMap) {
            _addNode(kind: BoardNodeKind.mindNode, parent: node);
          } else {
            _editNode(node);
          }
        },
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
  });

  final WhiteboardDocument document;
  final double origin;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0x12455A64)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 80) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 80) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
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
        final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
        const length = 24.0;
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
    }

    for (final stroke in document.strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = Color(stroke.color)
        ..strokeWidth = stroke.width.toDouble()
        ..strokeCap = StrokeCap.round
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

    for (final shape in document.shapes) {
      final paint = Paint()
        ..color = Color(shape.color)
        ..strokeWidth = shape.width.toDouble()
        ..style = PaintingStyle.stroke;
      final rect = Rect.fromPoints(
        Offset(origin + shape.x1, origin + shape.y1),
        Offset(origin + shape.x2, origin + shape.y2),
      );
      if (shape.kind == BoardShapeKind.ellipse) {
        canvas.drawOval(rect, paint);
      } else {
        canvas.drawRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) => true;
}

Color _contrast(Color background) {
  final luminance = background.computeLuminance();
  return luminance > 0.5 ? Colors.black87 : Colors.white;
}
