import 'note.dart';

/// Read-only, bounded Home projection over the caller's already-authorized
/// canonical notes. Never owns state or writes a second copy of user data.
class HomeUi5Projection {
  const HomeUi5Projection({
    required this.pageCount,
    required this.pendingTasks,
    required this.recentPages,
  });

  final int pageCount;
  final int pendingTasks;
  final List<Note> recentPages;

  static HomeUi5Projection fromNotes(
    Iterable<Note> visibleNotes, {
    int recentLimit = 3,
  }) {
    if (recentLimit < 0 || recentLimit > 10) {
      throw const FormatException('INVALID_HOME_RECENT_LIMIT');
    }

    var pages = 0;
    var tasks = 0;
    final recent = <Note>[];
    for (final note in visibleNotes) {
      if (note.isDeleted || note.archived) continue;
      if (note.isTask) {
        if (!note.taskCompleted) tasks++;
        continue;
      }
      pages++;

      if (recentLimit == 0) continue;
      final index = recent.indexWhere((item) =>
          note.updatedAt > item.updatedAt ||
          (note.updatedAt == item.updatedAt &&
              note.id.compareTo(item.id) < 0));
      if (index >= 0) {
        recent.insert(index, note);
      } else if (recent.length < recentLimit) {
        recent.add(note);
      }
      if (recent.length > recentLimit) recent.removeLast();
    }

    return HomeUi5Projection(
      pageCount: pages,
      pendingTasks: tasks,
      recentPages: List.unmodifiable(recent),
    );
  }
}
