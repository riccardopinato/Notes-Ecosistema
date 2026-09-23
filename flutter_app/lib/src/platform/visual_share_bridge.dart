import 'package:flutter/services.dart';

class VisualShareBridge {
  VisualShareBridge._();

  static const _channel = MethodChannel('notes.ecosystem/visual_share');

  static Future<void> sharePng(
    Uint8List bytes, {
    required String title,
  }) async {
    if (bytes.isEmpty || bytes.length > 16 * 1024 * 1024) {
      throw const FormatException('PNG vuoto o troppo grande.');
    }
    await _channel.invokeMethod<void>('sharePng', {
      'bytes': bytes,
      'title': title.trim().isEmpty ? 'Notes' : title.trim(),
    });
  }
}
