import 'dart:convert';

import 'calendar_locale.dart';
import 'note.dart';

const _unset = Object();

enum PlannerView { agenda, day, week, month, kanban, focus }

enum PlannerScope { today, upcoming, all, completed }

class TaskSubtask {
  const TaskSubtask({
    required this.id,
    required this.title,
    required this.completed,
  });

  final String id;
  final String title;
  final bool completed;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'completed': completed,
      };

  factory TaskSubtask.fromJson(Map<String, Object?> map) {
    final id = map['id']?.toString().trim() ?? '';
    final title = map['title']?.toString().trim() ?? '';
    final completed = map['completed'];
    if (id.isEmpty || id.length > 200 || title.isEmpty || title.length > 500) {
      throw const FormatException('Sotto-attività non valida.');
    }
    if (completed is! bool) {
      throw const FormatException('Stato sotto-attività non valido.');
    }
    return TaskSubtask(id: id, title: title, completed: completed);
  }
}

class TaskDetails {
  TaskDetails._(Map<String, dynamic> data)
      : _data = Map<String, dynamic>.from(data);

  final Map<String, dynamic> _data;

  factory TaskDetails.empty() => TaskDetails._({
        'due': null,
        'priority': 0,
        'repeat': 'NONE',
        'completedAt': null,
        'linkedNoteId': null,
        'reminderTime': null,
        'stage': 'TODO',
        'reminderAt': null,
        'reminderZone': null,
        'focusHistory': <dynamic>[],
        'focusSeconds': 0,
        'focusReceipts': <dynamic>[],
        'completedCycles': 0,
        'plannedDate': null,
        'plannedTime': null,
        'plannedMinutes': 30,
        'subtasks': <dynamic>[],
      });

  factory TaskDetails.decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Attività non valida.');
    }
    final map = decoded.map((key, value) => MapEntry(key.toString(), value));
    return TaskDetails._(map)..validate();
  }

  static TaskDetails? tryDecode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return TaskDetails.decode(raw);
    } catch (_) {
      return null;
    }
  }

  String? get due => _string('due');
  int get priority => _int('priority') ?? 0;
  String get repeat => (_string('repeat') ?? 'NONE').toUpperCase();
  int? get completedAt => _int('completedAt');
  String? get linkedNoteId => _string('linkedNoteId');
  int get focusSeconds => _int('focusSeconds') ?? 0;
  int get completedCycles => _int('completedCycles') ?? 0;
  String get stage => (_string('stage') ?? 'TODO').toUpperCase();
  int? get reminderAt => _int('reminderAt');
  String? get reminderZone => _string('reminderZone');
  String? get reminderTime => _string('reminderTime');
  String? get plannedDate => _string('plannedDate');
  String? get plannedTime => _string('plannedTime');
  int get plannedMinutes => _int('plannedMinutes') ?? 30;
  bool get completed => completedAt != null;

  List<TaskSubtask> get subtasks {
    final raw = _data['subtasks'];
    if (raw == null) return const [];
    if (raw is! List || raw.length > 100) {
      throw const FormatException('Sotto-attività non valide.');
    }
    return raw.map((value) {
      if (value is! Map) {
        throw const FormatException('Sotto-attività non valida.');
      }
      return TaskSubtask.fromJson(
        value.map((key, value) => MapEntry(key.toString(), value)),
      );
    }).toList(growable: false);
  }

  int get completedSubtasks => subtasks.where((item) => item.completed).length;

  List<String> get focusReceipts {
    final raw = _data['focusReceipts'];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList(growable: false);
  }

  List<Map<String, dynamic>> get focusHistory {
    final raw = _data['focusHistory'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => e.map((key, value) => MapEntry(key.toString(), value)))
        .toList(growable: false);
  }

  String encode() {
    validate();
    return jsonEncode(_data);
  }

  Map<String, dynamic> toMap() => Map<String, dynamic>.from(_data);

  TaskDetails copyWith({
    Object? due = _unset,
    Object? priority = _unset,
    Object? repeat = _unset,
    Object? completedAt = _unset,
    Object? linkedNoteId = _unset,
    Object? reminderTime = _unset,
    Object? stage = _unset,
    Object? reminderAt = _unset,
    Object? reminderZone = _unset,
    Object? focusHistory = _unset,
    Object? focusSeconds = _unset,
    Object? focusReceipts = _unset,
    Object? completedCycles = _unset,
    Object? plannedDate = _unset,
    Object? plannedTime = _unset,
    Object? plannedMinutes = _unset,
    Object? subtasks = _unset,
  }) {
    final next = Map<String, dynamic>.from(_data);
    void set(String key, Object? value) {
      if (!identical(value, _unset)) next[key] = value;
    }

    set('due', due);
    set('priority', priority);
    set('repeat', repeat);
    set('completedAt', completedAt);
    set('linkedNoteId', linkedNoteId);
    set('reminderTime', reminderTime);
    set('stage', stage);
    set('reminderAt', reminderAt);
    set('reminderZone', reminderZone);
    set('focusHistory', focusHistory);
    set('focusSeconds', focusSeconds);
    set('focusReceipts', focusReceipts);
    set('completedCycles', completedCycles);
    set('plannedDate', plannedDate);
    set('plannedTime', plannedTime);
    set('plannedMinutes', plannedMinutes);
    set(
      'subtasks',
      identical(subtasks, _unset)
          ? _unset
          : (subtasks as List<TaskSubtask>)
              .map((item) => item.toJson())
              .toList(growable: false),
    );
    if (identical(next['subtasks'], _unset)) {
      next['subtasks'] = _data['subtasks'];
    }

    return TaskDetails._(next)..validate();
  }

  TaskDetails schedule({
    required DateTime date,
    String? time,
    int? minutes,
  }) {
    final normalizedTime = time?.trim().isEmpty == true ? null : time?.trim();
    if (normalizedTime != null) _validateTime(normalizedTime);
    final duration = minutes ?? plannedMinutes;
    if (duration < 5 || duration > 720) {
      throw const FormatException('Durata tra 5 e 720 minuti richiesta.');
    }
    return copyWith(
      plannedDate: dateKey(date),
      plannedTime: normalizedTime,
      plannedMinutes: duration,
    );
  }

  TaskDetails unschedule() => copyWith(
        plannedDate: null,
        plannedTime: null,
        plannedMinutes: 30,
      );

  TaskDetails withEditorValues({
    required String? due,
    required int priority,
    required String repeat,
    required String? linkedNoteId,
    required String? plannedDate,
    required String? plannedTime,
    required int plannedMinutes,
  }) {
    final normalizedDue = due?.trim().isEmpty == true ? null : due?.trim();
    final normalizedPlannedDate =
        plannedDate?.trim().isEmpty == true ? null : plannedDate?.trim();
    final normalizedPlannedTime =
        plannedTime?.trim().isEmpty == true ? null : plannedTime?.trim();

    if (normalizedDue != null) _validateDate(normalizedDue, 2000, 2200);
    if (normalizedPlannedDate != null) {
      _validateDate(normalizedPlannedDate, 2000, 2200);
    }
    if (normalizedPlannedTime != null) _validateTime(normalizedPlannedTime);
    if (priority < 0 || priority > 3) {
      throw const FormatException('Priorità non valida.');
    }

    final normalizedRepeat = repeat.toUpperCase();
    if (!const {'NONE', 'DAILY', 'WEEKLY', 'MONTHLY'}
        .contains(normalizedRepeat)) {
      throw const FormatException('Ricorrenza non valida.');
    }
    if (normalizedRepeat != 'NONE' && normalizedDue == null) {
      throw const FormatException('La ricorrenza richiede una scadenza.');
    }
    if (normalizedPlannedTime != null && normalizedPlannedDate == null) {
      throw const FormatException(
          'Un orario pianificato richiede anche il giorno.');
    }
    if (plannedMinutes < 5 || plannedMinutes > 720) {
      throw const FormatException('Durata del blocco non valida.');
    }

    return copyWith(
      due: normalizedDue,
      priority: priority,
      repeat: normalizedRepeat,
      linkedNoteId: linkedNoteId?.trim().isEmpty == true ? null : linkedNoteId,
      plannedDate: normalizedPlannedDate,
      plannedTime: normalizedPlannedTime,
      plannedMinutes: plannedMinutes,
    );
  }

  TaskDetails toggleCompleted({
    required bool completed,
    required DateTime today,
    int? nowMillis,
  }) {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    if (!completed) return copyWith(completedAt: null);

    if (repeat == 'NONE') {
      return copyWith(
        completedAt: now,
        reminderAt: null,
        reminderZone: null,
        reminderTime: null,
      );
    }

    final dueDate = parseDate(due);
    if (dueDate == null) {
      throw const FormatException('La ricorrenza richiede una scadenza.');
    }

    var next = dueDate;
    do {
      switch (repeat) {
        case 'DAILY':
          next = next.add(const Duration(days: 1));
          break;
        case 'WEEKLY':
          next = next.add(const Duration(days: 7));
          break;
        case 'MONTHLY':
          next = addMonths(next, 1);
          break;
      }
    } while (!isAfterDay(next, today));

    int? nextReminderAt;
    if (reminderAt != null) {
      final old = DateTime.fromMillisecondsSinceEpoch(reminderAt!);
      nextReminderAt = DateTime(
        next.year,
        next.month,
        next.day,
        old.hour,
        old.minute,
        old.second,
        old.millisecond,
        old.microsecond,
      ).millisecondsSinceEpoch;
    }

    return copyWith(
      due: dateKey(next),
      completedAt: null,
      completedCycles: completedCycles + 1,
      stage: 'TODO',
      reminderAt: nextReminderAt,
      plannedDate: null,
      plannedTime: null,
      plannedMinutes: 30,
    );
  }

  TaskDetails addFocusSession({
    required String sessionId,
    required int seconds,
    required int endedAt,
  }) {
    if (seconds < 1 || seconds > 7200) {
      throw const FormatException('Sessione focus non valida.');
    }
    if (focusReceipts.contains(sessionId)) return this;
    if (focusReceipts.length >= 200) {
      throw const FormatException(
          'Limite di 200 sessioni per attività raggiunto.');
    }

    final receipts = [...focusReceipts, sessionId];
    final history = [
      ...focusHistory,
      {'id': sessionId, 'seconds': seconds, 'endedAt': endedAt},
    ];

    return copyWith(
      focusSeconds: focusSeconds + seconds,
      focusReceipts: receipts,
      focusHistory: history,
    );
  }

  void validate() {
    if (priority < 0 || priority > 3) {
      throw const FormatException('Priorità non valida.');
    }
    if (due != null) _validateDate(due!, 2000, 2200);
    if (plannedDate != null) _validateDate(plannedDate!, 2000, 2200);
    if (plannedTime != null) _validateTime(plannedTime!);
    if (plannedTime != null && plannedDate == null) {
      throw const FormatException(
          'Un orario pianificato richiede anche il giorno.');
    }
    if (plannedMinutes < 5 || plannedMinutes > 720) {
      throw const FormatException('Durata del blocco non valida.');
    }
    final seenSubtasks = <String>{};
    for (final item in subtasks) {
      if (!seenSubtasks.add(item.id)) {
        throw const FormatException('Sotto-attività duplicate.');
      }
    }
    if (!const {'NONE', 'DAILY', 'WEEKLY', 'MONTHLY'}.contains(repeat)) {
      throw const FormatException('Ricorrenza non valida.');
    }
    if (repeat != 'NONE' && due == null) {
      throw const FormatException('La ricorrenza richiede una scadenza.');
    }
  }

  String? _string(String key) {
    final value = _data[key];
    return value?.toString();
  }

  int? _int(String key) {
    final value = _data[key];
    return value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
  }

  static void _validateDate(String value, int minYear, int maxYear) {
    final parsed = parseDate(value);
    if (parsed == null || parsed.year < minYear || parsed.year > maxYear) {
      throw FormatException('Data tra $minYear e $maxYear richiesta.');
    }
  }

  static void _validateTime(String value) {
    if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
      throw const FormatException('Orario non valido.');
    }
  }
}

class PlannerIndex {
  const PlannerIndex({
    required this.planned,
    required this.due,
    required this.unplanned,
  });

  final Map<String, List<Note>> planned;
  final Map<String, List<Note>> due;
  final List<Note> unplanned;
}

class TimeBlock {
  const TimeBlock({
    required this.note,
    required this.date,
    required this.startMinutes,
    required this.minutes,
  });

  final Note note;
  final DateTime date;
  final int? startMinutes;
  final int minutes;

  int? get endMinutes => startMinutes == null ? null : startMinutes! + minutes;
}

class PlannerCollision {
  const PlannerCollision(this.firstTaskId, this.secondTaskId);
  final String firstTaskId;
  final String secondTaskId;
}

abstract final class PlannerPro {
  static PlannerIndex index(List<Note> notes) {
    final planned = <String, List<Note>>{};
    final due = <String, List<Note>>{};
    final unplanned = <Note>[];
    final details = <String, TaskDetails>{};

    for (final note in notes) {
      final task = TaskDetails.tryDecode(note.taskJson);
      if (task == null || note.isDeleted || note.archived || task.completed) {
        continue;
      }
      details[note.id] = task;
      if (task.plannedDate == null) {
        unplanned.add(note);
      } else {
        planned.putIfAbsent(task.plannedDate!, () => <Note>[]).add(note);
      }
      if (task.due != null) {
        due.putIfAbsent(task.due!, () => <Note>[]).add(note);
      }
    }

    int comparePlanned(Note a, Note b) {
      final ta = details[a.id]!;
      final tb = details[b.id]!;
      final time =
          (ta.plannedTime ?? '99:99').compareTo(tb.plannedTime ?? '99:99');
      if (time != 0) return time;
      final priority = tb.priority.compareTo(ta.priority);
      if (priority != 0) return priority;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    }

    int compareDue(Note a, Note b) {
      final pa = details[a.id]?.priority ?? 0;
      final pb = details[b.id]?.priority ?? 0;
      return pb.compareTo(pa);
    }

    for (final list in planned.values) {
      list.sort(comparePlanned);
    }
    for (final list in due.values) {
      list.sort(compareDue);
    }
    unplanned.sort((a, b) {
      final ta = details[a.id]!;
      final tb = details[b.id]!;
      final dueCompare =
          (ta.due ?? '9999-12-31').compareTo(tb.due ?? '9999-12-31');
      if (dueCompare != 0) return dueCompare;
      final priority = tb.priority.compareTo(ta.priority);
      if (priority != 0) return priority;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    return PlannerIndex(planned: planned, due: due, unplanned: unplanned);
  }

  static List<Note> agenda(
    List<Note> notes,
    PlannerScope scope,
    DateTime today,
  ) {
    final todayKey = dateKey(today);
    final result = <Note>[];
    final details = <String, TaskDetails>{};
    for (final note in notes) {
      final task = TaskDetails.tryDecode(note.taskJson);
      if (task == null || note.isDeleted || note.archived) continue;
      details[note.id] = task;
      final include = switch (scope) {
        PlannerScope.today => !task.completed &&
            (task.plannedDate == todayKey ||
                (task.due != null && task.due!.compareTo(todayKey) <= 0)),
        PlannerScope.upcoming => !task.completed &&
            ((task.plannedDate?.compareTo(todayKey) ?? -1) > 0 ||
                (task.due?.compareTo(todayKey) ?? -1) > 0),
        PlannerScope.all => !task.completed,
        PlannerScope.completed => task.completed,
      };
      if (include) result.add(note);
    }

    result.sort((a, b) {
      final ta = details[a.id]!;
      final tb = details[b.id]!;
      final da = ta.plannedDate ?? ta.due ?? '9999-12-31';
      final db = tb.plannedDate ?? tb.due ?? '9999-12-31';
      final date = da.compareTo(db);
      if (date != 0) return date;
      final time =
          (ta.plannedTime ?? '99:99').compareTo(tb.plannedTime ?? '99:99');
      if (time != 0) return time;
      return tb.priority.compareTo(ta.priority);
    });
    return result;
  }

  static List<Note> dayNotes(PlannerIndex index, DateTime date) =>
      index.planned[dateKey(date)] ?? const [];

  static List<Note> dueOn(PlannerIndex index, DateTime date) =>
      index.due[dateKey(date)] ?? const [];

  static List<TimeBlock> timeBlocks(PlannerIndex index, DateTime date) =>
      dayNotes(index, date).map((note) {
        final task = TaskDetails.tryDecode(note.taskJson)!;
        return TimeBlock(
          note: note,
          date: dateOnly(date),
          startMinutes: parseTimeMinutes(task.plannedTime),
          minutes: task.plannedMinutes,
        );
      }).toList(growable: false);

  static List<PlannerCollision> collisions(List<TimeBlock> blocks) {
    final timed = blocks.where((b) => b.startMinutes != null).toList();
    final result = <PlannerCollision>[];
    for (var i = 0; i < timed.length; i++) {
      final a = timed[i];
      for (var j = i + 1; j < timed.length; j++) {
        final b = timed[j];
        if (a.startMinutes! < b.endMinutes! &&
            b.startMinutes! < a.endMinutes!) {
          result.add(PlannerCollision(a.note.id, b.note.id));
        }
      }
    }
    return result;
  }

  static List<DateTime> weekDays(DateTime date) => appCalendar.weekDays(date);

  static List<DateTime> monthGrid(DateTime month) =>
      appCalendar.monthGrid(month);
}

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

DateTime? parseDate(String? value) {
  if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return null;
  }
  final parts = value.split('-').map(int.parse).toList();
  final parsed = DateTime(parts[0], parts[1], parts[2]);
  if (dateKey(parsed) != value) return null;
  return parsed;
}

int? parseTimeMinutes(String? value) {
  if (value == null ||
      !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
    return null;
  }
  final parts = value.split(':').map(int.parse).toList();
  return parts[0] * 60 + parts[1];
}

String timeLabel(int minutes) {
  final normalized = minutes.clamp(0, 24 * 60 - 1);
  return '${(normalized ~/ 60).toString().padLeft(2, '0')}:${(normalized % 60).toString().padLeft(2, '0')}';
}

bool isAfterDay(DateTime a, DateTime b) => dateOnly(a).isAfter(dateOnly(b));

DateTime addMonths(DateTime date, int months) {
  final zeroBased = date.year * 12 + date.month - 1 + months;
  final year = zeroBased ~/ 12;
  final month = zeroBased % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, date.day.clamp(1, lastDay).toInt());
}
