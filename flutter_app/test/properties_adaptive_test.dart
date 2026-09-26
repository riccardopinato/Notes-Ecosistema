import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/adaptive_editor.dart';
import 'package:notes_ecosistema/src/domain/properties.dart';

void main() {
  PropertyDefinition definition(
    NotePropertyType type, {
    List<String> options = const [],
  }) =>
      PropertyDefinition(
        id: 'property-id',
        name: 'Proprietà',
        type: type,
        options: options,
        createdAt: 1,
        updatedAt: 1,
      );

  test('universal properties normalize typed values', () {
    expect(
      PropertyRules.normalizeValue(
        definition(NotePropertyType.number),
        '12.5',
      ),
      12.5,
    );
    expect(
      PropertyRules.normalizeValue(
        definition(
          NotePropertyType.select,
          options: const ['Todo', 'Doing', 'Done'],
        ),
        'doing',
      ),
      'Doing',
    );
    expect(
      PropertyRules.normalizeValue(
        definition(
          NotePropertyType.multiSelect,
          options: const ['A', 'B', 'C'],
        ),
        ['a', 'B', 'a'],
      ),
      ['A', 'B'],
    );
    expect(
      PropertyRules.normalizeValue(
        definition(NotePropertyType.checkbox),
        true,
      ),
      isTrue,
    );
  });

  test('property definitions reject invalid option contracts', () {
    expect(
      () => PropertyRules.validateDefinition(
        definition(NotePropertyType.select),
      ),
      throwsFormatException,
    );
    expect(
      () => PropertyRules.validateDefinition(
        definition(
          NotePropertyType.text,
          options: const ['not allowed'],
        ),
      ),
      throwsFormatException,
    );
  });

  test('adaptive editor keeps normal notes in full mode', () {
    final profile = AdaptiveEditorPolicy.evaluate('Nota breve\ncon testo');
    expect(profile.level, AdaptiveEditorLevel.full);
    expect(profile.liveBlockParsing, isTrue);
    expect(profile.draftDebounce, const Duration(milliseconds: 280));
  });

  test('adaptive editor degrades large notes before they freeze', () {
    final reduced = AdaptiveEditorPolicy.evaluate('x' * (70 * 1024));
    expect(reduced.level, AdaptiveEditorLevel.reduced);
    expect(reduced.liveBlockParsing, isFalse);

    final minimal = AdaptiveEditorPolicy.evaluate('x' * (200 * 1024));
    expect(minimal.level, AdaptiveEditorLevel.minimal);
    expect(minimal.liveBlockParsing, isFalse);
    expect(minimal.draftDebounce, const Duration(milliseconds: 1200));
  });
}
