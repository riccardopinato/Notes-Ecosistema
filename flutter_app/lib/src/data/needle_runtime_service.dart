import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/needle_runtime.dart';

class NeedleRuntimeService {
  const NeedleRuntimeService({
    MethodChannel channel =
        const MethodChannel('notes.ecosystem/needle_runtime'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<NeedleRuntimeStatus> status() async {
    if (!Platform.isAndroid) {
      return NeedleRuntimeStatus.unavailable(
        'Needle 3 locale è disponibile nella build Android.',
      );
    }

    try {
      final raw = await _channel.invokeMethod<Object?>('status');
      if (raw is Map) return NeedleRuntimeStatus.fromMap(raw);
      return NeedleRuntimeStatus.unavailable(
        'Stato runtime Needle non valido.',
      );
    } on MissingPluginException {
      return NeedleRuntimeStatus.unavailable(
        'Runtime Needle non presente in questa build.',
      );
    } on PlatformException catch (error) {
      return NeedleRuntimeStatus.unavailable(error.message);
    }
  }

  Future<NeedleRuntimeGeneration> analyze(
    String prompt, {
    int maxOutputTokens = NeedleRuntimePolicy.defaultMaxOutputTokens,
  }) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      throw const NeedleRuntimeException('Prompt Needle vuoto.');
    }
    if (trimmed.length > NeedleRuntimePolicy.maxPromptChars) {
      throw const NeedleRuntimeException(
        'Prompt Needle oltre il limite locale.',
      );
    }

    final boundedTokens = maxOutputTokens.clamp(
      32,
      NeedleRuntimePolicy.maxOutputTokens,
    );

    try {
      final raw = await _channel.invokeMethod<Object?>(
        'analyze',
        {
          'prompt': trimmed,
          'maxOutputTokens': boundedTokens,
        },
      );
      if (raw is Map) return NeedleRuntimeGeneration.fromMap(raw);
      throw const NeedleRuntimeException(
        'Risposta runtime Needle non valida.',
      );
    } on PlatformException catch (error) {
      throw NeedleRuntimeException(
        error.message ?? 'Inferenza Needle non riuscita.',
      );
    }
  }

  Future<void> reset() async {
    try {
      await _channel.invokeMethod<void>('reset');
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      throw NeedleRuntimeException(
        error.message ?? 'Reset Needle non riuscito.',
      );
    }
  }
}

class NeedleRuntimeException implements Exception {
  const NeedleRuntimeException(this.message);

  final String message;

  @override
  String toString() => message;
}
