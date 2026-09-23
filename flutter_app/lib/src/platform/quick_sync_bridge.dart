import 'package:flutter/services.dart';

class QuickSyncBridge {
  QuickSyncBridge._();

  static const _channel = MethodChannel('notes.ecosystem/quick_sync');
  static bool _ready = false;

  static Future<void> initialize(
    Future<void> Function() onSync,
  ) async {
    if (!_ready) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'sync') await onSync();
      });
      _ready = true;
    }

    final initial = await _channel.invokeMethod<bool>('getInitialRequest');
    if (initial == true) await onSync();
  }
}
