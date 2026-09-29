class NeedleBenchmarkCase {
  const NeedleBenchmarkCase({
    required this.id,
    required this.prompt,
    required this.expectedTool,
  });

  final String id;
  final String prompt;
  final String expectedTool;
}

class NeedleBenchmarkSample {
  const NeedleBenchmarkSample({
    required this.id,
    required this.expectedTool,
    required this.actualTool,
    required this.inferenceMs,
    required this.pssDeltaKb,
  });

  final String id;
  final String expectedTool;
  final String? actualTool;
  final int inferenceMs;
  final int pssDeltaKb;

  bool get passed => actualTool == expectedTool;
}

class NeedleBenchmarkReport {
  const NeedleBenchmarkReport({
    required this.samples,
  });

  final List<NeedleBenchmarkSample> samples;

  int get passed => samples.where((sample) => sample.passed).length;
  int get total => samples.length;

  double get passRate => total == 0 ? 0 : passed / total;

  double get averageInferenceMs => total == 0
      ? 0
      : samples.fold<int>(0, (sum, sample) => sum + sample.inferenceMs) /
          total;

  int get peakPssDeltaKb => samples.fold<int>(
        0,
        (peak, sample) =>
            sample.pssDeltaKb > peak ? sample.pssDeltaKb : peak,
      );
}

abstract final class NeedleBenchmarkPolicy {
  static const cases = <NeedleBenchmarkCase>[
    NeedleBenchmarkCase(
      id: 'create_task',
      prompt: 'Nota: devo inviare il preventivo al cliente.',
      expectedTool: 'create_task',
    ),
    NeedleBenchmarkCase(
      id: 'add_tags',
      prompt: 'Nota sul progetto cucina professionale. Aggiungi i tag cucina e acquisti.',
      expectedTool: 'add_tags',
    ),
    NeedleBenchmarkCase(
      id: 'set_priority',
      prompt: 'Questa attività è esplicitamente ad alta priorità.',
      expectedTool: 'set_priority',
    ),
    NeedleBenchmarkCase(
      id: 'checklist_item',
      prompt: 'Checklist: controllare il listino aggiornato.',
      expectedTool: 'checklist_item',
    ),
  ];
}
