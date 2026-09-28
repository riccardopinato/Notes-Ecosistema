import 'package:flutter/material.dart';

import '../domain/knowledge_graph.dart';
import '../domain/note.dart';
import '../widgets/editorial.dart';
import '../widgets/ui_resilience.dart';

class KnowledgeGraphScreen extends StatefulWidget {
  const KnowledgeGraphScreen({
    required this.loadGraph,
    required this.notes,
    required this.onOpenNote,
    required this.onOpenProject,
    required this.onOpenStudy,
    super.key,
  });

  final Future<KnowledgeGraphSnapshot> Function() loadGraph;
  final List<Note> notes;
  final ValueChanged<Note> onOpenNote;
  final ValueChanged<String> onOpenProject;
  final VoidCallback onOpenStudy;

  @override
  State<KnowledgeGraphScreen> createState() => _KnowledgeGraphScreenState();
}

class _KnowledgeGraphScreenState extends State<KnowledgeGraphScreen> {
  static const _canvasSize = Size(2200, 1600);
  final TransformationController _viewport = TransformationController();
  KnowledgeGraphSnapshot? _graph;
  String? _focusId;
  KnowledgeGraphScope _scope = KnowledgeGraphScope.all;
  final Set<KnowledgeGraphEdgeKind> _edgeKinds = {
    ...KnowledgeGraphEdgeKind.values,
  };
  bool _loading = true;
  String? _error;
  bool _centered = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _viewport.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final graph = await widget.loadGraph();
      if (!mounted) return;
      setState(() {
        _graph = graph;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = userErrorText(error);
        _loading = false;
      });
    }
  }

  KnowledgeGraphView get _view => KnowledgeGraphProjection.project(
        graph: _graph!,
        focusNodeId: _focusId,
        scope: _scope,
        edgeKinds: _edgeKinds,
      );

  void _center(Size viewport) {
    if (_centered || viewport.width <= 0 || viewport.height <= 0) return;
    _centered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dx = (viewport.width - _canvasSize.width) / 2;
      final dy = (viewport.height - _canvasSize.height) / 2;
      _viewport.value = Matrix4.identity()..setTranslationRaw(dx, dy, 0);
    });
  }

  void _focus(KnowledgeGraphNode node) {
    setState(() {
      _focusId = node.id;
      if (_scope == KnowledgeGraphScope.all) {
        _scope = KnowledgeGraphScope.twoHops;
      }
    });
  }

  void _open(KnowledgeGraphNode node) {
    switch (node.kind) {
      case KnowledgeGraphNodeKind.note:
      case KnowledgeGraphNodeKind.task:
        final note =
            widget.notes.where((item) => item.id == node.entityId).firstOrNull;
        if (note != null) widget.onOpenNote(note);
        break;
      case KnowledgeGraphNodeKind.project:
        widget.onOpenProject(node.entityId);
        break;
      case KnowledgeGraphNodeKind.study:
        widget.onOpenStudy();
        break;
      case KnowledgeGraphNodeKind.pdf:
        final edge = _graph!.edges.where(
          (item) =>
              item.kind == KnowledgeGraphEdgeKind.document &&
              (item.sourceId == node.id || item.targetId == node.id),
        );
        if (edge.isEmpty) return;
        final noteNodeId = edge.first.sourceId == node.id
            ? edge.first.targetId
            : edge.first.sourceId;
        final noteId = noteNodeId.replaceFirst('note:', '');
        final note =
            widget.notes.where((item) => item.id == noteId).firstOrNull;
        if (note != null) widget.onOpenNote(note);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const EditorialAppTitle(
          'Knowledge Graph',
          eyebrow: 'CONNESSIONI DERIVATE',
        ),
        actions: [
          IconButton(
            tooltip: 'Ricarica',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 36),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Riprova'),
                        ),
                      ],
                    ),
                  ),
                )
              : _graph == null || _graph!.nodes.isEmpty
                  ? const Center(child: Text('Nessun contenuto da collegare.'))
                  : Column(
                      children: [
                        _toolbar(),
                        const Divider(height: 1),
                        Expanded(child: _graphCanvas()),
                      ],
                    ),
    );
  }

  Widget _toolbar() {
    final graph = _graph!;
    final focus = _focusId == null ? null : graph.node(_focusId!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Autocomplete<KnowledgeGraphNode>(
                  displayStringForOption: (node) => node.label,
                  optionsBuilder: (value) {
                    final query = value.text.trim().toLowerCase();
                    if (query.isEmpty) return const Iterable.empty();
                    return graph.nodes
                        .where(
                          (node) =>
                              node.label.toLowerCase().contains(query) ||
                              (node.subtitle ?? '')
                                  .toLowerCase()
                                  .contains(query),
                        )
                        .take(12);
                  },
                  onSelected: _focus,
                  fieldViewBuilder: (
                    context,
                    controller,
                    focusNode,
                    onSubmitted,
                  ) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Trova un nodo…',
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              SegmentedButton<KnowledgeGraphScope>(
                segments: const [
                  ButtonSegment(
                    value: KnowledgeGraphScope.neighbors,
                    label: Text('1 hop'),
                  ),
                  ButtonSegment(
                    value: KnowledgeGraphScope.twoHops,
                    label: Text('2 hop'),
                  ),
                  ButtonSegment(
                    value: KnowledgeGraphScope.all,
                    label: Text('Tutto'),
                  ),
                ],
                selected: {_scope},
                onSelectionChanged: (value) {
                  setState(() => _scope = value.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final kind in KnowledgeGraphEdgeKind.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(_edgeLabel(kind)),
                      selected: _edgeKinds.contains(kind),
                      onSelected: (value) {
                        setState(() {
                          if (value) {
                            _edgeKinds.add(kind);
                          } else if (_edgeKinds.length > 1) {
                            _edgeKinds.remove(kind);
                          }
                        });
                      },
                    ),
                  ),
                if (focus != null) ...[
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.close, size: 18),
                    label: Text('Focus: ${focus.label}'),
                    onPressed: () => setState(() => _focusId = null),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _graphCanvas() {
    final view = _view;
    return LayoutBuilder(
      builder: (context, constraints) {
        _center(Size(constraints.maxWidth, constraints.maxHeight));
        return Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
              ),
            ),
            InteractiveViewer(
              transformationController: _viewport,
              minScale: 0.22,
              maxScale: 2.2,
              boundaryMargin: const EdgeInsets.all(900),
              constrained: false,
              child: SizedBox(
                width: _canvasSize.width,
                height: _canvasSize.height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _KnowledgeGraphPainter(
                          view: view,
                          colorScheme: Theme.of(context).colorScheme,
                        ),
                      ),
                    ),
                    for (final node in view.nodes)
                      _positionedNode(
                        node,
                        view.positions[node.id]!,
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Text(
                    '${view.nodes.length} nodi · ${view.edges.length} connessioni'
                    '${view.hiddenNodes > 0 ? ' · +${view.hiddenNodes} nascosti' : ''}',
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _positionedNode(
    KnowledgeGraphNode node,
    KnowledgeGraphPoint point,
  ) {
    const width = 176.0;
    const height = 72.0;
    final selected = node.id == _focusId;
    final colors = Theme.of(context).colorScheme;
    return Positioned(
      left: point.x - width / 2,
      top: point.y - height / 2,
      width: width,
      height: height,
      child: Semantics(
        button: true,
        label: '${_nodeLabel(node.kind)}: ${node.label}',
        child: Material(
          elevation: selected ? 6 : 1,
          color: selected
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _focus(node),
            onDoubleTap: () => _open(node),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(_nodeIcon(node.kind), size: 22),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        if (node.subtitle != null)
                          Text(
                            node.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
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

  String _edgeLabel(KnowledgeGraphEdgeKind kind) => switch (kind) {
        KnowledgeGraphEdgeKind.link => 'Link',
        KnowledgeGraphEdgeKind.relation => 'Relazioni',
        KnowledgeGraphEdgeKind.project => 'Progetti',
        KnowledgeGraphEdgeKind.study => 'Study',
        KnowledgeGraphEdgeKind.document => 'PDF',
      };

  String _nodeLabel(KnowledgeGraphNodeKind kind) => switch (kind) {
        KnowledgeGraphNodeKind.note => 'Nota',
        KnowledgeGraphNodeKind.task => 'Attività',
        KnowledgeGraphNodeKind.project => 'Progetto',
        KnowledgeGraphNodeKind.study => 'Study',
        KnowledgeGraphNodeKind.pdf => 'PDF',
      };

  IconData _nodeIcon(KnowledgeGraphNodeKind kind) => switch (kind) {
        KnowledgeGraphNodeKind.note => Icons.description_outlined,
        KnowledgeGraphNodeKind.task => Icons.task_alt,
        KnowledgeGraphNodeKind.project => Icons.work_outline,
        KnowledgeGraphNodeKind.study => Icons.school_outlined,
        KnowledgeGraphNodeKind.pdf => Icons.picture_as_pdf_outlined,
      };
}

class _KnowledgeGraphPainter extends CustomPainter {
  const _KnowledgeGraphPainter({
    required this.view,
    required this.colorScheme,
  });

  final KnowledgeGraphView view;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final positions = view.positions;
    for (final edge in view.edges) {
      final a = positions[edge.sourceId];
      final b = positions[edge.targetId];
      if (a == null || b == null) continue;
      final paint = Paint()
        ..color = _edgeColor(edge.kind).withValues(alpha: 0.55)
        ..strokeWidth = edge.kind == KnowledgeGraphEdgeKind.relation ? 2.4 : 1.6
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), paint);
    }
  }

  Color _edgeColor(KnowledgeGraphEdgeKind kind) => switch (kind) {
        KnowledgeGraphEdgeKind.link => colorScheme.primary,
        KnowledgeGraphEdgeKind.relation => colorScheme.tertiary,
        KnowledgeGraphEdgeKind.project => colorScheme.secondary,
        KnowledgeGraphEdgeKind.study => colorScheme.primary,
        KnowledgeGraphEdgeKind.document => colorScheme.error,
      };

  @override
  bool shouldRepaint(covariant _KnowledgeGraphPainter oldDelegate) =>
      oldDelegate.view != view || oldDelegate.colorScheme != colorScheme;
}
