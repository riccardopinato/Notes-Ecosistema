import 'project_workspace.dart';

/// A source-backed, read-only view of direct impact inside one visible project.
/// A dependency mention is not a promise that completing its target unblocks
/// the source: there may be additional prerequisites or explicit blockers.
class ProjectDependencyImpact {
  const ProjectDependencyImpact({
    required this.taskId,
    required this.title,
    required this.directDependents,
    required this.visibleDependentTitles,
  });

  final String taskId;
  final String title;
  final int directDependents;
  final List<String> visibleDependentTitles;
}

abstract final class ProjectDependencyImpactReview {
  static List<ProjectDependencyImpact> inspect(
    Iterable<ProjectWorkItem> scopedItems, {
    int limit = 5,
  }) {
    if (limit < 0 || limit > 20) {
      throw const FormatException('INVALID_IMPACT_LIMIT');
    }
    if (limit == 0) return const [];
    final visible = scopedItems
        .where((item) =>
            item.kind == ProjectWorkItemKind.task &&
            !item.note.isDeleted &&
            !item.note.archived)
        .toList(growable: false);
    // Fail closed on unsupported scopes rather than ranking a partial graph.
    if (visible.length > ProjectWorkspaceRules.maxItemsPerProject) {
      return const [];
    }

    final byId = <String, List<ProjectWorkItem>>{};
    for (final item in visible) {
      byId.putIfAbsent(item.note.id.toLowerCase(), () => []).add(item);
    }
    final impacts = <String, Set<String>>{};
    for (final item in visible) {
      if (item.completed) continue;
      final sourceId = item.note.id.toLowerCase();
      if (byId[sourceId]?.length != 1) continue;
      final targets = <String>{};
      for (final raw in item.note.tags) {
        final tag = raw.trim().toLowerCase();
        if (!tag.startsWith('dep_')) continue;
        final targetId = tag.substring(4);
        if (targetId == sourceId ||
            targetId.isEmpty ||
            targetId.length > 36 ||
            !RegExp(r'^[a-z0-9_-]+$').hasMatch(targetId) ||
            byId[targetId]?.length != 1 ||
            byId[targetId]!.single.completed) {
          continue;
        }
        targets.add(targetId);
      }
      for (final targetId in targets) {
        impacts.putIfAbsent(targetId, () => <String>{}).add(sourceId);
      }
    }

    final ordered = impacts.keys.toList()
      ..sort((a, b) {
        final score = impacts[b]!.length.compareTo(impacts[a]!.length);
        return score != 0 ? score : a.compareTo(b);
      });
    return List.unmodifiable([
      for (final id in ordered.take(limit))
        ProjectDependencyImpact(
          taskId: byId[id]!.single.note.id,
          title: byId[id]!.single.title,
          directDependents: impacts[id]!.length,
          visibleDependentTitles: List.unmodifiable([
            for (final source in (impacts[id]!.toList()..sort()).take(3))
              byId[source]!.single.title,
          ]),
        ),
    ]);
  }
}
