import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/local_ai_pack.dart';

class LocalAiPackService {
  const LocalAiPackService({
    MethodChannel channel =
        const MethodChannel('notes.ecosystem/local_ai_pack'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<LocalAiPackStatus> status() async {
    if (!Platform.isAndroid) {
      return LocalAiPackStatus.unavailable(
        'Il pacchetto AI Plus è disponibile nella build Android.',
      );
    }
    try {
      final raw = await _channel.invokeMethod<Object?>('status');
      if (raw is Map) return LocalAiPackStatus.fromMap(raw);
      return LocalAiPackStatus.unavailable(
        'Stato del pacchetto AI non valido.',
      );
    } on MissingPluginException {
      return LocalAiPackStatus.unavailable(
        'Play AI Delivery non è presente in questa build.',
      );
    } on PlatformException catch (error) {
      return LocalAiPackStatus.unavailable(error.message);
    }
  }

  Future<LocalAiPackStatus> download() => _mutate('download');

  Future<LocalAiPackStatus> remove() => _mutate('remove');

  Future<LocalAiPackStatus> cancel() => _mutate('cancel');

  Future<LocalAiPackStatus> _mutate(String method) async {
    if (!Platform.isAndroid) {
      throw const LocalAiPackException(
        'Il pacchetto AI Plus è disponibile nella build Android.',
      );
    }
    try {
      final raw = await _channel.invokeMethod<Object?>(method);
      if (raw is Map) return LocalAiPackStatus.fromMap(raw);
      throw const LocalAiPackException(
        'Risposta Play AI Delivery non valida.',
      );
    } on PlatformException catch (error) {
      throw LocalAiPackException(
        error.message ?? 'Operazione sul pacchetto AI non riuscita.',
      );
    }
  }
}

class LocalAiPackException implements Exception {
  const LocalAiPackException(this.message);

  final String message;

  @override
  String toString() => message;
}
