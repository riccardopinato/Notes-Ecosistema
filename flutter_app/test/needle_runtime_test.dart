import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/needle_runtime.dart';

void main() {
  test('Needle runtime status parses native readiness', () {
    final status = NeedleRuntimeStatus.fromMap({
      'supported': true,
      'modelInstalled': true,
      'ready': true,
      'initialized': true,
      'modelName': 'Needle 3 20L',
      'backend': 'Needle native ARM64',
      'abi': 'arm64-v8a',
      'prefixTokens': 81,
    });

    expect(status.supported, isTrue);
    expect(status.modelInstalled, isTrue);
    expect(status.ready, isTrue);
    expect(status.initialized, isTrue);
    expect(status.abi, 'arm64-v8a');
    expect(status.prefixTokens, 81);
  });

  test('Needle generation exposes latency and PSS delta', () {
    final generation = NeedleRuntimeGeneration.fromMap({
      'text': '{"type":"call","function_calls":[]}',
      'elapsedMs': 140,
      'loadMs': 40,
      'inferenceMs': 100,
      'modelName': 'Needle 3 20L',
      'backend': 'Needle native ARM64',
      'pssBeforeKb': 100000,
      'pssAfterKb': 112500,
      'prefixTokens': 90,
    });

    expect(generation.inferenceMs, 100);
    expect(generation.pssDeltaKb, 12500);
    expect(generation.prefixTokens, 90);
  });

  test('Needle runtime unavailable factory is safe', () {
    final status = NeedleRuntimeStatus.unavailable('unsupported');

    expect(status.supported, isFalse);
    expect(status.ready, isFalse);
    expect(status.error, 'unsupported');
  });
}
