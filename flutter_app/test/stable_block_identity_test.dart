import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/blocks.dart';

void main() {
  test('text edit preserves block identity', () {
    final original = BlockEditorCodec.parse(
      'note-1',
      '# Titolo\n\nPrimo testo',
      now: 10,
    );
    final ids = original.map((block) => block.id).toList();

    final edited = BlockEditorCodec.reconcile(
      'note-1',
      original,
      '# Titolo\n\nPrimo testo modificato',
      now: 20,
    );

    expect(edited.length, 2);
    expect(edited[0].id, ids[0]);
    expect(edited[1].id, ids[1]);
    expect(edited[1].createdAt, original[1].createdAt);
    expect(edited[1].updatedAt, 20);
  });

  test('inserting a block preserves unchanged shifted block IDs', () {
    final original = BlockEditorCodec.parse(
      'note-1',
      '# Titolo\n\nParagrafo stabile\n\n- [ ] Task',
      now: 10,
    );
    final headingId = original[0].id;
    final paragraphId = original[1].id;
    final taskId = original[2].id;

    final edited = BlockEditorCodec.reconcile(
      'note-1',
      original,
      '# Titolo\n\nNuovo paragrafo\n\nParagrafo stabile\n\n- [ ] Task',
      now: 20,
    );

    expect(edited[0].id, headingId);
    expect(
      edited.firstWhere((block) => block.text == 'Paragrafo stabile').id,
      paragraphId,
    );
    expect(
      edited.firstWhere((block) => block.type == ContentBlockType.checklist).id,
      taskId,
    );
  });

  test('canonicalize keeps explicit IDs through save-reload representation', () {
    final original = BlockEditorCodec.parse('note-1', 'Uno\n\nDue', now: 10);
    final stored = original.map((block) => block.toMap()).toList();
    final reloaded = stored.map(ContentBlock.fromMap).toList();
    final canonical = BlockEditorCodec.canonicalize(
      'note-1',
      reloaded,
      now: 30,
    );

    expect(
      canonical.map((block) => block.id),
      original.map((block) => block.id),
    );
  });
}
