import 'dart:async';

import 'package:flutter/services.dart';

class DeepLinkBridge {
  static const _channel = MethodChannel('notes.ecosystem/deep_links');
  static FutureOr<void> Function(String link)? _handler;

  static Future<void> initialize(
    FutureOr<void> Function(String link) handler,
  ) async {
    _handler = handler;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'open') return;
      final link = call.arguments?.toString();
      if (link == null || link.trim().isEmpty) return;
      await _handler?.call(link);
    });
    try {
      final initial = await _channel.invokeMethod<String>('getInitialLink');
      if (initial != null && initial.trim().isNotEmpty) {
        await handler(initial);
      }
    } on MissingPluginException {
      // Web/desktop preview: deep links are Android-only for now.
    }
  }
}
