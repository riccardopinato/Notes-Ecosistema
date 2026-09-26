import 'note.dart';
import 'planner.dart';

class WorkdayItem {
  const WorkdayItem({
    required this.note,
    required this.time,
  });

  final Note note;
  final String? time;
}

class WorkdayBriefing {
  const WorkdayBriefing({
    required this.items,
    required this.dueToday,
    required this.overdue,
    required this.inbox,
    required this.sharedUnread,
  });

  final List<WorkdayItem> items;
  final int dueToday;
  final int overdue;
  final List<Note> inbox;
  final int sharedUnread;

  int get openToday => dueToday + overdue;
  bool get empty =>
      items.isEmpty && openToday == 0 && inbox.isEmpty && sharedUnread == 0;
}

abstract final class Workday {
  static WorkdayBriefing build({
    required List<Note> notes,
    required DateTime now,
    int sharedUnread = 0,
  }) {
    final today = dateKey(now);
    var dueToday = 0;
    var overdue = 0;
    final items = <WorkdayItem>[];
    final inbox = <Note>[];

    for (final note in notes) {
      if (note.isDeleted || note.archived) continue;

      if (!note.isTask && !note.isVisual && note.collectionId == null) {
        inbox.add(note);
      }

      final task = TaskDetails.tryDecode(note.taskJson);
      if (task == null || task.completed) continue;

      if (task.due == today) {
        dueToday++;
      } else if (task.due != null && task.due!.compareTo(today) < 0) {
        overdue++;
      }

      if (task.plannedDate == today) {
        items.add(WorkdayItem(note: note, time: task.plannedTime));
      }
    }

    items.sort((a, b) {
      final ta = a.time;
      final tb = b.time;
      if (ta == null && tb != null) return 1;
      if (ta != null && tb == null) return -1;
      if (ta != null && tb != null) {
        final byTime = ta.compareTo(tb);
        if (byTime != 0) return byTime;
      }
      final pa = TaskDetails.tryDecode(a.note.taskJson)?.priority ?? 0;
      final pb = TaskDetails.tryDecode(b.note.taskJson)?.priority ?? 0;
      final byPriority = pb.compareTo(pa);
      if (byPriority != 0) return byPriority;
      return a.note.title.toLowerCase().compareTo(b.note.title.toLowerCase());
    });

    inbox.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return WorkdayBriefing(
      items: items,
      dueToday: dueToday,
      overdue: overdue,
      inbox: inbox.take(5).toList(growable: false),
      sharedUnread: sharedUnread < 0 ? 0 : sharedUnread,
    );
  }
}
