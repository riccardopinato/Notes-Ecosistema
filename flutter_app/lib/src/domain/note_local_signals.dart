import 'note.dart';
import 'on_device_text_reference.dart';
import 'unified_retrieval.dart';

/// Read-only app consumer; never owns permissions, storage or writes.
/// Caller MUST pass only account/ACL-authorized notes.
abstract final class NoteLocalSignals {
  static final _singleTerm =
      RegExp(r'^[\p{L}\p{M}\p{N}]{4,64}$', unicode: true);
  static final _tagTerm =
      RegExp(r'^[\p{L}\p{M}][\p{L}\p{M}\p{N}]{1,31}$', unicode: true);
  static const _stopwords = <String>{
    'the',
    'and',
    'for',
    'with',
    'from',
    'this',
    'that',
    'are',
    'una',
    'uno',
    'che',
    'con',
    'per',
    'del',
    'della',
    'delle',
    'non',
    'sono',
    'nel',
    'nella',
    'anche',
    'come',
    'gli',
    'dei',
    'les',
    'des',
    'une',
    'pour',
    'dans',
    'avec',
    'est',
    'der',
    'die',
    'das',
    'und',
    'mit',
    'ein',
    'eine',
    'ist',
    'los',
    'las',
    'para',
    'por',
    'dos',
    'uma',
    'não',
    'com',
  };

  static String _boundedText(RetrievalDocument doc) {
    final value = [doc.title, ...doc.tags, doc.text].join(' ');
    return value.length <= 2000 ? value : value.substring(0, 2000);
  }

  /// Fuzzy is a supplementary typo fallback, not a new index/authority.
  static List<RetrievalHit> fuzzyFallback({
    required String query,
    required Iterable<Note> notes,
    Set<String> excludedNoteIds = const {},
    int limit = 10,
  }) {
    final needle = query.trim().toLowerCase();
    if (!_singleTerm.hasMatch(needle) || needle.runes.length > 64 || limit < 1) {
      return const [];
    }
    final docs = UnifiedRetrieval.noteDocuments(notes);
    if (docs.length > 5000) return const [];
    final byId = <String, RetrievalDocument>{
      for (final doc in docs) doc.id: doc,
    };
    try {
      final hits = LocalFuzzyReference.search(
        needle,
        [
          for (final doc in docs)
            LocalTextCandidate(
              id: doc.id,
              text: _boundedText(doc),
              revision: doc.updatedAt < 0 ? 0 : doc.updatedAt,
            ),
        ],
        maxCandidates: 5000,
        maxDistance: needle.runes.length < 6 ? 1 : 2,
        limit: (limit * 4).clamp(1, 100).toInt(),
      );
      return List.unmodifiable([
        for (final hit in hits)
          if (!excludedNoteIds.contains(hit.candidate.id.substring(5)))
            RetrievalHit(
              document: byId[hit.candidate.id]!,
              score: 10 / (1 + hit.distance),
              excerpt: UnifiedRetrieval.excerpt(
                  byId[hit.candidate.id]!.text, needle),
            ),
      ].take(limit));
    } on OnDeviceMathError {
      return const [];
    }
  }

  /// TF-IDF lexical proposals. Never silently write tags.
  static List<String> tagProposals({
    required String title,
    required String body,
    required Iterable<Note> authorizedNotes,
    List<String> existingTags = const [],
    int limit = 5,
  }) {
    if (limit < 1 || limit > 10) return const [];
    final text = '$title\n$body';
    if (text.trim().isEmpty || text.length > 20000) return const [];
    final corpus = <String>[];
    for (final note in authorizedNotes) {
      if (note.isDeleted || note.archived || note.isVisual) continue;
      if (corpus.length >= 5000) return const [];
      final candidate = '${note.title}\n${note.body}';
      if (candidate.length <= 20000) corpus.add(candidate);
    }
    if (corpus.isEmpty) return const [];
    try {
      final existing = existingTags.map((t) => t.toLowerCase()).toSet();
      final ranked = LocalTfidfReference.keywords(
        document: text,
        visibleCorpus: corpus,
        stopwords: _stopwords,
        limit: 30,
      );
      return List.unmodifiable([
        for (final item in ranked)
          if (_tagTerm.hasMatch(item.term) &&
              !existing.contains(item.term) &&
              !_stopwords.contains(item.term))
            item.term,
      ].take(limit));
    } on OnDeviceMathError {
      return const [];
    }
  }
}
