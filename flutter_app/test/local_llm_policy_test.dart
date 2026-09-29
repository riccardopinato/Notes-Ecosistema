import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/local_llm.dart';

void main() {
  test('note prompt is bounded and keeps the user question', () {
    final prompt = LocalLlmPolicy.notePrompt(
      question: 'Qual è la decisione principale?',
      title: 'Riunione prodotto',
      body: 'x' * 40000,
      tags: const ['meeting', 'roadmap'],
    );

    expect(prompt, contains('Qual è la decisione principale?'));
    expect(prompt, contains('Riunione prodotto'));
    expect(prompt, contains('meeting, roadmap'));
    expect(prompt, contains('contenuto troncato'));
    expect(
      prompt.length,
      lessThan(
        LocalLlmPolicy.maxNoteContextChars +
            LocalLlmPolicy.maxQuestionChars +
            2000,
      ),
    );
  });

  test('workspace prompt keeps bounded ranked local sources', () {
    final sources = List.generate(
      10,
      (index) => (
        title: 'Fonte $index',
        excerpt: 'Contenuto della fonte $index',
      ),
    );

    final prompt = LocalLlmPolicy.workspacePrompt(
      question: 'Che cosa sappiamo?',
      sources: sources,
    );

    expect(prompt, contains('[1] Fonte 0'));
    expect(
      prompt,
      contains('[${LocalLlmPolicy.maxWorkspaceSources}] Fonte 4'),
    );
    expect(prompt, isNot(contains('Fonte 5')));
    expect(prompt, contains('Non inventare fatti mancanti'));
  });

  test('adaptive runtime keeps Gemini Nano system-managed', () {
    expect(LocalLlmPolicy.runtime, contains('AICore'));
    expect(LocalLlmPolicy.preferredModel, 'Gemini Nano');
    expect(LocalLlmPolicy.lightweightFallback, 'Needle 3');
    expect(LocalLlmPolicy.maxWorkspaceContextChars, lessThanOrEqualTo(12000));
  });

  test('status maps provider capability without bundling a model', () {
    final status = LocalLlmStatus.fromMap(const {
      'supported': true,
      'available': true,
      'downloadable': false,
      'downloading': false,
      'runtime': 'ML Kit Prompt API 1.0.0-beta4',
      'backend': 'Android AICore',
      'modelName': 'Gemini Nano',
      'systemManaged': true,
      'provider': 'geminiNano',
    });

    expect(status.available, isTrue);
    expect(status.systemManaged, isTrue);
    expect(status.provider, LocalAiProvider.geminiNano);
  });
}
