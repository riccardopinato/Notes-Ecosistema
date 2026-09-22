import 'note.dart';
import 'planner.dart';

class DiaryEntry {
  const DiaryEntry({required this.note, required this.date});
  final Note note;
  final DateTime date;
}

class DiaryIndex {
  const DiaryIndex({
    required this.entries,
    required this.days,
    required this.tasks,
  });

  final List<DiaryEntry> entries;
  final Map<String, List<DiaryEntry>> days;
  final Map<String, List<Note>> tasks;
}

abstract final class Diary {
  static const prefix = 'diario_';

  static DateTime validDate(String value) {
    final parsed = parseDate(value);
    if (parsed == null || parsed.year < 1900 || parsed.year > 2200) {
      throw const FormatException('Usa una data AAAA-MM-GG tra 1900 e 2200.');
    }
    return parsed;
  }

  static DateTime? tagDate(String tag) {
    if (!tag.startsWith(prefix)) return null;
    try {
      return validDate(tag.substring(prefix.length));
    } catch (_) {
      return null;
    }
  }

  static DateTime? date(List<String> tags) {
    final dates = tags.map(tagDate).whereType<DateTime>().map(dateKey).toSet();
    if (dates.length != 1) return null;
    return parseDate(dates.single);
  }

  static List<String> datedTags(List<String> tags, DateTime? date) {
    final user = tags.where((tag) => tagDate(tag) == null);
    final next = <String>{...user.map((e) => e.trim()).where((e) => e.isNotEmpty)};
    if (date != null) {
      validDate(dateKey(date));
      next.add('$prefix${dateKey(date)}');
    }
    return next.toList(growable: false);
  }

  static List<String> userTags(List<String> tags) =>
      tags.where((tag) => tagDate(tag) == null).toList(growable: false);

  static DateTime? noteDate(Note note) {
    if (note.isDeleted || note.isTask || note.isVisual) return null;
    return date(note.tags);
  }

  static List<DateTime?> monthCells(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final offset = first.weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final size = ((offset + days + 6) ~/ 7) * 7;
    return List.generate(size, (index) {
      final day = index - offset + 1;
      return day >= 1 && day <= days ? DateTime(month.year, month.month, day) : null;
    });
  }

  static DiaryIndex index(List<Note> notes, {String? collectionId}) {
    final entries = <DiaryEntry>[];
    final days = <String, List<DiaryEntry>>{};
    final tasks = <String, List<Note>>{};

    for (final note in notes) {
      final date = noteDate(note);
      if (date != null &&
          (collectionId == null || note.collectionId == collectionId)) {
        final entry = DiaryEntry(note: note, date: date);
        entries.add(entry);
        days.putIfAbsent(dateKey(date), () => <DiaryEntry>[]).add(entry);
      }

      final task = TaskDetails.tryDecode(note.taskJson);
      if (!note.isDeleted && !note.archived && task?.due != null) {
        tasks.putIfAbsent(task!.due!, () => <Note>[]).add(note);
      }
    }

    entries.sort((a, b) {
      final day = b.date.compareTo(a.date);
      if (day != 0) return day;
      final created = b.note.createdAt.compareTo(a.note.createdAt);
      if (created != 0) return created;
      return a.note.id.compareTo(b.note.id);
    });

    for (final list in days.values) {
      list.sort((a, b) {
        final created = b.note.createdAt.compareTo(a.note.createdAt);
        if (created != 0) return created;
        return a.note.id.compareTo(b.note.id);
      });
    }

    return DiaryIndex(entries: entries, days: days, tasks: tasks);
  }
}
