import 'project_workspace.dart';

/// Read-only projection of explicit `dep_<canonical-task-id>` tags.
/// The 4+36-character form passes the existing NoteTags editor constraint.
/// Only items already authorized inside the current project can be resolved.
class ProjectDependencyIssue {
  const ProjectDependencyIssue(this.sourceId, this.reasonCode);
  final String sourceId;
  final String reasonCode;
}

abstract final class ProjectDependencyReview {
  static List<ProjectDependencyIssue> inspect(
    Iterable<ProjectWorkItem> items, {
    int limit = 20,
  }) {
    if (limit < 0 || limit > 100) {
      throw const FormatException('INVALID_DEPENDENCY_LIMIT');
    }
    if (limit == 0) return const [];
    final visible = items
        .where((item) =>
            item.kind == ProjectWorkItemKind.task &&
            !item.note.archived &&
            !item.note.isDeleted)
        .toList(growable: false);
    final active =
        visible.where((item) => !item.completed).toList(growable: false);
    final grouped = <String, List<ProjectWorkItem>>{};
    for (final item in visible) {
      grouped.putIfAbsent(item.note.id.toLowerCase(), () => []).add(item);
    }
    final links = <String, Set<String>>{};
    final unresolved = <String, bool>{};
    for (final item in active) {
      final sourceId = item.note.id.toLowerCase();
      if (grouped[sourceId]?.length != 1) continue;
      final dependencies = <String>{};
      for (final rawTag in item.note.tags) {
        final tag = rawTag.trim();
        if (!tag.startsWith('dep_')) continue;
        final target = tag.substring('dep_'.length).trim().toLowerCase();
        if (target.isEmpty ||
            target.length > 36 ||
            !RegExp(r'^[a-z0-9_-]+$').hasMatch(target)) {
          unresolved[sourceId] = true;
          continue;
        }
        if (grouped[target]?.length != 1) {
          unresolved[sourceId] = true;
          continue;
        }
        // A completed canonical target is no longer an active blocker.
        if (grouped[target]!.single.completed) continue;
        dependencies.add(target);
      }
      links[sourceId] = dependencies;
    }

    bool reachable(String from, String sought) {
      final visited = <String>{};
      final queue = <String>[from];
      while (queue.isNotEmpty && visited.length <= 5000) {
        final next = queue.removeLast();
        if (next == sought) return true;
        if (!visited.add(next)) continue;
        queue.addAll(links[next] ?? const {});
      }
      return false;
    }

    final ids = links.keys.toList()..sort();
    final issues = <ProjectDependencyIssue>[];
    for (final source in ids) {
      if (unresolved[source] == true) {
        issues.add(
            ProjectDependencyIssue(source, 'DEPENDENCY_TARGET_UNAVAILABLE'));
      } else if ((links[source] ?? const {})
          .any((target) => reachable(target, source))) {
        issues.add(ProjectDependencyIssue(source, 'DEPENDENCY_CYCLE'));
      } else if ((links[source] ?? const {}).isNotEmpty) {
        issues.add(ProjectDependencyIssue(source, 'EXPLICIT_OPEN_BLOCKER'));
      }
      if (issues.length >= limit) break;
    }
    return List.unmodifiable(issues);
  }
}
