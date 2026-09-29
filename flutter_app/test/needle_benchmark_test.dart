import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/needle_benchmark.dart';

void main() {
  test('Needle benchmark report computes quality and runtime metrics', () {
    const report = NeedleBenchmarkReport(
      samples: [
        NeedleBenchmarkSample(
          id: 'one',
          expectedTool: 'create_task',
          actualTool: 'create_task',
          inferenceMs: 100,
          pssDeltaKb: 4096,
        ),
        NeedleBenchmarkSample(
          id: 'two',
          expectedTool: 'add_tags',
          actualTool: 'checklist_item',
          inferenceMs: 200,
          pssDeltaKb: 8192,
        ),
      ],
    );

    expect(report.passed, 1);
    expect(report.total, 2);
    expect(report.passRate, 0.5);
    expect(report.averageInferenceMs, 150);
    expect(report.peakPssDeltaKb, 8192);
  });

  test('Needle benchmark corpus covers all structured tools', () {
    final tools = NeedleBenchmarkPolicy.cases
        .map((benchmarkCase) => benchmarkCase.expectedTool)
        .toSet();

    expect(
      tools,
      {
        'create_task',
        'add_tags',
        'set_priority',
        'checklist_item',
      },
    );
  });
}
