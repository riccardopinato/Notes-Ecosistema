import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/note_local_signals.dart';

void main() {
  Note note(
    String id,
    String title,
    String body, {
    bool archived = false,
    int? deletedAt,
    List<String> tags = const [],
  }) =>
      Note(
        id: id,
        title: title,
        body: body,
        favorite: false,
        createdAt: 1,
        updatedAt: 2,
        pinned: false,
        archived: archived,
        deletedAt: deletedAt,
        tags: tags,
      );

  test('misspelled single token finds active note via source-backed fallback', () {
    final hits = NoteLocalSignals.fuzzyFallback(
      query: 'taccuiono',
      notes: [
        note('a', 'Taccuino viaggi', 'Itinerari'),
        note('b', 'Ricette cucina', 'Spesa'),
      ],
    );
    expect(hits.map((hit) => hit.document.noteId), ['a']);
  });

  test('deleted and archived sources never enter fuzzy candidates', () {
    final hits = NoteLocalSignals.fuzzyFallback(
      query: 'taccuiono',
      notes: [
        note('hidden', 'Taccuino segreto', '', archived: true),
        note('deleted', 'Taccuino eliminato', '', deletedAt: 42),
        note('visible', 'Taccuino pubblico', ''),
      ],
      excludedNoteIds: {'visible'},
    );
    expect(hits, isEmpty);
    expect(
      NoteLocalSignals.fuzzyFallback(
        query: 'ta',
        notes: [note('short', 'Taccuino', '')],
      ),
      isEmpty,
    );
  });

  test('TF-IDF returns preview terms, never modifies source tags', () {
    final source = note(
        'source', 'Fotografia paesaggio', 'Paesaggio montagna paesaggio');
    final proposals = NoteLocalSignals.tagProposals(
      title: source.title,
      body: source.body,
      authorizedNotes: [
        source,
        note('other', 'Paesaggio', 'Ritratto e paesaggio'),
      ],
      existingTags: const ['montagna'],
    );
    expect(proposals, contains('paesaggio'));
    expect(proposals, isNot(contains('montagna')));
    expect(source.tags, isEmpty);
  });

  test('TF-IDF fails closed without an authorized visible corpus', () {
    expect(
      NoteLocalSignals.tagProposals(
        title: 'Fotografia',
        body: 'Paesaggio',
        authorizedNotes: [
          note('archived', 'Paesaggio', 'Foto', archived: true),
        ],
      ),
      isEmpty,
    );
  });

  test('500 / 5000 fixtures stay bounded and deterministic', () {
    final corpus = [
      for (var i = 0; i < 5000; i++)
        note('n$i', 'Taccuino$i', 'Documentazione locale'),
    ];
    final first = NoteLocalSignals.fuzzyFallback(
        query: 'documentazone', notes: corpus, limit: 4);
    final second = NoteLocalSignals.fuzzyFallback(
        query: 'documentazone', notes: corpus, limit: 4);
    expect(first.map((h) => h.document.noteId).toList(),
        second.map((h) => h.document.noteId).toList());
    expect(first.length, lessThanOrEqualTo(4));
    final proposals = NoteLocalSignals.tagProposals(
      title: 'Fotografia fotografia',
      body: 'Paesaggio',
      authorizedNotes: corpus.take(500),
    );
    expect(proposals.length, lessThanOrEqualTo(5));
    expect(
      NoteLocalSignals.fuzzyFallback(
          query: 'documentazone',
          notes: [
            ...corpus,
            note('overflow', 'Documentazione', ''),
          ]),
      isEmpty,
    );
  });
}
