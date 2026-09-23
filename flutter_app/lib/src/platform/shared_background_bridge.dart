import 'package:flutter/services.dart';

class SharedBackgroundStatus {
  const SharedBackgroundStatus({
    required this.enabledAt,
    required this.lastCheckAt,
    required this.lastSuccessAt,
    required this.intervalMinutes,
    this.lastError,
  });

  final int enabledAt;
  final int lastCheckAt;
  final int lastSuccessAt;
  final int intervalMinutes;
  final String? lastError;

  bool get configured => enabledAt > 0;
  bool get healthy => lastError == null || lastError!.trim().isEmpty;

  factory SharedBackgroundStatus.fromMap(Map<Object?, Object?> map) =>
      SharedBackgroundStatus(
        enabledAt: (map['enabledAt'] as num?)?.toInt() ?? 0,
        lastCheckAt: (map['lastCheckAt'] as num?)?.toInt() ?? 0,
        lastSuccessAt: (map['lastSuccessAt'] as num?)?.toInt() ?? 0,
        intervalMinutes:
            (map['intervalMinutes'] as num?)?.toInt() ?? 15,
        lastError: map['lastError']?.toString(),
      );
}

class SharedBackgroundBridge {
  SharedBackgroundBridge._();

  static const _channel = MethodChannel(
    'notes.ecosystem/shared_background',
  );

  static Future<void> initialize(
    Future<void> Function(String spaceId) onOpenSpace,
  ) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'openSpace') return;
      final id = call.arguments?.toString().trim() ?? '';
      if (id.isNotEmpty) {
        await onOpenSpace(id);
      }
    });

    final initial =
        await _channel.invokeMethod<String>('getInitialSpace');
    if (initial != null && initial.trim().isNotEmpty) {
      await onOpenSpace(initial.trim());
    }
  }

  static Future<void> setEnabled(bool enabled) =>
      _channel.invokeMethod<void>('setEnabled', enabled);

  static Future<SharedBackgroundStatus> status() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'status',
    );
    return SharedBackgroundStatus.fromMap(raw ?? const {});
  }
}
