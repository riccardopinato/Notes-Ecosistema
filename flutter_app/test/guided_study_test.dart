import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/guided_study.dart';
import 'package:notes_ecosistema/src/domain/note.dart';

void main() {
  Note note(String body, {bool archived = false}) => Note(
        id: 'source',
        title: 'Study source',
        body: body,
        favorite: false,
        createdAt: 1,
        updatedAt: 2,
        pinned: false,
        archived: archived,
        tags: const [],
      );

  test('only explicit adjacent Q/A pairs generate verifiable drafts', () {
    final proposals = GuidedStudyExtractor.extract(
      note('Q: Capital of Italy?\nA: Rome\n'
          'Other random text\n'
          'Domanda: 2 + 2?\nRisposta: 4'),
    );
    expect(proposals.length, 2);
    expect(proposals.first.prompt, 'Capital of Italy?');
    expect(proposals.first.answer, 'Rome');
    expect(proposals.first.questionLine, 1);
    expect(proposals.last.questionLine, 4);
    expect(proposals.first.reasonCode, 'EXPLICIT_SOURCE_QA_PAIR');
  });

  test('no hallucinated answer, duplicate or non-authorized source', () {
    final input = note(
      'Q: No answer\nA different paragraph\n'
      'Q: Same?\nA: Yes\nQ: Same?\nA: Yes',
    );
    expect(GuidedStudyExtractor.extract(input).length, 1);
    expect(
      GuidedStudyExtractor.extract(input.copyWith(archived: true)),
      isEmpty,
    );
    expect(
      GuidedStudyExtractor.extract(input.copyWith(deletedAt: 100)),
      isEmpty,
    );
    expect(
      () => GuidedStudyExtractor.extract(input, limit: -1),
      throwsFormatException,
    );
    expect(GuidedStudyExtractor.extract(input, limit: 0), isEmpty);
  });

  test('later Q/A pairs remain available after earlier cards are saved', () {
    final source = note(
      List.generate(12, (index) => 'Q: Question $index?\nA: Answer $index')
          .join('\n'),
    );
    final first = GuidedStudyExtractor.extract(source);
    expect(first.length, 8);
    final existing = first
        .map(
          (draft) => '${draft.prompt}\u0000${draft.answer}',
        )
        .toSet();
    final later = GuidedStudyExtractor.extract(
      source,
      excludedPairs: existing,
    );
    expect(later.length, 4);
    expect(later.first.prompt, 'Question 8?');
    expect(later.last.prompt, 'Question 11?');
  });

  test('source excerpt retains exact Q/A even after 50k characters', () {
    final source = note(
      '${'x' * 51000}\nQ: Late question?\nA: Late answer',
    );
    final drafts = GuidedStudyExtractor.extract(source);
    expect(drafts.length, 1);
    expect(drafts.single.sourceExcerpt, 'Q: Late question?\nA: Late answer');
    expect(drafts.single.sourceExcerpt, contains(drafts.single.answer));
  });
  test('French and Portuguese labels retain verifiable source and line', () {
    final source = note(
      'Question: Capitale du Canada?\nRéponse: Ottawa\n'
      'Pergunta: Capital de Portugal?\nResposta: Lisboa\n'
      'Question: Dernière question?\nReponse: Confirmée',
    );
    final drafts = GuidedStudyExtractor.extract(source);
    expect(drafts.length, 3);
    expect(drafts.map((draft) => draft.questionLine), [1, 3, 5]);
    expect(drafts.map((draft) => draft.answer), [
      'Ottawa',
      'Lisboa',
      'Confirmée',
    ]);
    expect(
      drafts[1].sourceExcerpt,
      'Pergunta: Capital de Portugal?\nResposta: Lisboa',
    );
    expect(
        drafts.every((draft) => draft.reasonCode == 'EXPLICIT_SOURCE_QA_PAIR'),
        isTrue);
  });
}
