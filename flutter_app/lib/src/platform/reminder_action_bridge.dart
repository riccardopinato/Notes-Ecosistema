import 'package:flutter/services.dart';

class ReminderAction {
  const ReminderAction({
    required this.action,
    required this.id,
    this.expectedAt,
    this.nextAt,
  });

  final String action;
  final String id;
  final int? expectedAt;
  final int? nextAt;

  factory ReminderAction.fromMap(Map<Object?, Object?> raw) => ReminderAction(
        action: raw['action']?.toString() ?? '',
        id: raw['id']?.toString() ?? '',
        expectedAt: (raw['expectedAt'] as num?)?.toInt(),
        nextAt: (raw['nextAt'] as num?)?.toInt(),
      );
}

class ReminderActionBridge {
  ReminderActionBridge._();

  static const _channel = MethodChannel('notes.ecosystem/reminder_actions');
  static bool _ready = false;

  static Future<void> initialize(
    Future<void> Function(ReminderAction action) onAction,
  ) async {
    if (!_ready) {
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'action' || call.arguments is! Map) return;
        await onAction(
          ReminderAction.fromMap(
            (call.arguments as Map).cast<Object?, Object?>(),
          ),
        );
      });
      _ready = true;
    }

    final initial = await _channel.invokeMethod<Object?>('getInitialAction');
    if (initial is Map) {
      final action = ReminderAction.fromMap(
        initial.cast<Object?, Object?>(),
      );
      if (action.id.isNotEmpty && action.action.isNotEmpty) {
        await onAction(action);
      }
    }
  }
}
