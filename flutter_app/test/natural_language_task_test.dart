import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/natural_language_task.dart';

void main() {
  final reference = DateTime(2026, 11, 5); // Thursday

  test('Italian Friday and high priority are extracted locally', () {
    final draft = NaturalLanguageTask.parse(
      'Prepara la presentazione entro venerdì, priorità alta',
      today: reference,
    );
    expect(draft.title, 'Prepara la presentazione');
    expect(draft.due, '2026-11-06');
    expect(draft.priority, 3);
    expect(draft.unknownParts, isEmpty);
  });

  test('English tomorrow and low priority', () {
    final draft = NaturalLanguageTask.parse(
      'Send report by tomorrow priority low',
      today: reference,
    );
    expect(draft.title, 'Send report');
    expect(draft.due, '2026-11-06');
    expect(draft.priority, 1);
  });

  test('ambiguous numeric dates are never fabricated', () {
    final draft = NaturalLanguageTask.parse(
      'Incontrare il cliente 05/11/2026',
      today: reference,
    );
    expect(draft.due, isNull);
    expect(draft.unknownParts, isNotEmpty);
  });

  test('invalid ISO date stays reviewable, rejected at save', () {
    final draft = NaturalLanguageTask.parse(
      'Call Andrea by 2026-02-30',
      today: reference,
    );
    expect(draft.due, isNull);
    expect(draft.unknownParts, isNotEmpty);
    expect(
        () => NaturalLanguageTask.validateEdited(
              title: 'Call Andrea',
              due: '2026-02-30',
              priority: 2,
            ),
        throwsFormatException);
  });

  test('past ISO deadline is not silently moved to the future', () {
    final draft = NaturalLanguageTask.parse(
      'Archive by 2026-11-01',
      today: reference,
    );
    expect(draft.due, '2026-11-01');
  });

  test('multiple priority and deadline markers require manual review', () {
    final draft = NaturalLanguageTask.parse(
      'Call by Friday by Monday priority high priority low',
      today: reference,
    );
    expect(draft.due, isNull);
    expect(draft.priority, 0);
    expect(draft.unknownParts, hasLength(2));
  });

  test('editing validation enforces limits without writing', () {
    expect(() => NaturalLanguageTask.parse('', today: reference),
        throwsFormatException);
    expect(
        () => NaturalLanguageTask.validateEdited(
              title: '',
              due: '',
              priority: 1,
            ),
        throwsFormatException);
    expect(
        () => NaturalLanguageTask.validateEdited(
              title: 'okay',
              due: '',
              priority: 9,
            ),
        throwsFormatException);
    final valid = NaturalLanguageTask.validateEdited(
      title: 'Task',
      due: '',
      priority: 2,
    );
    expect(valid.due, isNull);
    expect(valid.priority, 2);
  });
}
