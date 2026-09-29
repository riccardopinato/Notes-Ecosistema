import 'dart:convert';

import '../domain/needle_benchmark.dart';
import 'needle_runtime_service.dart';

class NeedleBenchmarkService {
  NeedleBenchmarkService({
    NeedleRuntimeService? runtime,
  }) : _runtime = runtime ?? const NeedleRuntimeService();

  final NeedleRuntimeService _runtime;

  Future<NeedleBenchmarkReport> run({
    List<NeedleBenchmarkCase> cases = NeedleBenchmarkPolicy.cases,
  }) async {
    final samples = <NeedleBenchmarkSample>[];

    for (final benchmarkCase in cases) {
      final generation = await _runtime.analyze(
        benchmarkCase.prompt,
        maxOutputTokens: 192,
      );

      samples.add(
        NeedleBenchmarkSample(
          id: benchmarkCase.id,
          expectedTool: benchmarkCase.expectedTool,
          actualTool: _firstTool(generation.text),
          inferenceMs: generation.inferenceMs,
          pssDeltaKb: generation.pssDeltaKb,
        ),
      );
    }

    return NeedleBenchmarkReport(samples: samples);
  }

  static String? _firstTool(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final calls = decoded['function_calls'];
      if (calls is! List || calls.isEmpty) return null;
      final first = calls.first;
      if (first is! Map) return null;
      return first['name']?.toString();
    } catch (_) {
      return null;
    }
  }
}
