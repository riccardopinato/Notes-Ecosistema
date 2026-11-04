import 'note.dart';
import 'study.dart';

/// Only adjacent, explicitly labeled source-authored Q/A pairs, including
/// Markdown list and heading wrappers. Never synthesize an answer.
class GuidedStudyProposal {
  const GuidedStudyProposal({
    required this.source,
    required this.prompt,
    required this.answer,
    required this.questionLine,
    required this.sourceExcerpt,
  });

  final Note source;
  final String prompt;
  final String answer;
  final int questionLine;
  final String sourceExcerpt;
  String get reasonCode => 'EXPLICIT_SOURCE_QA_PAIR';
}

abstract final class GuidedStudyExtractor {
  static final RegExp _question = RegExp(
    r'^\s*(?:#{1,6}\s+|[-*]\s+)?(?:\*\*)?(?:Q|Question|Domanda|Pregunta|Frage|Pergunta):(?:\*\*)?\s*(.+?)\s*
    caseSensitive: false,
  );
  static final RegExp _answer = RegExp(
    r'^\s*(?:#{1,6}\s+|[-*]\s+)?(?:\*\*)?(?:A|Answer|Risposta|Respuesta|Antwort|R[eé]ponse|Resposta):(?:\*\*)?\s*(.+?)\s*
    caseSensitive: false,
  );

  static List<GuidedStudyProposal> extract(
    Note note, {
    int limit = 8,
    Set<String> excludedPairs = const {},
  }) {
    if (limit < 0 || limit > 30) {
      throw const FormatException('INVALID_GUIDED_STUDY_LIMIT');
    }
    if (limit == 0 ||
        note.isDeleted ||
        note.archived ||
        note.isTask ||
        note.isVisual) {
      return const [];
    }
    final lines = note.body.split('\n');
    final result = <GuidedStudyProposal>[];
    final seen = <String>{};
    for (var i = 0; i < lines.length - 1; i++) {
      final question = _question.firstMatch(lines[i]);
      final answer = _answer.firstMatch(lines[i + 1]);
      if (question == null || answer == null) continue;
      final prompt = question.group(1)!.trim();
      final response = answer.group(1)!.trim();
      if (prompt.isEmpty ||
          response.isEmpty ||
          prompt.length > StudyRules.maxPrompt ||
          response.length > StudyRules.maxAnswer) {
        continue;
      }
      final key = '$prompt\u0000$response';
      if (!seen.add(key) || excludedPairs.contains(key)) continue;
      final excerpt = '${lines[i]}\n${lines[i + 1]}';
      if (excerpt.length > StudyRules.maxSnapshot) continue;
      result.add(
        GuidedStudyProposal(
          source: note,
          prompt: prompt,
          answer: response,
          questionLine: i + 1,
          sourceExcerpt: excerpt,
        ),
      );
      if (result.length >= limit) break;
      i++; // One answer cannot be reused as another question.
    }
    return List.unmodifiable(result);
  }
}
,
    caseSensitive: false,
  );
  static final RegExp _answer = RegExp(
    r'^\s*(?:A|Answer|Risposta|Respuesta|Antwort|R[eé]ponse|Resposta):\s*(.+?)\s*$',
    caseSensitive: false,
  );

  static List<GuidedStudyProposal> extract(
    Note note, {
    int limit = 8,
    Set<String> excludedPairs = const {},
  }) {
    if (limit < 0 || limit > 30) {
      throw const FormatException('INVALID_GUIDED_STUDY_LIMIT');
    }
    if (limit == 0 ||
        note.isDeleted ||
        note.archived ||
        note.isTask ||
        note.isVisual) {
      return const [];
    }
    final lines = note.body.split('\n');
    final result = <GuidedStudyProposal>[];
    final seen = <String>{};
    for (var i = 0; i < lines.length - 1; i++) {
      final question = _question.firstMatch(lines[i]);
      final answer = _answer.firstMatch(lines[i + 1]);
      if (question == null || answer == null) continue;
      final prompt = question.group(1)!.trim();
      final response = answer.group(1)!.trim();
      if (prompt.isEmpty ||
          response.isEmpty ||
          prompt.length > StudyRules.maxPrompt ||
          response.length > StudyRules.maxAnswer) {
        continue;
      }
      final key = '$prompt\u0000$response';
      if (!seen.add(key) || excludedPairs.contains(key)) continue;
      final excerpt = '${lines[i]}\n${lines[i + 1]}';
      if (excerpt.length > StudyRules.maxSnapshot) continue;
      result.add(
        GuidedStudyProposal(
          source: note,
          prompt: prompt,
          answer: response,
          questionLine: i + 1,
          sourceExcerpt: excerpt,
        ),
      );
      if (result.length >= limit) break;
      i++; // One answer cannot be reused as another question.
    }
    return List.unmodifiable(result);
  }
}
,
    caseSensitive: false,
  );

  static List<GuidedStudyProposal> extract(
    Note note, {
    int limit = 8,
    Set<String> excludedPairs = const {},
  }) {
    if (limit < 0 || limit > 30) {
      throw const FormatException('INVALID_GUIDED_STUDY_LIMIT');
    }
    if (limit == 0 ||
        note.isDeleted ||
        note.archived ||
        note.isTask ||
        note.isVisual) {
      return const [];
    }
    final lines = note.body.split('\n');
    final result = <GuidedStudyProposal>[];
    final seen = <String>{};
    for (var i = 0; i < lines.length - 1; i++) {
      final question = _question.firstMatch(lines[i]);
      final answer = _answer.firstMatch(lines[i + 1]);
      if (question == null || answer == null) continue;
      final prompt = question.group(1)!.trim();
      final response = answer.group(1)!.trim();
      if (prompt.isEmpty ||
          response.isEmpty ||
          prompt.length > StudyRules.maxPrompt ||
          response.length > StudyRules.maxAnswer) {
        continue;
      }
      final key = '$prompt\u0000$response';
      if (!seen.add(key) || excludedPairs.contains(key)) continue;
      final excerpt = '${lines[i]}\n${lines[i + 1]}';
      if (excerpt.length > StudyRules.maxSnapshot) continue;
      result.add(
        GuidedStudyProposal(
          source: note,
          prompt: prompt,
          answer: response,
          questionLine: i + 1,
          sourceExcerpt: excerpt,
        ),
      );
      if (result.length >= limit) break;
      i++; // One answer cannot be reused as another question.
    }
    return List.unmodifiable(result);
  }
}
,
    caseSensitive: false,
  );
  static final RegExp _answer = RegExp(
    r'^\s*(?:A|Answer|Risposta|Respuesta|Antwort|R[eé]ponse|Resposta):\s*(.+?)\s*$',
    caseSensitive: false,
  );

  static List<GuidedStudyProposal> extract(
    Note note, {
    int limit = 8,
    Set<String> excludedPairs = const {},
  }) {
    if (limit < 0 || limit > 30) {
      throw const FormatException('INVALID_GUIDED_STUDY_LIMIT');
    }
    if (limit == 0 ||
        note.isDeleted ||
        note.archived ||
        note.isTask ||
        note.isVisual) {
      return const [];
    }
    final lines = note.body.split('\n');
    final result = <GuidedStudyProposal>[];
    final seen = <String>{};
    for (var i = 0; i < lines.length - 1; i++) {
      final question = _question.firstMatch(lines[i]);
      final answer = _answer.firstMatch(lines[i + 1]);
      if (question == null || answer == null) continue;
      final prompt = question.group(1)!.trim();
      final response = answer.group(1)!.trim();
      if (prompt.isEmpty ||
          response.isEmpty ||
          prompt.length > StudyRules.maxPrompt ||
          response.length > StudyRules.maxAnswer) {
        continue;
      }
      final key = '$prompt\u0000$response';
      if (!seen.add(key) || excludedPairs.contains(key)) continue;
      final excerpt = '${lines[i]}\n${lines[i + 1]}';
      if (excerpt.length > StudyRules.maxSnapshot) continue;
      result.add(
        GuidedStudyProposal(
          source: note,
          prompt: prompt,
          answer: response,
          questionLine: i + 1,
          sourceExcerpt: excerpt,
        ),
      );
      if (result.length >= limit) break;
      i++; // One answer cannot be reused as another question.
    }
    return List.unmodifiable(result);
  }
}
