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

  test('workspace prompt keeps at most six ranked local sources', () {
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
    expect(prompt, contains('[6] Fonte 5'));
    expect(prompt, isNot(contains('Fonte 6')));
    expect(prompt, contains('Non inventare fatti mancanti'));
  });

  test('local runtime policy keeps model external to the APK', () {
    expect(LocalLlmPolicy.runtime, 'LiteRT-LM 0.17.1');
    expect(LocalLlmPolicy.modelExtension, '.litertlm');
    expect(LocalLlmPolicy.minModelBytes, greaterThan(0));
    expect(LocalLlmPolicy.maxModelBytes, greaterThan(1024 * 1024 * 1024));
  });
}
