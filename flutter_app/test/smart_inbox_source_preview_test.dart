import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/contextual_work_insights.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/smart_inbox_source_preview.dart';

void main() {
  Note note(String body, {List<String> tags = const []}) => Note(
        id: 'n1',
        title: 'Source',
        body: body,
        favorite: false,
        createdAt: 1,
        updatedAt: 2,
        pinned: false,
        archived: false,
        tags: tags,
      );

  test('preview only source-authored pending checkboxes', () {
    final source = note('- [ ] Alpha\n- [x] Done\n* [ ] Beta\n- [ ] Alpha');
    final result = SmartInboxSourcePreview.inspect(InboxReviewSuggestion(
        source, InboxReviewKind.checklist, 'EXPLICIT_UNCHECKED_LIST'))!;
    expect(result.candidates, ['Alpha', 'Beta']);
    expect(result.sourceExcerpt, '- [ ] Alpha');
    expect(result.current([source]), same(source));
  });

  test('Unicode hashtags skip already-applied tags', () {
    final source = note('Nota #caffè #déjà_vu #esistente', tags: ['esistente']);
    final result = SmartInboxSourcePreview.inspect(InboxReviewSuggestion(source,
        InboxReviewKind.explicitTags, 'EXPLICIT_HASHTAGS_NOT_APPLIED'))!;
    expect(result.candidates, ['caffè', 'déjà_vu']);
  });

  test('existing tags do not hide unchecked checklist tasks', () {
    final source = note('- [ ] Shopping', tags: ['shopping']);
    final result = SmartInboxSourcePreview.inspect(InboxReviewSuggestion(
        source, InboxReviewKind.checklist, 'EXPLICIT_UNCHECKED_LIST'));
    expect(result, isNotNull);
    expect(result!.candidates, ['Shopping']);
  });

  test('selected tags require explicit source candidates and remain draft-only', () {
    final source = note('Documento #caffè #nuovo', tags: ['esistente']);
    final preview = SmartInboxSourcePreview.inspect(InboxReviewSuggestion(
      source, InboxReviewKind.explicitTags, 'EXPLICIT_HASHTAGS_NOT_APPLIED'))!;
    expect(preview.selectedTagDraft(['nuovo']), ['esistente', 'nuovo']);
    expect(source.tags, ['esistente']);
    expect(() => preview.selectedTagDraft([]), throwsFormatException);
    expect(() => preview.selectedTagDraft(['segreto']), throwsFormatException);
  });

  test('source change, hidden record and duplicate identity fail closed', () {
    final source = note('- [ ] Alpha');
    final result = SmartInboxSourcePreview.inspect(InboxReviewSuggestion(
        source, InboxReviewKind.checklist, 'EXPLICIT_UNCHECKED_LIST'))!;
    expect(result.current([]), isNull);
    expect(result.current([source, source]), isNull);
    expect(result.current([source.copyWith(updatedAt: 3)]), isNull);
    expect(result.current([source.copyWith(body: '- [ ] Beta')]), isNull);
    expect(result.current([source.copyWith(archived: true)]), isNull);
    expect(result.current([source.copyWith(deletedAt: 100)]), isNull);
  });

  test('unlabeled text does not produce candidates', () {
    expect(
        SmartInboxSourcePreview.inspect(InboxReviewSuggestion(
            note('An ordinary paragraph'),
            InboxReviewKind.checklist,
            'EXPLICIT_UNCHECKED_LIST')),
        isNull);
  });
}
