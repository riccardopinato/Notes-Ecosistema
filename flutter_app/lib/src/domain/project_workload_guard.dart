import 'project_workspace.dart';

/// Bounded, read-only workload derived from already-authorized project items.
/// Unknown duration must not be silently treated as a fact.
class ProjectWorkloadResult {
  const ProjectWorkloadResult({
    required this.scheduledMinutes,
    required this.scheduledTasks,
    required this.unknownDurationTasks,
    required this.blockedTasks,
    required this.inProgressTasks,
    required this.reasonCode,
  });
  final int scheduledMinutes;
  final int scheduledTasks;
  final int unknownDurationTasks;
  final int blockedTasks;
  final int inProgressTasks;
  final String reasonCode;
}

abstract final class ProjectWorkloadGuard {
  static ProjectWorkloadResult evaluate(
    Iterable<ProjectWorkItem> items, {
    required String civilDay,
    required int capacityMinutes,
    required int wipLimit,
  }) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(civilDay) ||
        capacityMinutes < 30 ||
        capacityMinutes > 720 ||
        wipLimit < 1 ||
        wipLimit > 20) {
      throw const FormatException('INVALID_WORKLOAD_POLICY');
    }
    final active = items
        .where((item) =>
            item.kind == ProjectWorkItemKind.task &&
            !item.note.isDeleted &&
            !item.note.archived &&
            !item.completed)
        .toList(growable: false);
    var minutes = 0;
    var scheduled = 0;
    var unknown = 0;
    var doing = 0;
    var blocked = 0;
    for (final item in active) {
      if (item.stage == 'DOING') doing++;
      if (item.note.tags.any((tag) => tag.trim().toLowerCase() == 'blocked')) {
        blocked++;
      }
      if (item.plannedDate != civilDay) continue;
      if (item.plannedTime == null) {
        unknown++;
      } else if (item.plannedMinutes >= 5 && item.plannedMinutes <= 720) {
        minutes += item.plannedMinutes;
        scheduled++;
      } else {
        unknown++;
      }
    }
    final reason = minutes > capacityMinutes
        ? 'SCHEDULED_MINUTES_OVER_BUDGET'
        : doing > wipLimit
            ? 'WIP_LIMIT_EXCEEDED'
            : blocked > 0
                ? 'EXPLICIT_BLOCKED_TAGS'
                : unknown > 0
                    ? 'SCHEDULED_DURATION_UNKNOWN'
                    : 'NO_DETECTED_PRESSURE';
    return ProjectWorkloadResult(
      scheduledMinutes: minutes,
      scheduledTasks: scheduled,
      unknownDurationTasks: unknown,
      blockedTasks: blocked,
      inProgressTasks: doing,
      reasonCode: reason,
    );
  }
}
