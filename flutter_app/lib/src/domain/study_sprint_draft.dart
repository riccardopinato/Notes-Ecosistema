import 'templates.dart';

/// A prepared Notes draft only. This never persists a Note or a Task.
class StudySprintDraftPlan {
  const StudySprintDraftPlan({
    required this.title,
    required this.declaredSource,
    required this.topicsInput,
    required this.includeQuestions,
    required this.includeReview,
  });

  final String title;
  final String declaredSource;
  final String topicsInput;
  final bool includeQuestions;
  final bool includeReview;

  /// A future explicit "Open in editor" action may hand this object to the
  /// existing TemplatesScreen.onUse -> canonical Note editor flow.
  /// Neither construction nor preparation writes user data.
  TemplateContent prepareForEditor({required bool userConfirmed}) {
    if (!userConfirmed) {
      throw StateError('study_sprint_explicit_confirmation_required');
    }
    final name = title.trim();
    final source = declaredSource.trim();
    if (name.isEmpty || name.length > 100 || name.contains('\n') ||
        name.contains('\r') || source.isEmpty || source.length > 150 ||
        source.contains('\n') || source.contains('\r') ||
        topicsInput.length > 500) {
      throw const FormatException('study_sprint_invalid_input');
    }

    final topics = topicsInput
        .split(RegExp(r'\r?\n'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (topics.isEmpty || topics.length > 8) {
      throw const FormatException('study_sprint_topics_out_of_range');
    }
    final lines = <String>[
      '# $name',
      '',
      'Fonte dichiarata: $source',
      '',
      '## Argomenti',
      ...topics.map((topic) => '- $topic'),
      if (includeQuestions) ...[
        '',
        '## Domande scritte da me',
        '- Quale concetto voglio chiarire?',
      ],
      if (includeReview) ...[
        '',
        '## Ripasso',
        '- [ ] Rivedere gli appunti',
        '- [ ] Rispondere alle domande',
      ],
    ];
    final body = lines.join('\n');
    if (body.length > 200000) {
      throw const FormatException('study_sprint_body_too_large');
    }
    return TemplateContent(name, body, const <String>['studio']);
  }
}
