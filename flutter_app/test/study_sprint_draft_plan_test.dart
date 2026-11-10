import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/study_sprint_draft.dart';

void main() {
  StudySprintDraftPlan valid(String topics) => StudySprintDraftPlan(
        title: 'Sessione di studio',
        declaredSource: 'Appunti personali',
        topicsInput: topics,
        includeQuestions: true,
        includeReview: true,
      );

  test('No editor payload without explicit user confirmation', () {
    expect(() => valid('Tema 1').prepareForEditor(userConfirmed: false),
        throwsStateError);
  });

  test('Prepared payload uses canonical editable Note content, not Tasks', () {
    final draft = valid('A\r\nB\nC').prepareForEditor(userConfirmed: true);
    expect(draft.title, 'Sessione di studio');
    expect(draft.body, contains('- A\n- B\n- C'));
    expect(draft.body, contains('Fonte dichiarata: Appunti personali'));
    expect(draft.body, contains('- [ ] Rivedere gli appunti'));
    expect(draft.tags, ['studio']);
    expect(draft.tags, isNot(contains('modello')));
  });

  test('More than eight topics is rejected, never silently truncated', () {
    final nine = List.generate(9, (i) => 'Argomento $i').join('\n');
    expect(() => valid(nine).prepareForEditor(userConfirmed: true),
        throwsFormatException);
  });

  test('Empty source and oversized fields fail before editor handoff', () {
    expect(
      () => const StudySprintDraftPlan(
        title: 'A',
        declaredSource: '',
        topicsInput: 'T',
        includeQuestions: false,
        includeReview: false,
      ).prepareForEditor(userConfirmed: true),
      throwsFormatException,
    );
    expect(() => valid(List<String>.filled(501, 'a').join()).prepareForEditor(userConfirmed: true),
        throwsFormatException);
  });
}
