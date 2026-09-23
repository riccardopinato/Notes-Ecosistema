import 'package:flutter/services.dart';

class AttachmentBridge {
  AttachmentBridge._();

  static const _channel = MethodChannel('notes.ecosystem/attachments');

  static Future<void> open({
    required String key,
    required String name,
    required String mime,
  }) =>
      _channel.invokeMethod<void>('open', {
        'key': key,
        'name': name,
        'mime': mime,
      });

  static Future<void> share({
    required String key,
    required String name,
    required String mime,
  }) =>
      _channel.invokeMethod<void>('share', {
        'key': key,
        'name': name,
        'mime': mime,
      });
}
