import 'project_workspace.dart';

/// Derived operational status for canonical project tasks. No second task
/// store, implicit automation, inferred deadlines or remote permissions.
enum ProjectTaskReadinessStatus { ready, doing, blocked, done }

class ProjectTaskReadinessRecord {
  const ProjectTaskReadinessRecord({
    required this.taskId,
    required this.title,
    required this.status,
    required this.reasonCode,
  });

  final String taskId;
  final String title;
  final ProjectTaskReadinessStatus status;
  final String reasonCode;
}

abstract final class ProjectTaskReadiness {
  static List<ProjectTaskReadinessRecord> inspect(
    Iterable<ProjectWorkItem> items, {
    int limit = 8,
  }) {
    if (limit < 0 || limit > 20) {
      throw const FormatException('INVALID_READINESS_LIMIT');
    }
    if (limit == 0) return const [];
    final scoped = items.where((item) =>
        item.kind == ProjectWorkItemKind.task &&
        !item.note.isDeleted &&
        !item.note.archived).toList(growable: false);

    // Source policy caps a project at 5,000 items; reject unsupported scopes
    // rather than showing an incorrectly authoritative READY status.
    if (scoped.length > ProjectWorkspaceRules.maxItemsPerProject) {
      return const [];
    }
    final byId = <String, List<ProjectWorkItem>>{};
    for (final item in scoped) {
      byId.putIfAbsent(item.note.id.toLowerCase(), () => []).add(item);
    }
    final links = <String, Set<String>>{};
    final missing = <String>{};
    for (final entry in byId.entries) {
      if (entry.value.length != 1) continue;
      final item = entry.value.single;
      if (item.completed) continue;
      final targets = <String>{};
      for (final tag in item.note.tags) {
        final token = tag.trim().toLowerCase();
        if (!token.startsWith('dep_')) continue;
        final target = token.substring(4);
        if (target.isEmpty ||
            target.length > 36 ||
            !RegExp(r'^[a-z0-9_-]+$').hasMatch(target) ||
            byId[target]?.length != 1) {
          missing.add(entry.key);
          continue;
        }
        if (byId[target]!.single.completed) continue;
        targets.add(target);
      }
      links[entry.key] = targets;
    }

    final result = <ProjectTaskReadinessRecord>[];
    for (final item in scoped) {
      final id = item.note.id.toLowerCase();
      ProjectTaskReadinessStatus status;
      String reason;
      if (byId[id]?.length != 1) {
        status = ProjectTaskReadinessStatus.blocked;
        reason = 'DEPENDENCY_UNAVAILABLE';
      } else if (item.completed) {
        status = ProjectTaskReadinessStatus.done;
        reason = 'TASK_DONE';
      } else if (item.note.tags.any(
          (tag) => tag.trim().toLowerCase() == 'blocked')) {
        status = ProjectTaskReadinessStatus.blocked;
        reason = 'EXPLICIT_BLOCKED';
      } else if (missing.contains(id)) {
        status = ProjectTaskReadinessStatus.blocked;
        reason = 'DEPENDENCY_UNAVAILABLE';
      } else if ((links[id] ?? const <String>{}).isNotEmpty) {
        final cycle = links[id]!.any(
            (target) => _reaches(links, target, id));
        status = ProjectTaskReadinessStatus.blocked;
        reason = cycle ? 'DEPENDENCY_CYCLE' : 'DEPENDENCY_OPEN';
      } else if (item.stage == 'DOING') {
        status = ProjectTaskReadinessStatus.doing;
        reason = 'TASK_DOING';
      } else {
        status = ProjectTaskReadinessStatus.ready;
        reason = item.stage == 'DONE'
            ? 'TASK_STAGE_INCONSISTENT'
            : 'TASK_READY';
      }
      result.add(ProjectTaskReadinessRecord(
        taskId: item.note.id,
        title: item.title,
        status: status,
        reasonCode: reason,
      ));
      if (result.length >= limit) break;
    }
    return List.unmodifiable(result);
  }

  /// Bounded graph walk: all visited nodes belong to the active project.
  /// A graph exceeding the source bound is never silently treated as ready.
  static bool _reaches(
      Map<String, Set<String>> links, String initial, String sought) {
    final pending = <String>[initial];
    final seen = <String>{};
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      if (next == sought) return true;
      if (!seen.add(next)) continue;
      if (seen.length > ProjectWorkspaceRules.maxItemsPerProject) {
        return true;
      }
      pending.addAll(links[next] ?? const <String>{});
    }
    return false;
  }
}
