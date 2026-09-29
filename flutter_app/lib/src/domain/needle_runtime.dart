class NeedleRuntimeStatus {
  const NeedleRuntimeStatus({
    required this.supported,
    required this.modelInstalled,
    required this.ready,
    required this.initialized,
    required this.modelName,
    required this.backend,
    this.abi,
    this.prefixTokens,
    this.error,
  });

  final bool supported;
  final bool modelInstalled;
  final bool ready;
  final bool initialized;
  final String modelName;
  final String backend;
  final String? abi;
  final int? prefixTokens;
  final String? error;

  factory NeedleRuntimeStatus.fromMap(Map<Object?, Object?> raw) =>
      NeedleRuntimeStatus(
        supported: raw['supported'] == true,
        modelInstalled: raw['modelInstalled'] == true,
        ready: raw['ready'] == true,
        initialized: raw['initialized'] == true,
        modelName: raw['modelName']?.toString() ?? 'Needle 3 20L',
        backend: raw['backend']?.toString() ?? 'Needle native ARM64',
        abi: raw['abi']?.toString(),
        prefixTokens: (raw['prefixTokens'] as num?)?.toInt(),
        error: raw['error']?.toString(),
      );

  factory NeedleRuntimeStatus.unavailable([String? error]) =>
      NeedleRuntimeStatus(
        supported: false,
        modelInstalled: false,
        ready: false,
        initialized: false,
        modelName: 'Needle 3 20L',
        backend: 'Needle native ARM64',
        error: error,
      );
}

class NeedleRuntimeGeneration {
  const NeedleRuntimeGeneration({
    required this.text,
    required this.elapsedMs,
    required this.loadMs,
    required this.inferenceMs,
    required this.modelName,
    required this.backend,
    required this.pssBeforeKb,
    required this.pssAfterKb,
    this.prefixTokens,
  });

  final String text;
  final int elapsedMs;
  final int loadMs;
  final int inferenceMs;
  final String modelName;
  final String backend;
  final int pssBeforeKb;
  final int pssAfterKb;
  final int? prefixTokens;

  int get pssDeltaKb => pssAfterKb - pssBeforeKb;

  factory NeedleRuntimeGeneration.fromMap(Map<Object?, Object?> raw) =>
      NeedleRuntimeGeneration(
        text: raw['text']?.toString() ?? '',
        elapsedMs: (raw['elapsedMs'] as num?)?.toInt() ?? 0,
        loadMs: (raw['loadMs'] as num?)?.toInt() ?? 0,
        inferenceMs: (raw['inferenceMs'] as num?)?.toInt() ?? 0,
        modelName: raw['modelName']?.toString() ?? 'Needle 3 20L',
        backend: raw['backend']?.toString() ?? 'Needle native ARM64',
        pssBeforeKb: (raw['pssBeforeKb'] as num?)?.toInt() ?? 0,
        pssAfterKb: (raw['pssAfterKb'] as num?)?.toInt() ?? 0,
        prefixTokens: (raw['prefixTokens'] as num?)?.toInt(),
      );
}

abstract final class NeedleRuntimePolicy {
  static const maxPromptChars = 14000;
  static const defaultMaxOutputTokens = 384;
  static const maxOutputTokens = 512;
}
