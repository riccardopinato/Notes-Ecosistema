import 'dart:convert';

import 'note.dart';
import 'planner.dart';

enum FocusPhase { work, breakTime }

class FocusClock {
  const FocusClock({
    required this.sessionId,
    required this.taskId,
    required this.durationSeconds,
    required this.deadline,
    this.pausedMillis,
    this.phase = FocusPhase.work,
    this.workMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.completedBlocks = 0,
  });

  final String sessionId;
  final String taskId;
  final int durationSeconds;
  final int deadline;
  final int? pausedMillis;
  final FocusPhase phase;
  final int workMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;
  final int completedBlocks;

  int remainingMillis(int now) =>
      (pausedMillis ?? (deadline - now))
          .clamp(0, durationSeconds * 1000)
          .toInt();

  int remaining(int now) => (remainingMillis(now) + 999) ~/ 1000;
  bool finished(int now) => remainingMillis(now) == 0;

  FocusClock pause(int now) {
    if (pausedMillis != null || finished(now)) {
      throw const FormatException('Sessione Focus non sospendibile.');
    }
    return copyWith(pausedMillis: remainingMillis(now));
  }

  FocusClock resume(int now) {
    final remaining = pausedMillis;
    if (remaining == null) {
      throw const FormatException('Sessione Focus non in pausa.');
    }
    return copyWith(
      deadline: now + remaining,
      pausedMillis: null,
    );
  }

  FocusClock next(int now, String id) {
    if (!finished(now) || id.trim().isEmpty) {
      throw const FormatException('Intervallo Focus non concluso.');
    }
    final count =
        phase == FocusPhase.work ? completedBlocks + 1 : completedBlocks;
    final minutes = phase == FocusPhase.breakTime
        ? workMinutes
        : count % 4 == 0
            ? longBreakMinutes
            : shortBreakMinutes;
    return FocusClock(
      sessionId: id,
      taskId: taskId,
      durationSeconds: minutes * 60,
      deadline: now + minutes * 60000,
      phase:
          phase == FocusPhase.work ? FocusPhase.breakTime : FocusPhase.work,
      workMinutes: workMinutes,
      shortBreakMinutes: shortBreakMinutes,
      longBreakMinutes: longBreakMinutes,
      completedBlocks: count,
    ).validate();
  }

  FocusClock copyWith({
    String? sessionId,
    String? taskId,
    int? durationSeconds,
    int? deadline,
    Object? pausedMillis = _unset,
    FocusPhase? phase,
    int? workMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? completedBlocks,
  }) =>
      FocusClock(
        sessionId: sessionId ?? this.sessionId,
        taskId: taskId ?? this.taskId,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        deadline: deadline ?? this.deadline,
        pausedMillis: identical(pausedMillis, _unset)
            ? this.pausedMillis
            : pausedMillis as int?,
        phase: phase ?? this.phase,
        workMinutes: workMinutes ?? this.workMinutes,
        shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
        longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
        completedBlocks: completedBlocks ?? this.completedBlocks,
      );

  FocusClock validate() {
    if (sessionId.trim().isEmpty ||
        sessionId.length > 80 ||
        taskId.trim().isEmpty ||
        taskId.length > 200 ||
        durationSeconds < 1 ||
        durationSeconds > 7200 ||
        deadline < 0 ||
        (pausedMillis != null &&
            (pausedMillis! < 0 ||
                pausedMillis! > durationSeconds * 1000)) ||
        workMinutes < 1 ||
        workMinutes > 120 ||
        shortBreakMinutes < 1 ||
        shortBreakMinutes > 60 ||
        longBreakMinutes < 1 ||
        longBreakMinutes > 60 ||
        completedBlocks < 0 ||
        completedBlocks > 1000000) {
      throw const FormatException('Sessione Focus non valida.');
    }
    return this;
  }

  String encode() {
    validate();
    return jsonEncode({
      'version': 1,
      'sessionId': sessionId,
      'taskId': taskId,
      'durationSeconds': durationSeconds,
      'deadline': deadline,
      'pausedMillis': pausedMillis,
      'phase': phase == FocusPhase.work ? 'WORK' : 'BREAK',
      'workMinutes': workMinutes,
      'shortBreakMinutes': shortBreakMinutes,
      'longBreakMinutes': longBreakMinutes,
      'completedBlocks': completedBlocks,
    });
  }

  static FocusClock decode(String raw) {
    final map = jsonDecode(raw);
    if (map is! Map || map['version'] != 1) {
      throw const FormatException('Formato Focus non supportato.');
    }
    return FocusClock(
      sessionId: map['sessionId']?.toString() ?? '',
      taskId: map['taskId']?.toString() ?? '',
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      deadline: (map['deadline'] as num?)?.toInt() ?? 0,
      pausedMillis: (map['pausedMillis'] as num?)?.toInt(),
      phase: map['phase']?.toString() == 'BREAK'
          ? FocusPhase.breakTime
          : FocusPhase.work,
      workMinutes: (map['workMinutes'] as num?)?.toInt() ?? 25,
      shortBreakMinutes:
          (map['shortBreakMinutes'] as num?)?.toInt() ?? 5,
      longBreakMinutes:
          (map['longBreakMinutes'] as num?)?.toInt() ?? 15,
      completedBlocks: (map['completedBlocks'] as num?)?.toInt() ?? 0,
    ).validate();
  }

  static FocusClock start({
    required String sessionId,
    required String taskId,
    required int minutes,
    required int now,
    int shortBreak = 5,
    int longBreak = 15,
  }) {
    if (minutes < 1 || minutes > 120 || now < 0) {
      throw const FormatException('Durata Focus non valida.');
    }
    return FocusClock(
      sessionId: sessionId,
      taskId: taskId,
      durationSeconds: minutes * 60,
      deadline: now + minutes * 60000,
      workMinutes: minutes,
      shortBreakMinutes: shortBreak,
      longBreakMinutes: longBreak,
    ).validate();
  }
}

const _unset = Object();

enum TaskStatus { todo, doing, waiting, done }

TaskStatus taskStatus(TaskDetails details) {
  if (details.completed) return TaskStatus.done;
  return switch (details.stage) {
    'DOING' => TaskStatus.doing,
    'WAITING' => TaskStatus.waiting,
    _ => TaskStatus.todo,
  };
}

TaskDetails changeTaskStatus(
  TaskDetails details,
  TaskStatus status, {
  required int now,
  required DateTime today,
}) {
  if (status == TaskStatus.done) {
    return details.toggleCompleted(
      completed: true,
      today: today,
      nowMillis: now,
    );
  }
  return details.copyWith(
    completedAt: null,
    stage: switch (status) {
      TaskStatus.todo => 'TODO',
      TaskStatus.doing => 'DOING',
      TaskStatus.waiting => 'WAITING',
      TaskStatus.done => 'TODO',
    },
  );
}

class FocusHistoryRow {
  const FocusHistoryRow({
    required this.taskId,
    required this.title,
    required this.id,
    required this.seconds,
    required this.endedAt,
  });

  final String taskId;
  final String title;
  final String id;
  final int seconds;
  final int endedAt;
}

List<FocusHistoryRow> focusHistory(List<Note> notes) {
  final rows = <FocusHistoryRow>[];
  final receipts = <String>{};
  final active = notes.where((n) => !n.isDeleted && n.isTask).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  for (final note in active) {
    final task = TaskDetails.tryDecode(note.taskJson);
    if (task == null) continue;
    for (final raw in task.focusHistory) {
      final id = raw['id']?.toString() ?? '';
      final seconds = (raw['seconds'] as num?)?.toInt() ?? 0;
      final endedAt = (raw['endedAt'] as num?)?.toInt() ?? 0;
      if (id.isEmpty || seconds <= 0 || endedAt <= 0 || !receipts.add(id)) {
        continue;
      }
      rows.add(
        FocusHistoryRow(
          taskId: note.id,
          title: note.title,
          id: id,
          seconds: seconds,
          endedAt: endedAt,
        ),
      );
    }
  }
  rows.sort((a, b) => b.endedAt.compareTo(a.endedAt));
  return rows;
}

List<MapEntry<DateTime, int>> weeklyFocus(
  List<Note> notes,
  DateTime today,
) {
  final byDay = <String, int>{};
  for (final row in focusHistory(notes)) {
    final date = DateTime.fromMillisecondsSinceEpoch(row.endedAt);
    final key =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    byDay[key] = (byDay[key] ?? 0) + row.seconds;
  }

  final base = DateTime(today.year, today.month, today.day);
  return [
    for (var back = 6; back >= 0; back--)
      () {
        final day = base.subtract(Duration(days: back));
        final key =
            '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        return MapEntry(day, byDay[key] ?? 0);
      }(),
  ];
}
