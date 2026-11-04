/// Source-projected, read-only duplicate review using a scoped MinHash+LSH
/// translation of App-Factory-Core@f5dad948dcc1096864cd4b9db84b9f0d86c9cb03
/// reference_engines/lib/src/local_ml_candidates.dart (ML10 / CAP-0116).
///
/// Input MUST be account- and ACL-authorized by the parent workspace.
/// This module never opens editors, mutates notes, merges or removes records.
/// Signatures are ephemeral; no derived private index is persisted.
library;

import 'note.dart';

final class NoteDuplicatePair {
  const NoteDuplicatePair({
    required this.first,
    required this.second,
    required this.jaccard,
  });

  final Note first;
  final Note second;
  final double jaccard;
}

final class _NoteSketch {
  const _NoteSketch(this.note, this.features, this.signature);

  final Note note;
  final Set<String> features;
  final List<int> signature;
}

abstract final class NoteDuplicateReview {
  static final RegExp _words = RegExp(
    r'[\p{L}\p{M}\p{N}]+',
    unicode: true,
  );
  static const _prime = 2147483647;
  static const _signatureSize = 64;
  static const _rowsPerBand = 4;
  static const _maxNotes = 300;

  static Set<String> _shingles(String text) {
    if (text.length > 4000) return const {};
    final words = _words
        .allMatches(text.toLowerCase())
        .map((m) => m.group(0)!)
        .where((w) => w.runes.length >= 2 && w.runes.length <= 48)
        .take(301)
        .toList(growable: false);
    if (words.length < 2 || words.length > 300) return const {};
    return {
      for (var i = 1; i < words.length; i++)
        '${words[i - 1]} \u0001 ${words[i]}',
    };
  }

  static int _stableHash(String value) {
    var hash = 5381;
    for (final rune in value.runes) {
      hash = ((hash * 33) + rune) & 0x7fffffff;
    }
    return hash;
  }

  static List<int> _signature(Set<String> features) {
    final result = List<int>.filled(_signatureSize, _prime);
    for (final term in features) {
      final hashed = _stableHash(term);
      for (var i = 0; i < _signatureSize; i++) {
        final a = ((i + 1) * 1009) % 20000 + 1;
        final b = ((i + 1) * 7919) % 20000;
        final value = (a * hashed + b) % _prime;
        if (value < result[i]) result[i] = value;
      }
    }
    return result;
  }

  static bool _bandMatch(List<int> a, List<int> b) {
    for (var band = 0; band < _signatureSize ~/ _rowsPerBand; band++) {
      var same = true;
      for (var i = 0; i < _rowsPerBand; i++) {
        final at = band * _rowsPerBand + i;
        if (a[at] != b[at]) {
          same = false;
          break;
        }
      }
      if (same) return true;
    }
    return false;
  }

  static double _jaccard(Set<String> a, Set<String> b) {
    var shared = 0;
    for (final term in a) {
      if (b.contains(term)) shared++;
    }
    return shared / (a.length + b.length - shared);
  }

  /// Scans only the visible, active note snapshot supplied by the caller.
  /// <=300 bounded records, 30 read-only pairs, no durable index or writes.
  /// Similarity is lexical (bigram Jaccard); it is NOT semantic identity.
  static List<NoteDuplicatePair> review(List<Note> authorizedNotes) {
    if (authorizedNotes.length > _maxNotes) return const [];
    final seen = <String>{};
    final prepared = <_NoteSketch>[];
    for (final note in authorizedNotes) {
      if (note.id.trim().isEmpty || !seen.add(note.id)) return const [];
      if (note.isDeleted || note.archived || note.isTask || note.isVisual) {
        continue;
      }
      final text = '${note.title}\n${note.body}';
      final features = _shingles(text);
      if (features.isEmpty) continue;
      prepared.add(_NoteSketch(note, features, _signature(features)));
    }
    prepared.sort((a, b) => a.note.id.compareTo(b.note.id));
    final result = <NoteDuplicatePair>[];
    for (var i = 0; i < prepared.length; i++) {
      for (var j = i + 1; j < prepared.length; j++) {
        final a = prepared[i];
        final b = prepared[j];
        if (!_bandMatch(a.signature, b.signature)) continue;
        final score = _jaccard(a.features, b.features);
        if (score < 0.78) continue;
        result.add(NoteDuplicatePair(
          first: a.note,
          second: b.note,
          jaccard: score,
        ));
      }
    }
    result.sort((a, b) {
      final score = b.jaccard.compareTo(a.jaccard);
      if (score != 0) return score;
      final first = a.first.id.compareTo(b.first.id);
      return first != 0 ? first : a.second.id.compareTo(b.second.id);
    });
    return List.unmodifiable(result.take(30));
  }

  /// Full snapshot revalidation immediately before opening a canonical editor.
  /// The caller must pass the CURRENT authorized source, not the old snapshot.
  static Note? revalidate(Note original, Iterable<Note> currentAuthorized) {
    Note? match;
    for (final note in currentAuthorized) {
      if (note.id != original.id) continue;
      if (match != null) return null;
      match = note;
    }
    if (match == null ||
        match.isDeleted ||
        match.archived ||
        match.isTask ||
        match.isVisual ||
        match.updatedAt != original.updatedAt ||
        match.title != original.title ||
        match.body != original.body ||
        match.collectionId != original.collectionId ||
        match.tags.length != original.tags.length) {
      return null;
    }
    for (var i = 0; i < match.tags.length; i++) {
      if (match.tags[i] != original.tags[i]) return null;
    }
    return match;
  }
}
