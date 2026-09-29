import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/local_llm.dart';

class LocalLlmService {
  LocalLlmService({
    MethodChannel channel = const MethodChannel('notes.ecosystem/local_llm'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<LocalLlmStatus> status() async {
    if (!Platform.isAndroid) {
      return LocalLlmStatus.unsupported(
        'Gemini Nano/AICore è disponibile solo nella build Android.',
      );
    }
    try {
      final raw = await _channel.invokeMethod<Object?>('status');
      if (raw is Map) return LocalLlmStatus.fromMap(raw);
      return LocalLlmStatus.unsupported('Stato AI locale non valido.');
    } on MissingPluginException {
      return LocalLlmStatus.unsupported(
        'Bridge AI locale non presente in questa build.',
      );
    } on PlatformException catch (error) {
      return LocalLlmStatus.unsupported(error.message);
    }
  }

  Future<LocalLlmStatus> downloadSystemModel() async {
    if (!Platform.isAndroid) {
      throw const LocalLlmException(
        'Gemini Nano/AICore è disponibile solo su Android.',
      );
    }
    try {
      final raw = await _channel.invokeMethod<Object?>('download');
      if (raw is Map) return LocalLlmStatus.fromMap(raw);
      throw const LocalLlmException('Risposta download AI locale non valida.');
    } on PlatformException catch (error) {
      throw LocalLlmException(
        error.message ?? 'Download del modello di sistema non riuscito.',
      );
    }
  }

  Future<LocalLlmGeneration> generate({
    required String prompt,
    String systemInstruction = LocalLlmPolicy.systemInstruction,
    int maxOutputTokens = LocalLlmPolicy.defaultMaxOutputTokens,
  }) async {
    if (!Platform.isAndroid) {
      throw const LocalLlmException(
        'La generazione locale è disponibile nella build Android.',
      );
    }
    final safePrompt = prompt.trim();
    if (safePrompt.isEmpty) {
      throw const LocalLlmException('Prompt locale vuoto.');
    }
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'generate',
        {
          'prompt': safePrompt,
          'systemInstruction': systemInstruction.trim(),
          'maxOutputTokens': maxOutputTokens.clamp(64, 768),
        },
      );
      if (raw is Map) {
        final generation = LocalLlmGeneration.fromMap(raw);
        if (generation.text.isEmpty) {
          throw const LocalLlmException(
            'Il modello locale non ha restituito testo.',
          );
        }
        return generation;
      }
      throw const LocalLlmException('Risposta del modello non valida.');
    } on PlatformException catch (error) {
      throw LocalLlmException(
        error.message ?? 'Inferenza locale non riuscita.',
      );
    }
  }

  Future<void> cancel() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      return;
    }
  }
}

class LocalLlmException implements Exception {
  const LocalLlmException(this.message);

  final String message;

  @override
  String toString() => message;
}
