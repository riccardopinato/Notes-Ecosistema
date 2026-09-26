import 'dart:math' as math;

import 'note.dart';

class KnowledgeHit {
  const KnowledgeHit({
    required this.note,
    required this.score,
    required this.excerpt,
  });

  final Note note;
  final double score;
  final String excerpt;

  String citation(int index) =>
      '[$index] ${note.title.trim().isEmpty ? 'Senza titolo' : note.title}';
}

class KnowledgeQueryResult {
  const KnowledgeQueryResult({
    required this.query,
    required this.hits,
  });

  final String query;
  final List<KnowledgeHit> hits;

  bool get empty => hits.isEmpty;
}

abstract interface class KnowledgeRetrievalEngine {
  KnowledgeQueryResult ask(String query, List<Note> notes, {int limit = 8});
  List<KnowledgeHit> related(Note source, List<Note> notes, {int limit = 6});
}

class LocalKnowledgeRetrieval implements KnowledgeRetrievalEngine {
  const LocalKnowledgeRetrieval();

  @override
  KnowledgeQueryResult ask(
    String query,
    List<Note> notes, {
    int limit = 8,
  }) {
    final queryVector = _vector(query);
    if (queryVector.isEmpty) {
      return KnowledgeQueryResult(query: query, hits: const []);
    }
    final hits = <KnowledgeHit>[];
    for (final note in _eligible(notes)) {
      final score = _cosine(queryVector, _vector('${note.title}\n${note.body}'));
      if (score <= 0) continue;
      hits.add(
        KnowledgeHit(
          note: note,
          score: score,
          excerpt: _excerpt(note.body, query),
        ),
      );
    }
    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.note.updatedAt.compareTo(a.note.updatedAt);
    });
    return KnowledgeQueryResult(
      query: query.trim(),
      hits: hits.take(limit.clamp(1, 30)).toList(growable: false),
    );
  }

  @override
  List<KnowledgeHit> related(
    Note source,
    List<Note> notes, {
    int limit = 6,
  }) {
    final sourceVector = _vector('${source.title}\n${source.body}');
    if (sourceVector.isEmpty) return const [];
    final hits = <KnowledgeHit>[];
    for (final note in _eligible(notes)) {
      if (note.id == source.id) continue;
      final score = _cosine(sourceVector, _vector('${note.title}\n${note.body}'));
      if (score < .08) continue;
      hits.add(
        KnowledgeHit(
          note: note,
          score: score,
          excerpt: _excerpt(note.body, source.title),
        ),
      );
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit.clamp(1, 20)).toList(growable: false);
  }

  static Iterable<Note> _eligible(List<Note> notes) => notes.where(
        (note) =>
            !note.isDeleted &&
            !note.archived &&
            !note.isVisual &&
            !note.isTask &&
            (note.title.trim().isNotEmpty || note.body.trim().isNotEmpty),
      );

  static Map<String, double> _vector(String text) {
    final tokens = _tokens(text);
    if (tokens.isEmpty) return const {};
    final counts = <String, double>{};
    for (final token in tokens) {
      counts.update(token, (value) => value + 1, ifAbsent: () => 1);
    }
    final norm = math.sqrt(
      counts.values.fold<double>(0, (sum, value) => sum + value * value),
    );
    if (norm == 0) return const {};
    return {
      for (final entry in counts.entries) entry.key: entry.value / norm,
    };
  }

  static double _cosine(
    Map<String, double> a,
    Map<String, double> b,
  ) {
    if (a.isEmpty || b.isEmpty) return 0;
    var score = 0.0;
    final smaller = a.length <= b.length ? a : b;
    final larger = identical(smaller, a) ? b : a;
    for (final entry in smaller.entries) {
      score += entry.value * (larger[entry.key] ?? 0);
    }
    return score;
  }

  static List<String> _tokens(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'https?://\S+'), ' ')
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ');
    final raw = normalized
        .split(RegExp(r'\s+'))
        .where((token) => token.length >= 2)
        .toList(growable: false);
    final result = <String>[];
    for (final token in raw) {
      if (_stopWords.contains(token)) continue;
      result.add(_stem(token));
    }
    return result;
  }

  static String _stem(String token) {
    for (final suffix in const [
      'mente',
      'zioni',
      'zione',
      'ando',
      'endo',
      'ato',
      'ito',
      'are',
      'ere',
      'ire',
      'ati',
      'iti',
      'ale',
      'ali',
    ]) {
      if (token.length > suffix.length + 3 && token.endsWith(suffix)) {
        return token.substring(0, token.length - suffix.length);
      }
    }
    return token;
  }

  static String _excerpt(String body, String query) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) return 'Nessun estratto.';
    final terms = _tokens(query);
    var index = -1;
    for (final term in terms) {
      index = compact.toLowerCase().indexOf(term);
      if (index >= 0) break;
    }
    final start = index < 0 ? 0 : math.max(0, index - 90);
    final end = math.min(compact.length, start + 260);
    return '${start > 0 ? '…' : ''}${compact.substring(start, end)}'
        '${end < compact.length ? '…' : ''}';
  }

  static const _stopWords = {
    'che',
    'con',
    'del',
    'della',
    'delle',
    'degli',
    'dei',
    'per',
    'una',
    'uno',
    'gli',
    'le',
    'la',
    'il',
    'lo',
    'un',
    'di',
    'da',
    'in',
    'su',
    'e',
    'o',
    'a',
    'the',
    'and',
    'for',
    'with',
    'this',
    'that',
  };
}
