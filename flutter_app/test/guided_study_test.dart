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
}
