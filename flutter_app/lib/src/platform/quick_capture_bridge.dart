import 'package:flutter/services.dart';

import '../domain/quick_capture.dart';

class QuickCaptureBridge {
  QuickCaptureBridge._();

  static const _channel = MethodChannel('notes.ecosystem/capture');
  static bool _ready = false;

  static Future<bool> pinNoteShortcut() async =>
      await _channel.invokeMethod<bool>('pinNoteShortcut') ?? false;

  static Future<bool> pinCaptureWidget() async =>
      await _channel.invokeMethod<bool>('pinCaptureWidget') ?? false;

  static Future<void> initialize(
    Future<void> Function(IncomingCapture capture) onCapture,
  ) async {
    if (!_ready) {
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'capture' || call.arguments is! Map) return;
        await onCapture(
          IncomingCapture.fromMap(
            (call.arguments as Map).cast<Object?, Object?>(),
          ),
        );
      });
      _ready = true;
    }

    final initial = await _channel.invokeMethod<Object?>('getInitialCapture');
    if (initial is Map) {
      final capture = IncomingCapture.fromMap(
        initial.cast<Object?, Object?>(),
      );
      if (!capture.empty || capture.seed.checklist) {
        await onCapture(capture);
      }
    }
  }
}
