import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/derivatives.dart';
import 'package:notes_ecosistema/src/domain/intelligence.dart';
import 'package:notes_ecosistema/src/domain/note.dart';

void main() {
  Note note(String id, String title, String body) => Note(
        id: id,
        title: title,
        body: body,
        favorite: false,
        createdAt: 1,
        updatedAt: 2,
        pinned: false,
        archived: false,
        tags: const [],
      );

  test('local knowledge retrieval ranks matching notes with citations', () {
    final notes = [
      note(
        'alpha',
        'Progetto Alpha',
        'La review del progetto Alpha è fissata per venerdì.',
      ),
      note(
        'beta',
        'Lista spesa',
        'Pane latte e verdure.',
      ),
    ];
    const engine = LocalKnowledgeRetrieval();
    final result = engine.ask('review Alpha', notes);

    expect(result.hits, isNotEmpty);
    expect(result.hits.first.note.id, 'alpha');
    expect(result.hits.first.citation(1), '[1] Progetto Alpha');
  });

  test('related notes exclude the source and preserve deterministic ordering',
      () {
    final source = note(
      'source',
      'Ricerca batterie',
      'Batterie litio durata ricarica autonomia.',
    );
    final notes = [
      source,
      note(
        'related',
        'Autonomia',
        'Durata batteria litio e cicli di ricarica.',
      ),
      note('other', 'Cucina', 'Ricette pasta pomodoro.'),
    ];
    const engine = LocalKnowledgeRetrieval();
    final related = engine.related(source, notes);

    expect(related, isNotEmpty);
    expect(related.first.note.id, 'related');
    expect(related.any((hit) => hit.note.id == 'source'), isFalse);
  });

  test('transcript cleaning never mutates the supplied original', () {
    const original = 'ciao   mondo\n\n\nquesta è una prova.';
    final cleaned = LocalDerivation.cleanTranscript(original);

    expect(original, 'ciao   mondo\n\n\nquesta è una prova.');
    expect(cleaned, isNot(equals(original)));
    expect(cleaned, contains('Ciao mondo'));
  });

  test('summary is extractive and bounded', () {
    const source = 'Alpha riguarda il progetto principale. '
        'Alpha richiede una review. '
        'La cucina è separata. '
        'Il progetto Alpha ha una scadenza. '
        'Serve preparare il documento finale. '
        'Un dettaglio secondario completa il testo.';
    final summary = LocalDerivation.summarize(source, maxSentences: 3);
    final sentenceCount = summary
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((e) => e.isNotEmpty)
        .length;

    expect(sentenceCount, lessThanOrEqualTo(3));
    expect(source, contains(summary.split('.').first));
  });

  test('task extraction only uses explicit action markers', () {
    final tasks = LocalDerivation.extractTasks(
      'Nota normale\n'
      '- [ ] Chiamare Marco\n'
      'TODO: Preparare report\n'
      'azione - Inviare preventivo\n'
      'Altro testo',
    );

    expect(tasks, ['Chiamare Marco', 'Preparare report', 'Inviare preventivo']);
    expect(
      LocalDerivation.tasksAsMarkdown(tasks),
      contains('- [ ] Preparare report'),
    );
  });

  test('derivative metadata remains distinct from source content', () {
    const derivative = SourceDerivative(
      id: 'd1',
      sourceNoteId: 'n1',
      kind: DerivativeKind.summary,
      content: 'Riassunto',
      sourceFingerprint: 'fingerprint',
      createdAt: 1,
      engine: 'local',
    );

    final map = derivative.toMap();
    expect(map['content'], 'Riassunto');
    expect(map['sourceNoteId'], 'n1');
    expect(map.containsKey('sourceBody'), isFalse);
  });
}
