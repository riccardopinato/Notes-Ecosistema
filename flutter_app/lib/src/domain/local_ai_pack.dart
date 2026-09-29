enum LocalAiPackPhase {
  unavailable,
  notInstalled,
  pending,
  downloading,
  transferring,
  installed,
  waitingForWifi,
  requiresConfirmation,
  failed,
  canceled,
}

class LocalAiPackStatus {
  const LocalAiPackStatus({
    required this.phase,
    required this.supported,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.modelPath,
    this.error,
  });

  final LocalAiPackPhase phase;
  final bool supported;
  final int bytesDownloaded;
  final int totalBytes;
  final String? modelPath;
  final String? error;

  bool get installed =>
      supported &&
      phase == LocalAiPackPhase.installed &&
      modelPath != null &&
      modelPath!.isNotEmpty;

  bool get downloading =>
      phase == LocalAiPackPhase.pending ||
      phase == LocalAiPackPhase.downloading ||
      phase == LocalAiPackPhase.transferring;

  bool get canDownload =>
      supported &&
      (phase == LocalAiPackPhase.notInstalled ||
          phase == LocalAiPackPhase.failed ||
          phase == LocalAiPackPhase.canceled);

  double? get progress {
    if (phase == LocalAiPackPhase.installed) return 1;
    if (totalBytes <= 0) return null;
    return (bytesDownloaded / totalBytes).clamp(0, 1).toDouble();
  }

  factory LocalAiPackStatus.fromMap(Map<Object?, Object?> raw) {
    final phase = switch (raw['phase']?.toString()) {
      'notInstalled' => LocalAiPackPhase.notInstalled,
      'pending' => LocalAiPackPhase.pending,
      'downloading' => LocalAiPackPhase.downloading,
      'transferring' => LocalAiPackPhase.transferring,
      'installed' => LocalAiPackPhase.installed,
      'waitingForWifi' => LocalAiPackPhase.waitingForWifi,
      'requiresConfirmation' => LocalAiPackPhase.requiresConfirmation,
      'failed' => LocalAiPackPhase.failed,
      'canceled' => LocalAiPackPhase.canceled,
      _ => LocalAiPackPhase.unavailable,
    };
    return LocalAiPackStatus(
      phase: phase,
      supported: raw['supported'] == true,
      bytesDownloaded: (raw['bytesDownloaded'] as num?)?.toInt() ?? 0,
      totalBytes: (raw['totalBytes'] as num?)?.toInt() ?? 0,
      modelPath: raw['modelPath']?.toString(),
      error: raw['error']?.toString(),
    );
  }

  factory LocalAiPackStatus.unavailable([String? error]) => LocalAiPackStatus(
        phase: LocalAiPackPhase.unavailable,
        supported: false,
        error: error,
      );
}

abstract final class Needle20LPackPolicy {
  static const packName = 'notes_needle3_20l';
  static const modelFileName = 'needle3.cact';
  static const modelLabel = 'Needle 3 20L';

  static const upstreamRevision = 'b274efcb211a9eef48c9a88da4b43bd569696a39';
  static const modelSha256 =
      'c9d915eca282ed42d1a09b143b592adb4cc6744ffe2d294adf5cfc5548170c38';
  static const modelBytes = 35335380;
  static const approximateModelMegabytes = 35.3;

  static const androidArm64RuntimeSha256 =
      '5e0a5daaadca1fbe1c518110bee6bbb1cc97a5e53a16a1e964d0af0186eac60a';
  static const androidArm64RuntimeBytes = 1663992;
  static const approximateAndroidArm64RuntimeMegabytes = 1.6;
}
