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

  // Production Needle 3 archive pinned during the 0.56.2 integration.
  static const upstreamRevision = '3e8e2a66057a29694052d915128b91b53e7e5ead';
  static const modelSha256 =
      'c9d915eca282ed42d1a09b143b592adb4cc6744ffe2d294adf5cfc5548170c38';

  // Current upstream file is displayed as 35.3 MB. Keep UX approximate:
  // Play may report a different compressed transfer size at runtime.
  static const approximateModelMegabytes = 35.3;

  // Recent production Android ARM64 runtime builds are around 1.6 MB.
  // Pin the exact runtime revision/hash only when the JNI integration lands.
  static const approximateAndroidArm64RuntimeMegabytes = 1.6;
}
