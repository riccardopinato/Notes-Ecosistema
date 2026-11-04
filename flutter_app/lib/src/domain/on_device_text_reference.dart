/// Local text subset extracted from App-Factory-Core@ae76e4267b67fe0e913d650d8e89a010dd235a5c.
/// Sensor portion excluded; candidate E5 limited to text consumer.
/// These reference functions do not own storage, permissions, native sensor
/// listeners, models, scheduling, notifications or application writes.
library;

import 'dart:math' as math;

final class OnDeviceMathError implements Exception {
  const OnDeviceMathError(this.code);
  final String code;
  @override
  String toString() => 'OnDeviceMathError($code)';
}

final class LocalTextCandidate {
  const LocalTextCandidate({
    required this.id,
    required this.text,
    this.visible = true,
    this.deleted = false,
    this.revision = 0,
  });
  final String id;
  final String text;
  final bool visible;
  final bool deleted;
  final int revision;
}

final class LocalFuzzyHit {
  const LocalFuzzyHit(this.candidate, this.distance);
  final LocalTextCandidate candidate;
  final int distance;
}

/// Read-only bounded typo matching over authorized input candidates.
/// The app MUST filter ACLs before calling this code. Here it additionally
/// refuses items marked hidden/deleted; it cannot infer an account's ACL.
abstract final class LocalFuzzyReference {
  static final RegExp _words = RegExp(
    r'[\p{L}\p{M}\p{N}]+', unicode: true,
  );

  static int distance(String a, String b, {int cutoff = 3}) {
    if (cutoff < 0 || cutoff > 20) {
      throw const OnDeviceMathError('INVALID_CUTOFF');
    }
    final left = a.toLowerCase().runes.toList(growable: false);
    final right = b.toLowerCase().runes.toList(growable: false);
    if (left.length > 64 || right.length > 64) {
      throw const OnDeviceMathError('UNBOUNDED_TOKEN');
    }
    if ((left.length - right.length).abs() > cutoff) return cutoff + 1;
    var previous = List<int>.generate(right.length + 1, (i) => i);
    for (var row = 1; row <= left.length; row++) {
      final next = List<int>.filled(right.length + 1, 0);
      next[0] = row;
      var rowMin = next[0];
      for (var col = 1; col <= right.length; col++) {
        final substitution = left[row - 1] == right[col - 1] ? 0 : 1;
        next[col] = math.min(
          math.min(next[col - 1] + 1, previous[col] + 1),
          previous[col - 1] + substitution,
        );
        rowMin = math.min(rowMin, next[col]);
      }
      if (rowMin > cutoff) return cutoff + 1;
      previous = next;
    }
    return previous[right.length];
  }

  static List<LocalFuzzyHit> search(
    String query,
    Iterable<LocalTextCandidate> source, {
    int maxCandidates = 400,
    int maxDistance = 2,
    int limit = 10,
  }) {
    if (limit < 1 || limit > 100 || maxCandidates < 1 ||
        maxCandidates > 5000 || maxDistance < 0 || maxDistance > 20) {
      throw const OnDeviceMathError('INVALID_SEARCH_LIMIT');
    }
    final normalizedQuery = query.toLowerCase().trim();
    if (normalizedQuery.isEmpty || normalizedQuery.runes.length > 64) {
      throw const OnDeviceMathError('INVALID_QUERY');
    }
    final found = <LocalFuzzyHit>[];
    final seen = <String>{};
    var count = 0;
    for (final item in source) {
      if (++count > maxCandidates) {
        throw const OnDeviceMathError('TOO_MANY_CANDIDATES');
      }
      if (item.id.trim().isEmpty || item.revision < 0 ||
          item.text.length > 2000 || !seen.add(item.id)) {
        throw const OnDeviceMathError('INVALID_OR_DUPLICATE_SOURCE');
      }
      if (!item.visible || item.deleted) continue;
      var best = maxDistance + 1;
      for (final match in _words.allMatches(item.text)) {
        final token = match.group(0)!;
        if (token.runes.length > 64) continue;
        final value = distance(normalizedQuery, token, cutoff: maxDistance);
        if (value < best) best = value;
        if (best == 0) break;
      }
      if (best <= maxDistance) found.add(LocalFuzzyHit(item, best));
    }
    found.sort((a, b) {
      final diff = a.distance.compareTo(b.distance);
      return diff != 0 ? diff : a.candidate.id.compareTo(b.candidate.id);
    });
    return List.unmodifiable(found.take(limit));
  }
}

final class LocalKeywordScore {
  const LocalKeywordScore(this.term, this.score);
  final String term;
  final double score;
}

/// Corpus-local lexical TF-IDF; this is NOT a trained semantic embedding.
/// The source must be a bounded set of authorized, current documents.
abstract final class LocalTfidfReference {
  static final RegExp _terms = RegExp(
    r'[\p{L}\p{M}\p{N}]+', unicode: true,
  );

  static List<String> tokenize(String text, {Set<String> stopwords = const {}}) {
    if (text.length > 20000) {
      throw const OnDeviceMathError('OVERSIZE_DOCUMENT');
    }
    return List.unmodifiable(
      _terms.allMatches(text.toLowerCase())
          .map((match) => match.group(0)!)
          .where((word) => word.runes.length >= 2 &&
              word.runes.length <= 32 && !stopwords.contains(word))
          .take(2000),
    );
  }

  static List<LocalKeywordScore> keywords({
    required String document,
    required Iterable<String> visibleCorpus,
    Set<String> stopwords = const {},
    int limit = 8,
  }) {
    if (limit < 1 || limit > 50) {
      throw const OnDeviceMathError('INVALID_KEYWORD_LIMIT');
    }
    final corpus = <Set<String>>[];
    for (final text in visibleCorpus) {
      if (corpus.length == 5000) {
        throw const OnDeviceMathError('UNBOUNDED_CORPUS');
      }
      corpus.add(tokenize(text, stopwords: stopwords).toSet());
    }
    final tokens = tokenize(document, stopwords: stopwords);
    if (tokens.isEmpty || corpus.isEmpty) return const [];
    final frequency = <String, int>{};
    for (final token in tokens) {
      frequency[token] = (frequency[token] ?? 0) + 1;
    }
    final df = <String, int>{};
    for (final terms in corpus) {
      for (final token in frequency.keys) {
        if (terms.contains(token)) {
          df[token] = (df[token] ?? 0) + 1;
        }
      }
    }
    final scores = frequency.entries.map((entry) {
      final tf = entry.value / tokens.length;
      final idf = math.log((1 + corpus.length) / (1 + (df[entry.key] ?? 0))) + 1;
      return LocalKeywordScore(entry.key, tf * idf);
    }).toList();
    scores.sort((a, b) {
      final comparison = b.score.compareTo(a.score);
      return comparison != 0 ? comparison : a.term.compareTo(b.term);
    });
    return List.unmodifiable(scores.take(limit));
  }
}

