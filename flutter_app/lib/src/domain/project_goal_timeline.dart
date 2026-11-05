import 'project_workspace.dart';

class ProjectGoalPlanEntry {
  const ProjectGoalPlanEntry({
    required this.taskId,
    required this.title,
    required this.date,
    required this.minutes,
  });
  final String taskId;
  final String title;
  final String date;
  final int minutes;
}

/// Read-only reverse-planning for an explicitly entered estimate and capacity.
/// The projection makes no claim about meetings, holidays or real availability.
abstract final class ProjectGoalTimeline {
  static List<ProjectGoalPlanEntry> backplan(
    Iterable<ProjectWorkItem> items, {
    required String deadline,
    required int minutesPerTask,
    required int minutesPerDay,
  }) {
    final when = _date(deadline);
    if (when == null ||
        minutesPerTask < 5 ||
        minutesPerTask > 720 ||
        minutesPerDay < 30 ||
        minutesPerDay > 720 ||
        minutesPerTask > minutesPerDay) {
      throw const FormatException('TIMELINE_INVALID_USER_CONSTRAINTS');
    }
    final active = items
        .where((item) =>
            item.kind == ProjectWorkItemKind.task &&
            !item.note.isDeleted &&
            !item.note.archived &&
            !item.completed)
        .toList(growable: false);
    if (active.isEmpty || active.length > 500) {
      throw const FormatException('TIMELINE_TASK_COUNT_UNSUPPORTED');
    }
    final byId = <String, ProjectWorkItem>{};
    for (final item in active) {
      final id = item.note.id.toLowerCase();
      if (byId.containsKey(id)) {
        throw const FormatException('TIMELINE_DUPLICATE_TASK');
      }
      byId[id] = item;
    }
    final all = <String, ProjectWorkItem>{};
    for (final item in items) {
      if (item.kind != ProjectWorkItemKind.task ||
          item.note.isDeleted ||
          item.note.archived) continue;
      final id = item.note.id.toLowerCase();
      if (all.containsKey(id)) {
        throw const FormatException('TIMELINE_DUPLICATE_TASK');
      }
      all[id] = item;
    }

    final order = <String>[];
    final visiting = <String>{};
    final visited = <String>{};
    void visit(String id) {
      if (visiting.contains(id)) {
        throw const FormatException('TIMELINE_DEPENDENCY_CYCLE');
      }
      if (visited.contains(id)) return;
      visiting.add(id);
      for (final tag in byId[id]!.note.tags) {
        if (!tag.toLowerCase().startsWith('dep_')) continue;
        final target = tag.substring(4).toLowerCase();
        if (all[target] == null) {
          throw const FormatException('TIMELINE_MISSING_DEPENDENCY');
        }
        if (all[target]!.completed) continue;
        if (!byId.containsKey(target)) {
          throw const FormatException('TIMELINE_UNAVAILABLE_DEPENDENCY');
        }
        visit(target);
      }
      visiting.remove(id);
      visited.add(id);
      order.add(id);
    }

    for (final id in byId.keys) {
      visit(id);
    }
    var current = when;
    while (current.weekday == DateTime.saturday ||
        current.weekday == DateTime.sunday) {
      current = current.subtract(const Duration(days: 1));
    }
    var remaining = minutesPerDay;
    final scheduled = <String, ProjectGoalPlanEntry>{};
    for (final id in order.reversed) {
      if (remaining < minutesPerTask) {
        do {
          current = current.subtract(const Duration(days: 1));
        } while (current.weekday == DateTime.saturday ||
            current.weekday == DateTime.sunday);
        remaining = minutesPerDay;
      }
      final item = byId[id]!;
      scheduled[id] = ProjectGoalPlanEntry(
        taskId: item.note.id,
        title: item.title,
        date: _key(current),
        minutes: minutesPerTask,
      );
      remaining -= minutesPerTask;
    }
    return List.unmodifiable([
      for (final id in order) scheduled[id]!,
    ]);
  }

  static DateTime? _date(String text) {
    if (!RegExp(r'^20\d{2}-\d{2}-\d{2}$').hasMatch(text)) return null;
    final p = text.split('-').map(int.parse).toList();
    final date = DateTime(p[0], p[1], p[2]);
    if (date.year != p[0] || date.month != p[1] || date.day != p[2])
      return null;
    return date;
  }

  static String _key(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
