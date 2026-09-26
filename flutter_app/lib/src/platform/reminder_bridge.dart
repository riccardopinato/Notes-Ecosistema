import 'package:flutter/services.dart';

import '../domain/note.dart';
import '../domain/planner.dart';

List<Map<String, Object?>> reminderPayload(List<Note> notes) {
  final reminders = <Map<String, Object?>>[];
  for (final note in notes) {
    final task = TaskDetails.tryDecode(note.taskJson);
    if (task == null ||
        note.isDeleted ||
        note.archived ||
        task.completed ||
        task.reminderAt == null) {
      continue;
    }
    reminders.add({
      'id': note.id,
      'title': note.title.trim().isEmpty ? 'Attività' : note.title.trim(),
      'at': task.reminderAt,
    });
  }
  return reminders;
}

class ReminderBridge {
  ReminderBridge._();

  static const _channel = MethodChannel('notes.ecosystem/reminders');

  static Future<void> sync(List<Note> notes) async {
    await _channel.invokeMethod<void>('sync', reminderPayload(notes));
  }

  static Future<bool> allowed() async =>
      await _channel.invokeMethod<bool>('allowed') ?? false;

  static Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  static Future<void> openSettings() async =>
      _channel.invokeMethod<void>('openSettings');

  static Future<String> zoneId() async =>
      await _channel.invokeMethod<String>('zoneId') ?? 'UTC';
}
