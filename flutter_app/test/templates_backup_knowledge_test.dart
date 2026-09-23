import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/backup.dart';
import 'package:notes_ecosistema/src/domain/knowledge.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/planner.dart';
import 'package:notes_ecosistema/src/domain/quick_capture.dart';
import 'package:notes_ecosistema/src/domain/templates.dart';

void main() {
  test('Personal templates expand variables and reset completed checks', () {
    final content = PersonalTemplates.instantiate(
      'Riunione {{data}}',
      '- [x] Fatto\n- [ ] Da fare\nOra {{ora}} · {{giorno}}',
      const ['modello', 'Lavoro', 'diario_2026-09-23'],
      DateTime(2026, 9, 23, 14, 5),
    );

    expect(content.title, 'Riunione 23/09/2026');
    expect(content.body, contains('- [ ] Fatto'));
    expect(content.body, contains('14:05'));
    expect(content.body, contains('mercoledì'));
    expect(content.tags, ['lavoro']);
  });

  test('Knowledge links round-trip stable UUIDs and headings skip fences', () {
    const a = '11111111-1111-1111-1111-111111111111';
    const b = '22222222-2222-2222-2222-222222222222';
    final edit = Knowledge.insert('Ciao mondo', 5, 10, a, 'Pagina A');

    expect(edit.text, 'Ciao [Pagina A](notes://note/$a)');
    expect(Knowledge.links(edit.text).single.id, a);

    final remapped = Knowledge.remap(edit.text, const {a: b});
    expect(remapped, contains('notes://note/$b'));

    final grave = String.fromCharCode(0x60);
    final fence = List<String>.filled(3, grave).join();
    final headings = Knowledge.headings([
      '# Uno',
      '${fence}dart',
      '## Nascosto',
      fence,
      '### Tre',
    ].join('\n'));
    expect(headings.map((h) => h.title), ['Uno', 'Tre']);
    expect(headings.last.level, 3);
  });

  test('Literal replace keeps deterministic ranges', () {
    final ranges = LiteralSearch.ranges('Casa casa CASA', 'casa');
    expect(ranges, hasLength(3));

    final edit = LiteralSearch.replaceAll(
      'Casa casa CASA',
      'casa',
      'Home',
    );
    expect(edit.text, 'Home Home Home');
  });

  test('Backup v6 preserves notes tasks collections and drafts', () {
    final task = TaskDetails.empty().copyWith(
      due: '2026-09-30',
      linkedNoteId: '11111111-1111-1111-1111-111111111111',
    );
    final snapshot = BackupSnapshot(
      notes: [
        const Note(
          id: '11111111-1111-1111-1111-111111111111',
          title: 'Pagina',
          body: 'Body',
          collectionId: 'book',
          favorite: true,
          createdAt: 1,
          updatedAt: 2,
          pinned: true,
          archived: false,
          tags: ['lavoro'],
        ),
        Note(
          id: '22222222-2222-2222-2222-222222222222',
          title: 'Task',
          body: '',
          favorite: false,
          createdAt: 2,
          updatedAt: 3,
          pinned: false,
          archived: false,
          tags: const [],
          taskJson: task.encode(),
        ),
      ],
      collections: const [
        NoteCollection(id: 'book', name: 'Progetti'),
      ],
      drafts: const [
        BackupDraft(
          id: '33333333-3333-3333-3333-333333333333',
          title: 'Bozza',
          body: 'testo',
          collectionId: 'book',
          updatedAt: 4,
          tags: ['idea'],
        ),
      ],
    );

    final encoded = BackupCodec.encode(snapshot, exportedAt: 10);
    final decoded = BackupCodec.decode(encoded);

    expect(decoded.notes, hasLength(2));
    expect(decoded.collections.single.name, 'Progetti');
    expect(decoded.drafts.single.tags, ['idea']);
    expect(
      TaskDetails.decode(decoded.notes.last.taskJson!).linkedNoteId,
      '11111111-1111-1111-1111-111111111111',
    );
  });

  test('Backup import copies remap knowledge and linked task IDs', () {
    const sourceNote = '11111111-1111-1111-1111-111111111111';
    const taskId = '22222222-2222-2222-2222-222222222222';
    final snapshot = BackupSnapshot(
      notes: [
        const Note(
          id: sourceNote,
          title: 'Pagina',
          body: 'Collega [me](notes://note/$sourceNote)',
          collectionId: 'book',
          favorite: false,
          createdAt: 1,
          updatedAt: 1,
          pinned: false,
          archived: false,
          tags: [],
        ),
        Note(
          id: taskId,
          title: 'Task',
          body: '',
          favorite: false,
          createdAt: 1,
          updatedAt: 1,
          pinned: false,
          archived: false,
          tags: const [],
          taskJson: TaskDetails.empty()
              .copyWith(linkedNoteId: sourceNote)
              .encode(),
        ),
      ],
      collections: const [
        NoteCollection(id: 'book', name: 'Progetti'),
      ],
      drafts: const [],
    );

    var index = 0;
    final ids = [
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
    ];
    final plan = BackupImport.asCopies(
      snapshot,
      existingCollectionNames: {'Progetti'},
      newId: () => ids[index++],
    );

    expect(plan.collections.single.name, 'Progetti (importata 1)');
    final importedPage = plan.notes.first;
    final importedTask = plan.notes.last;
    expect(importedPage.id, ids[1]);
    expect(importedPage.body, contains('notes://note/${ids[1]}'));
    expect(
      TaskDetails.decode(importedTask.taskJson!).linkedNoteId,
      ids[1],
    );
  });

  test('Quick Capture accepts plain UTF-8 and rejects empty or oversized', () {
    final seed = QuickCapture.shared('https://example.com', 'Fonte');
    expect(seed.title, 'Fonte');
    expect(seed.body, 'https://example.com');

    expect(() => QuickCapture.shared('', ''), throwsFormatException);
    expect(
      () => QuickCapture.shared(
        List<String>.filled(QuickCapture.maxBytes + 1, 'x').join(),
        '',
      ),
      throwsFormatException,
    );
  });
}
