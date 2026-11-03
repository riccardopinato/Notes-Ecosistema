import 'calendar_locale.dart';
import 'note.dart';
import 'planner.dart';

/// Read-only projections on the existing canonical TaskDetails.
enum EisenhowerGroup {
  urgentImportant,
  importantNotUrgent,
  urgentNotImportant,
  notUrgentNotImportant,
  needsDetails,
}

class PlannerWeekSnapshot {
  const PlannerWeekSnapshot({
    required this.weekStart,
    required this.completedThisWeek,
    required this.dueThisWeek,
    required this.overdueBeforeWeek,
    required this.highPriorityOpen,
    required this.missingDueDate,
  });

  final DateTime weekStart;
  final List<Note> completedThisWeek;
  final List<Note> dueThisWeek;
  final List<Note> overdueBeforeWeek;
  final List<Note> highPriorityOpen;
  final List<Note> missingDueDate;
}

abstract final class PlannerInsights {
  static Map<EisenhowerGroup, List<Note>> eisenhower(
    List<Note> notes,
    DateTime today, {
    int urgentWithinDays = 2,
  }) {
    if (urgentWithinDays < 0 || urgentWithinDays > 14) {
      throw const FormatException('Soglia urgenza non valida.');
    }
    final result = {
      for (final group in EisenhowerGroup.values) group: <Note>[],
    };
    final date = DateTime(today.year, today.month, today.day);
    for (final note in notes) {
      final task = TaskDetails.tryDecode(note.taskJson);
      if (task == null || note.isDeleted || note.archived || task.completed) {
        continue;
      }
      // Zero is unassigned, not proof that a task is unimportant.
      final important =
          task.priority >= 2 ? true : (task.priority == 1 ? false : null);
      final due = parseDate(task.due);
      if (due == null || important == null) {
        result[EisenhowerGroup.needsDetails]!.add(note);
        continue;
      }
      final urgent = due.difference(date).inDays <= urgentWithinDays;
      final group = switch ((urgent, important)) {
        (true, true) => EisenhowerGroup.urgentImportant,
        (false, true) => EisenhowerGroup.importantNotUrgent,
        (true, false) => EisenhowerGroup.urgentNotImportant,
        (false, false) => EisenhowerGroup.notUrgentNotImportant,
      };
      result[group]!.add(note);
    }
    return {
      for (final group in EisenhowerGroup.values)
        group: List<Note>.unmodifiable(result[group]!),
    };
  }

  static PlannerWeekSnapshot weeklyReview(
    List<Note> notes,
    DateTime today,
  ) {
    final start = appCalendar.startOfWeek(today);
    final end = start.add(const Duration(days: 7));
    final startMillis = start.millisecondsSinceEpoch;
    final endMillis = end.millisecondsSinceEpoch;
    final completed = <Note>[];
    final due = <Note>[];
    final overdue = <Note>[];
    final highPriority = <Note>[];
    final missingDate = <Note>[];

    for (final note in notes) {
      final task = TaskDetails.tryDecode(note.taskJson);
      if (task == null || note.isDeleted || note.archived) continue;
      // Only a real completedAt counts: updatedAt is NOT a completion date.
      final completedAt = task.completedAt;
      if (completedAt != null &&
          completedAt >= startMillis &&
          completedAt < endMillis) {
        completed.add(note);
      }
      if (task.completed) continue;
      final deadline = parseDate(task.due);
      if (deadline == null) {
        missingDate.add(note);
      } else if (deadline.isBefore(start)) {
        overdue.add(note);
      } else if (deadline.isBefore(end)) {
        due.add(note);
      }
      if (task.priority >= 2) highPriority.add(note);
    }
    return PlannerWeekSnapshot(
      weekStart: start,
      completedThisWeek: List.unmodifiable(completed),
      dueThisWeek: List.unmodifiable(due),
      overdueBeforeWeek: List.unmodifiable(overdue),
      highPriorityOpen: List.unmodifiable(highPriority),
      missingDueDate: List.unmodifiable(missingDate),
    );
  }
}
