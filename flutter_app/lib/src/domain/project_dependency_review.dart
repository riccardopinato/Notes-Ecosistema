import 'project_workspace.dart';

/// Read-only projection of explicit `dep_<canonical-task-id>` tags.
/// The 4+36-character form passes the existing NoteTags editor constraint.
/// Only items already authorized inside the current project can be resolved.
class ProjectDependencyIssue {
  const ProjectDependencyIssue(this.sourceId, this.reasonCode);
  final String sourceId;
  final String reasonCode;
}

/// Account- and project-scoped display information. No raw IDs of invisible
/// prerequisite targets are exposed to the UI.
class ProjectDependencyDetail {
  const ProjectDependencyDetail({
    required this.sourceId,
    required this.sourceTitle,
    required this.reasonCode,
    required this.visibleBlockerTitles,
  });
  final String sourceId;
  final String sourceTitle;
  final String reasonCode;
  final List<String> visibleBlockerTitles;
}

abstract final class ProjectDependencyReview {
  /// Resolve only currently visible tasks for display; missing/archived target
  /// identities remain hidden. This is an advisory projection, never a writer.
  static List<ProjectDependencyDetail> details(
    Iterable<ProjectWorkItem> items, {
    int limit = 8,
  }) {
    if (limit < 0 || limit > 100) {
      throw const FormatException('INVALID_DEPENDENCY_LIMIT');
    }
    if (limit == 0) return const [];
    final scoped = items
        .where((item) =>
            item.kind == ProjectWorkItemKind.task &&
            !item.note.archived &&
            !item.note.isDeleted)
        .toList(growable: false);
    final byId = <String, List<ProjectWorkItem>>{};
    for (final item in scoped) {
      byId.putIfAbsent(item.note.id.toLowerCase(), () => []).add(item);
    }
    final output = <ProjectDependencyDetail>[];
    for (final issue in inspect(scoped, limit: limit)) {
      final matches = byId[issue.sourceId];
      if (matches == null || matches.length != 1) continue;
      final names = <String>[];
      final seen = <String>{};
      for (final tag in matches.single.note.tags) {
        if (!tag.startsWith('dep_')) continue;
        final id = tag.substring(4).toLowerCase();
        final target = byId[id];
        if (!seen.add(id) ||
            target == null ||
            target.length != 1 ||
            target.single.completed) continue;
        names.add(target.single.title);
        if (names.length >= 5) break;
      }
      output.add(ProjectDependencyDetail(
        sourceId: issue.sourceId,
        sourceTitle: matches.single.title,
        reasonCode: issue.reasonCode,
        visibleBlockerTitles: List.unmodifiable(names),
      ));
    }
    return List.unmodifiable(output);
  }

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
