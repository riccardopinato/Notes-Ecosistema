import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/local_llm.dart';

class LocalLlmService {
  LocalLlmService({
    MethodChannel channel = const MethodChannel('notes.ecosystem/local_llm'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<Directory> _modelDirectory() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(p.join(root.path, 'local_llm'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File?> installedModel() async {
    if (!Platform.isAndroid) return null;
    final directory = await _modelDirectory();
    final files = await directory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .where(
          (file) => file.path.toLowerCase().endsWith(
                LocalLlmPolicy.modelExtension,
              ),
        )
        .toList();
    if (files.isEmpty) return null;
    files.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    return files.first;
  }

  Future<File?> pickAndInstallModel() async {
    if (!Platform.isAndroid) {
      throw const LocalLlmException(
        'L’LLM locale è disponibile nella build Android.',
      );
    }
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['litertlm'],
      allowMultiple: false,
      withData: false,
    );
    final path = picked?.files.single.path;
    if (path == null || path.trim().isEmpty) return null;

    final source = File(path);
    if (!await source.exists()) {
      throw const LocalLlmException('File modello non disponibile.');
    }
    final bytes = await source.length();
    if (bytes < LocalLlmPolicy.minModelBytes ||
        bytes > LocalLlmPolicy.maxModelBytes) {
      throw const LocalLlmException(
        'Dimensione modello non valida. Usa un file .litertlm tra 32 MiB e 2 GiB.',
      );
    }

    final directory = await _modelDirectory();
    final safeBase = p
        .basenameWithoutExtension(source.path)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '')
        .takeSafe(80);
    final destination = File(
      p.join(
        directory.path,
        '${safeBase.isEmpty ? 'local-model' : safeBase}.litertlm',
      ),
    );
    final temporary = File('${destination.path}.partial');
    if (await temporary.exists()) await temporary.delete();
    await source.copy(temporary.path);
    final copiedBytes = await temporary.length();
    if (copiedBytes != bytes) {
      await temporary.delete();
      throw const LocalLlmException('Copia del modello incompleta.');
    }

    await unload();
    await for (final entity in directory.list()) {
      if (entity is File &&
          entity.path != temporary.path &&
          entity.path.toLowerCase().endsWith('.litertlm')) {
        await entity.delete();
      }
    }
    if (await destination.exists()) await destination.delete();
    return temporary.rename(destination.path);
  }

  Future<LocalLlmStatus> status() async {
    final model = await installedModel();
    if (!Platform.isAndroid) {
      return const LocalLlmStatus(
        supported: false,
        installed: false,
        loaded: false,
        runtime: LocalLlmPolicy.runtime,
        backend: 'CPU',
        modelName: null,
        modelBytes: 0,
        memoryClassMb: 0,
        processors: 0,
        error: 'Disponibile nella build Android.',
      );
    }
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'status',
        {'modelPath': model?.path},
      );
      if (raw is Map) return LocalLlmStatus.fromMap(raw);
      throw const LocalLlmException('Stato runtime non valido.');
    } on MissingPluginException {
      return LocalLlmStatus(
        supported: false,
        installed: model != null,
        loaded: false,
        runtime: LocalLlmPolicy.runtime,
        backend: 'CPU',
        modelName: model == null ? null : p.basename(model.path),
        modelBytes: model == null ? 0 : await model.length(),
        memoryClassMb: 0,
        processors: 0,
        error: 'Runtime LiteRT-LM non presente in questa build.',
      );
    } on PlatformException catch (error) {
      return LocalLlmStatus(
        supported: true,
        installed: model != null,
        loaded: false,
        runtime: LocalLlmPolicy.runtime,
        backend: 'CPU',
        modelName: model == null ? null : p.basename(model.path),
        modelBytes: model == null ? 0 : await model.length(),
        memoryClassMb: 0,
        processors: 0,
        error: error.message,
      );
    }
  }

  Future<LocalLlmStatus> load() async {
    final model = await installedModel();
    if (model == null) {
      throw const LocalLlmException(
        'Installa prima un modello .litertlm.',
      );
    }
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'load',
        {'modelPath': model.path},
      );
      if (raw is Map) return LocalLlmStatus.fromMap(raw);
      throw const LocalLlmException('Risposta di caricamento non valida.');
    } on PlatformException catch (error) {
      throw LocalLlmException(
        error.message ?? 'Impossibile caricare il modello locale.',
      );
    }
  }

  Future<LocalLlmGeneration> generate({
    required String prompt,
    String systemInstruction = LocalLlmPolicy.systemInstruction,
    int maxOutputTokens = LocalLlmPolicy.defaultMaxOutputTokens,
  }) async {
    final model = await installedModel();
    if (model == null) {
      throw const LocalLlmException(
        'Installa prima un modello .litertlm.',
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
          'modelPath': model.path,
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

  Future<void> unload() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('unload');
    } on MissingPluginException {
      return;
    }
  }

  Future<void> deleteModel() async {
    await unload();
    final directory = await _modelDirectory();
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is File &&
          entity.path.toLowerCase().endsWith('.litertlm')) {
        await entity.delete();
      }
    }
  }
}

class LocalLlmException implements Exception {
  const LocalLlmException(this.message);

  final String message;

  @override
  String toString() => message;
}

extension _SafeTake on String {
  String takeSafe(int maxLength) =>
      length <= maxLength ? this : substring(0, maxLength);
}
