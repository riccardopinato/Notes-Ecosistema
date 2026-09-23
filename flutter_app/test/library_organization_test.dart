import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/library.dart';
import 'package:notes_ecosistema/src/domain/note.dart';

void main() {
  Note note({
    required String id,
    String title = '',
    String body = '',
    String? collectionId,
    bool favorite = false,
    bool pinned = false,
    bool archived = false,
    int? deletedAt,
    List<String> tags = const [],
    int createdAt = 1,
    int updatedAt = 1,
  }) =>
      Note(
        id: id,
        title: title,
        body: body,
        collectionId: collectionId,
        favorite: favorite,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        pinned: pinned,
        archived: archived,
        tags: tags,
      );

  test('advanced search combines scope tags flags and checklist', () {
    final notes = [
      note(
        id: 'a',
        title: 'Casa',
        body: '- [ ] compra latte',
        favorite: true,
        pinned: true,
        tags: const ['casa', 'spesa'],
      ),
      note(
        id: 'b',
        title: 'Lavoro',
        body: 'appunti',
        tags: const ['lavoro'],
      ),
      note(
        id: 'c',
        title: 'Archivio',
        archived: true,
        tags: const ['casa'],
      ),
    ];

    final result = searchNotes(
      notes,
      query: 'latte',
      options: const SearchOptions(
        tags: ['casa'],
        favoritesOnly: true,
        pinnedOnly: true,
        tasks: TaskPresence.openTasks,
      ),
    );

    expect(result.map((e) => e.id), ['a']);
  });

  test('orders keep pinned notes first', () {
    final notes = [
      note(id: 'a', title: 'Zeta', createdAt: 5),
      note(id: 'b', title: 'Alfa', createdAt: 1, pinned: true),
      note(id: 'c', title: 'Beta', createdAt: 10),
    ];

    expect(
      searchNotes(notes, order: NoteOrder.title).map((e) => e.id),
      ['b', 'c', 'a'],
    );
    expect(
      searchNotes(notes, order: NoteOrder.oldest).map((e) => e.id),
      ['b', 'a', 'c'],
    );
  });

  test('bulk edit follows Kotlin state preflight', () {
    final source = [
      note(id: 'a', tags: const ['casa']),
      note(id: 'b'),
    ];

    final tagged = planBulkEdit(
      source,
      const BulkChange(BulkAction.addTag, tag: 'Lavoro'),
      100,
    );
    expect(tagged.every((e) => e.tags.contains('lavoro')), isTrue);
    expect(tagged.every((e) => e.updatedAt == 100), isTrue);

    final trashed = planBulkEdit(
      source,
      const BulkChange(BulkAction.trash),
      200,
    );
    expect(trashed.every((e) => e.deletedAt == 200), isTrue);

    expect(
      () => planBulkEdit(
        [source.first.copyWith(deletedAt: 1)],
        const BulkChange(BulkAction.archive),
        300,
      ),
      throwsFormatException,
    );
  });

  test('saved search v1 codec preserves filters and order', () {
    const search = SavedSearch(
      id: 'saved-1',
      name: 'Casa aperta',
      query: 'latte',
      scope: NoteScope.inbox,
      collectionId: 'book',
      options: SearchOptions(
        tags: ['casa', 'spesa'],
        allTags: false,
        favoritesOnly: true,
        pinnedOnly: true,
        tasks: TaskPresence.openTasks,
      ),
      kind: 'Checklist',
      order: NoteOrder.title,
    );

    final raw = SavedSearchCodec.encode([search]);
    final decoded = SavedSearchCodec.decode(raw).single;

    expect(decoded.id, search.id);
    expect(decoded.name, search.name);
    expect(decoded.query, search.query);
    expect(decoded.scope, NoteScope.inbox);
    expect(decoded.collectionId, 'book');
    expect(decoded.options.tags, ['casa', 'spesa']);
    expect(decoded.options.allTags, isFalse);
    expect(decoded.options.favoritesOnly, isTrue);
    expect(decoded.options.pinnedOnly, isTrue);
    expect(decoded.options.tasks, TaskPresence.openTasks);
    expect(decoded.kind, 'Checklist');
    expect(decoded.order, NoteOrder.title);
  });
}
