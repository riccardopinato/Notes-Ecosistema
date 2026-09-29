import 'dart:math' as math;

import 'attachments.dart';
import 'documents.dart';
import 'knowledge.dart';
import 'note.dart';
import 'project_workspace.dart';
import 'research.dart';
import 'stable_links.dart';
import 'study.dart';
import 'unified_retrieval.dart';

enum KnowledgeGraphNodeKind { note, task, project, study, pdf }

enum KnowledgeGraphEdgeKind { link, relation, project, study, document }

enum KnowledgeGraphScope { all, neighbors, twoHops }

class KnowledgeGraphNode {
  const KnowledgeGraphNode({
    required this.id,
    required this.entityId,
    required this.kind,
    required this.label,
    required this.updatedAt,
    this.subtitle,
  });

  final String id;
  final String entityId;
  final KnowledgeGraphNodeKind kind;
  final String label;
  final String? subtitle;
  final int updatedAt;
}

class KnowledgeGraphEdge {
  const KnowledgeGraphEdge({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.kind,
    required this.label,
  });

  final String id;
  final String sourceId;
  final String targetId;
  final KnowledgeGraphEdgeKind kind;
  final String label;

  String get canonicalKey {
    final a = sourceId.compareTo(targetId) <= 0 ? sourceId : targetId;
    final b = sourceId.compareTo(targetId) <= 0 ? targetId : sourceId;
    return '$kind|$a|$b|$label';
  }
}

class KnowledgeGraphSnapshot {
  const KnowledgeGraphSnapshot({
    required this.nodes,
    required this.edges,
  });

  final List<KnowledgeGraphNode> nodes;
  final List<KnowledgeGraphEdge> edges;

  KnowledgeGraphNode? node(String id) {
    for (final value in nodes) {
      if (value.id == id) return value;
    }
    return null;
  }

  int degree(String nodeId) => edges
      .where((edge) => edge.sourceId == nodeId || edge.targetId == nodeId)
      .length;

  Set<String> neighbors(String nodeId) {
    final result = <String>{};
    for (final edge in edges) {
      if (edge.sourceId == nodeId) result.add(edge.targetId);
      if (edge.targetId == nodeId) result.add(edge.sourceId);
    }
    return result;
  }
}

abstract final class KnowledgeGraphSearch {
  static List<KnowledgeGraphNode> search({
    required KnowledgeGraphSnapshot graph,
    required String query,
    List<String> semanticNoteIds = const [],
    int limit = 12,
  }) {
    final needle = UnifiedRetrieval.normalize(query);
    if (needle.isEmpty) return const [];
    if (limit < 1 || limit > 50) {
      throw const FormatException('Limite ricerca grafo non valido.');
    }

    final semanticRank = <String, int>{
      for (var i = 0; i < semanticNoteIds.length; i++) semanticNoteIds[i]: i,
    };
    final rows = <({KnowledgeGraphNode node, int score})>[];
    for (final node in graph.nodes) {
      final lexical = UnifiedRetrieval.scoreText(
        query: needle,
        title: node.label,
        text: node.subtitle ?? '',
      );
      final rank = switch (node.kind) {
        KnowledgeGraphNodeKind.note || KnowledgeGraphNodeKind.task =>
          semanticRank[node.entityId],
        _ => null,
      };
      final semantic = rank == null ? 0 : (320 - rank * 8).clamp(80, 320).toInt();
      final score = lexical + semantic;
      if (score <= 0) continue;
      rows.add((node: node, score: score));
    }
    rows.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byDegree = graph.degree(b.node.id).compareTo(graph.degree(a.node.id));
      if (byDegree != 0) return byDegree;
      final byUpdated = b.node.updatedAt.compareTo(a.node.updatedAt);
      if (byUpdated != 0) return byUpdated;
      return a.node.id.compareTo(b.node.id);
    });
    return rows.take(limit).map((row) => row.node).toList(growable: false);
  }
}

class KnowledgeGraphBuildInput {
  const KnowledgeGraphBuildInput({
    required this.notes,
    required this.relations,
    required this.projects,
    required this.projectLinks,
    required this.studyItems,
    required this.pdfAnnotations,
  });

  final List<Note> notes;
  final List<NoteRelation> relations;
  final List<ProjectWorkspace> projects;
  final List<ProjectItemLink> projectLinks;
  final List<LearningItem> studyItems;
  final List<PdfAnnotation> pdfAnnotations;
}

abstract final class KnowledgeGraph {
  static KnowledgeGraphSnapshot build(KnowledgeGraphBuildInput input) {
    final nodes = <String, KnowledgeGraphNode>{};
    final edges = <String, KnowledgeGraphEdge>{};
    final liveNotes = <String, Note>{
      for (final note in input.notes)
        if (!note.isDeleted) note.id: note,
    };

    for (final note in liveNotes.values) {
      nodes['note:${note.id}'] = KnowledgeGraphNode(
        id: 'note:${note.id}',
        entityId: note.id,
        kind: note.isTask
            ? KnowledgeGraphNodeKind.task
            : KnowledgeGraphNodeKind.note,
        label: note.title.trim().isEmpty ? 'Senza titolo' : note.title.trim(),
        subtitle: note.isTask
            ? 'Attività'
            : note.archived
                ? 'Nota archiviata'
                : 'Nota',
        updatedAt: note.updatedAt,
      );
    }

    for (final note in liveNotes.values) {
      if (note.isVisual) continue;
      final source = 'note:${note.id}';
      for (final link in Knowledge.links(note.body)) {
        final target = 'note:${link.id}';
        if (!nodes.containsKey(target) || target == source) continue;
        _addEdge(
          edges,
          KnowledgeGraphEdge(
            id: 'link:${note.id}:${link.id}',
            sourceId: source,
            targetId: target,
            kind: KnowledgeGraphEdgeKind.link,
            label: 'Link',
          ),
        );
      }
      for (final targetId in _stableObjectLinks(note.body)) {
        final target = 'note:$targetId';
        if (!nodes.containsKey(target) || target == source) continue;
        _addEdge(
          edges,
          KnowledgeGraphEdge(
            id: 'stable-link:${note.id}:$targetId',
            sourceId: source,
            targetId: target,
            kind: KnowledgeGraphEdgeKind.link,
            label: 'Link',
          ),
        );
      }
    }

    for (final relation in input.relations) {
      final source = 'note:${relation.sourceId}';
      final target = 'note:${relation.targetId}';
      if (!nodes.containsKey(source) ||
          !nodes.containsKey(target) ||
          source == target) {
        continue;
      }
      _addEdge(
        edges,
        KnowledgeGraphEdge(
          id: 'relation:${relation.id}',
          sourceId: source,
          targetId: target,
          kind: KnowledgeGraphEdgeKind.relation,
          label: relation.label.trim().isEmpty ? 'Relazione' : relation.label,
        ),
      );
    }

    final activeProjects = {
      for (final project in input.projects)
        if (project.isActive) project.id: project,
    };
    for (final project in activeProjects.values) {
      nodes['project:${project.id}'] = KnowledgeGraphNode(
        id: 'project:${project.id}',
        entityId: project.id,
        kind: KnowledgeGraphNodeKind.project,
        label: project.name,
        subtitle:
            project.sharedSpaceId == null ? 'Progetto' : 'Progetto condiviso',
        updatedAt: project.updatedAt,
      );
    }
    for (final link in input.projectLinks) {
      if (!activeProjects.containsKey(link.projectId) ||
          !liveNotes.containsKey(link.noteId)) {
        continue;
      }
      _addEdge(
        edges,
        KnowledgeGraphEdge(
          id: 'project:${link.projectId}:${link.noteId}',
          sourceId: 'project:${link.projectId}',
          targetId: 'note:${link.noteId}',
          kind: KnowledgeGraphEdgeKind.project,
          label: 'Nel progetto',
        ),
      );
    }

    for (final item in input.studyItems) {
      final sourceId = 'note:${item.sourceNoteId}';
      if (!nodes.containsKey(sourceId)) continue;
      final id = 'study:${item.id}';
      nodes[id] = KnowledgeGraphNode(
        id: id,
        entityId: item.id,
        kind: KnowledgeGraphNodeKind.study,
        label: item.prompt.trim().isEmpty ? 'Elemento di studio' : item.prompt,
        subtitle: 'Study',
        updatedAt: item.updatedAt,
      );
      _addEdge(
        edges,
        KnowledgeGraphEdge(
          id: 'study:${item.id}:${item.sourceNoteId}',
          sourceId: id,
          targetId: sourceId,
          kind: KnowledgeGraphEdgeKind.study,
          label: 'Studia da',
        ),
      );
    }

    final pdfById =
        <String, ({String noteId, String assetKey, int updatedAt})>{};
    for (final annotation in input.pdfAnnotations) {
      if (!liveNotes.containsKey(annotation.noteId)) continue;
      final id = 'pdf:${annotation.noteId}:${annotation.assetKey}';
      final existing = pdfById[id];
      if (existing == null || annotation.updatedAt > existing.updatedAt) {
        pdfById[id] = (
          noteId: annotation.noteId,
          assetKey: annotation.assetKey,
          updatedAt: annotation.updatedAt,
        );
      }
    }
    for (final note in liveNotes.values) {
      if (note.isVisual) continue;
      for (final ref in Attachments.refs(note.body)) {
        if (Attachments.type(ref.key) != AttachmentType.pdf) continue;
        final id = 'pdf:${note.id}:${ref.key}';
        pdfById.putIfAbsent(
          id,
          () => (
            noteId: note.id,
            assetKey: ref.key,
            updatedAt: note.updatedAt,
          ),
        );
      }
    }
    for (final entry in pdfById.entries) {
      final value = entry.value;
      final shortKey = value.assetKey.length <= 12
          ? value.assetKey
          : value.assetKey.substring(0, 12);
      nodes[entry.key] = KnowledgeGraphNode(
        id: entry.key,
        entityId: value.assetKey,
        kind: KnowledgeGraphNodeKind.pdf,
        label: 'PDF · $shortKey…',
        subtitle: 'Document Workspace',
        updatedAt: value.updatedAt,
      );
      _addEdge(
        edges,
        KnowledgeGraphEdge(
          id: 'document:${value.noteId}:${value.assetKey}',
          sourceId: 'note:${value.noteId}',
          targetId: entry.key,
          kind: KnowledgeGraphEdgeKind.document,
          label: 'Documento',
        ),
      );
    }

    final connected = <String>{};
    for (final edge in edges.values) {
      connected
        ..add(edge.sourceId)
        ..add(edge.targetId);
    }
    final orderedNodes = nodes.values.toList(growable: false)
      ..sort((a, b) {
        final aConnected = connected.contains(a.id) ? 1 : 0;
        final bConnected = connected.contains(b.id) ? 1 : 0;
        final byConnected = bConnected.compareTo(aConnected);
        if (byConnected != 0) return byConnected;
        final byUpdated = b.updatedAt.compareTo(a.updatedAt);
        if (byUpdated != 0) return byUpdated;
        return a.id.compareTo(b.id);
      });
    final orderedEdges = edges.values.toList(growable: false)
      ..sort((a, b) => a.canonicalKey.compareTo(b.canonicalKey));

    return KnowledgeGraphSnapshot(nodes: orderedNodes, edges: orderedEdges);
  }

  static Set<String> _stableObjectLinks(String text) {
    final result = <String>{};
    final regex = RegExp(r'\]\((notes://object/[^)\s]+)\)');
    for (final match in regex.allMatches(text)) {
      final raw = match.group(1);
      if (raw == null) continue;
      final target = StableLinks.parse(raw);
      if (target?.kind == StableLinkKind.object) {
        result.add(target!.id);
      }
    }
    return result;
  }

  static void _addEdge(
    Map<String, KnowledgeGraphEdge> edges,
    KnowledgeGraphEdge edge,
  ) {
    if (edge.sourceId == edge.targetId) return;
    edges.putIfAbsent(edge.canonicalKey, () => edge);
  }
}

class KnowledgeGraphPoint {
  const KnowledgeGraphPoint(this.x, this.y);

  final double x;
  final double y;
}

class KnowledgeGraphView {
  const KnowledgeGraphView({
    required this.nodes,
    required this.edges,
    required this.positions,
    required this.hiddenNodes,
  });

  final List<KnowledgeGraphNode> nodes;
  final List<KnowledgeGraphEdge> edges;
  final Map<String, KnowledgeGraphPoint> positions;
  final int hiddenNodes;
}

abstract final class KnowledgeGraphProjection {
  static KnowledgeGraphView project({
    required KnowledgeGraphSnapshot graph,
    String? focusNodeId,
    KnowledgeGraphScope scope = KnowledgeGraphScope.all,
    Set<KnowledgeGraphEdgeKind> edgeKinds = const {
      KnowledgeGraphEdgeKind.link,
      KnowledgeGraphEdgeKind.relation,
      KnowledgeGraphEdgeKind.project,
      KnowledgeGraphEdgeKind.study,
      KnowledgeGraphEdgeKind.document,
    },
    int maxNodes = 120,
  }) {
    if (maxNodes < 8 || maxNodes > 300) {
      throw const FormatException('Limite grafo non valido.');
    }
    final enabledEdges = graph.edges
        .where((edge) => edgeKinds.contains(edge.kind))
        .toList(growable: false);
    final adjacency = <String, Set<String>>{};
    for (final edge in enabledEdges) {
      adjacency.putIfAbsent(edge.sourceId, () => <String>{}).add(edge.targetId);
      adjacency.putIfAbsent(edge.targetId, () => <String>{}).add(edge.sourceId);
    }

    Set<String>? scopedIds;
    if (focusNodeId != null &&
        graph.node(focusNodeId) != null &&
        scope != KnowledgeGraphScope.all) {
      scopedIds = {focusNodeId};
      final first = adjacency[focusNodeId] ?? const <String>{};
      scopedIds.addAll(first);
      if (scope == KnowledgeGraphScope.twoHops) {
        for (final id in first) {
          scopedIds.addAll(adjacency[id] ?? const <String>{});
        }
      }
    }

    final ranked = graph.nodes
        .where((node) => scopedIds == null || scopedIds.contains(node.id))
        .map(
          (node) => (
            node: node,
            degree: adjacency[node.id]?.length ?? 0,
            focus: node.id == focusNodeId ? 1 : 0,
          ),
        )
        .toList()
      ..sort((a, b) {
        final byFocus = b.focus.compareTo(a.focus);
        if (byFocus != 0) return byFocus;
        final byDegree = b.degree.compareTo(a.degree);
        if (byDegree != 0) return byDegree;
        final byUpdated = b.node.updatedAt.compareTo(a.node.updatedAt);
        if (byUpdated != 0) return byUpdated;
        return a.node.id.compareTo(b.node.id);
      });

    final selected = ranked.take(maxNodes).map((row) => row.node).toList();
    final selectedIds = selected.map((node) => node.id).toSet();
    final edges = enabledEdges
        .where(
          (edge) =>
              selectedIds.contains(edge.sourceId) &&
              selectedIds.contains(edge.targetId),
        )
        .toList(growable: false);

    final positions = _layout(selected, edges, focusNodeId: focusNodeId);
    return KnowledgeGraphView(
      nodes: selected,
      edges: edges,
      positions: positions,
      hiddenNodes: math.max(0, ranked.length - selected.length),
    );
  }

  static Map<String, KnowledgeGraphPoint> _layout(
    List<KnowledgeGraphNode> nodes,
    List<KnowledgeGraphEdge> edges, {
    String? focusNodeId,
  }) {
    if (nodes.isEmpty) return const {};
    final degree = <String, int>{};
    for (final edge in edges) {
      degree.update(edge.sourceId, (value) => value + 1, ifAbsent: () => 1);
      degree.update(edge.targetId, (value) => value + 1, ifAbsent: () => 1);
    }
    final center =
        focusNodeId != null && nodes.any((node) => node.id == focusNodeId)
            ? focusNodeId
            : (nodes.toList()
                  ..sort((a, b) {
                    final byDegree =
                        (degree[b.id] ?? 0).compareTo(degree[a.id] ?? 0);
                    if (byDegree != 0) return byDegree;
                    return b.updatedAt.compareTo(a.updatedAt);
                  }))
                .first
                .id;

    const cx = 1100.0;
    const cy = 800.0;
    final positions = <String, KnowledgeGraphPoint>{
      center: const KnowledgeGraphPoint(cx, cy),
    };
    final others = nodes.where((node) => node.id != center).toList()
      ..sort((a, b) {
        final byDegree = (degree[b.id] ?? 0).compareTo(degree[a.id] ?? 0);
        if (byDegree != 0) return byDegree;
        return a.id.compareTo(b.id);
      });

    var placed = 0;
    var ring = 1;
    while (placed < others.length) {
      final capacity = math.max(8, ring * 10);
      final count = math.min(capacity, others.length - placed);
      final radius = 210.0 + (ring - 1) * 190.0;
      for (var i = 0; i < count; i++) {
        final angle = -math.pi / 2 + (2 * math.pi * i / count);
        final node = others[placed + i];
        positions[node.id] = KnowledgeGraphPoint(
          cx + math.cos(angle) * radius,
          cy + math.sin(angle) * radius,
        );
      }
      placed += count;
      ring++;
    }
    return positions;
  }
}
