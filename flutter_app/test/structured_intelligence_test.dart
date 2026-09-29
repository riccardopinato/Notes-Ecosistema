import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/structured_intelligence.dart';

void main() {
  test('structured prompt is bounded and forbids destructive actions', () {
    final prompt = StructuredIntelligencePolicy.notePrompt(
      title: 'Riunione',
      body: 'x' * 50000,
    );

    expect(prompt, contains('"commands"'));
    expect(prompt, contains('non proporre eliminazioni'));
    expect(
      prompt.length,
      lessThan(StructuredIntelligencePolicy.maxBodyChars + 3000),
    );
  });

  test('Gemini JSON parser keeps only supported validated commands', () {
    final analysis = StructuredIntelligencePolicy.parseGemini(
      '''
      {
        "commands": [
          {
            "kind": "create_task",
            "title": "Inviare il preventivo",
            "confidence": 0.91,
            "evidence": "Inviare il preventivo entro venerdì"
          },
          {
            "kind": "delete_note",
            "title": "Cancella tutto",
            "confidence": 1
          },
          {
            "kind": "add_tags",
            "tags": ["Cliente", "Q4", "tag non valido"],
            "confidence": 0.8
          }
        ]
      }
      ''',
    );

    expect(analysis.commands, hasLength(2));
    expect(
      analysis.commands.first.kind,
      StructuredCommandKind.createTask,
    );
    expect(analysis.commands.first.title, 'Inviare il preventivo');
    expect(
      analysis.commands.last.tags,
      containsAll(<String>['cliente', 'q4']),
    );
    expect(analysis.commands.last.tags, isNot(contains('tag non valido')));
  });

  test('deterministic fallback extracts explicit tasks and hashtags', () {
    final analysis = StructuredIntelligencePolicy.deterministic(
      body: '''
- [ ] Chiamare Marco
- Preparare le slide
Note per #progetto_x e #cliente
''',
    );

    expect(
      analysis.commands.any(
        (command) =>
            command.kind == StructuredCommandKind.createTask &&
            command.title == 'Chiamare Marco',
      ),
      isTrue,
    );
    expect(
      analysis.commands.any(
        (command) =>
            command.kind == StructuredCommandKind.checklistItem &&
            command.title == 'Preparare le slide',
      ),
      isTrue,
    );
    expect(
      analysis.commands.any(
        (command) =>
            command.kind == StructuredCommandKind.addTags &&
            ['progetto_x', 'cliente'].every(command.tags.contains),
      ),
      isTrue,
    );
  });

  test('structured parser accepts fenced JSON and clamps confidence', () {
    final analysis = StructuredIntelligencePolicy.parseGemini(
      '''
```json
{"commands":[{"kind":"set_priority","priority":"high","confidence":4}]}
```
''',
    );

    expect(analysis.commands, hasLength(1));
    expect(analysis.commands.single.priority, 'high');
    expect(analysis.commands.single.confidence, 1);
  });

  test('Needle structured output uses the same validator contract', () {
    final result = StructuredIntelligencePolicy.parseNeedle(
      '{"commands":[{"kind":"create_task","title":"Invia report","confidence":0.91}]}',
    );

    expect(result.source, StructuredAnalysisSource.needle);
    expect(result.modelName, 'Needle 3 20L');
    expect(result.commands, hasLength(1));
    expect(result.commands.single.kind, StructuredCommandKind.createTask);
    expect(result.commands.single.title, 'Invia report');
  });
}
