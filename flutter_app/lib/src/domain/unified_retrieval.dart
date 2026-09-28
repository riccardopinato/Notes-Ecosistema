import 'dart:math' as math;

import 'note.dart';

enum RetrievalKind {
  note,
  task,
  ocr,
  derivative,
  study,
  pdfAnnotation,
  research,
  metadata,
  relation,
}

class RetrievalDocument {
  const RetrievalDocument({
    required this.id,
    required this.noteId,
    required this.kind,
    required this.title,
    required this.text,
    this.tags = const [],
    this.updatedAt = 0,
  });

  final String id;
  final String noteId;
  final RetrievalKind kind;
  final String title;
  final String text;
  final List<String> tags;
  final int updatedAt;
}

class RetrievalHit {
  const RetrievalHit({
    required this.document,
    required this.score,
    required this.excerpt,
  });

  final RetrievalDocument document;
  final double score;
  final String excerpt;
}

abstract final class UnifiedRetrieval {
  static List<RetrievalDocument> noteDocuments(Iterable<Note> notes) => [
        for (final note in notes)
          if (!note.isDeleted && !note.archived && !note.isVisual)
            RetrievalDocument(
              id: 'note:${note.id}',
              noteId: note.id,
              kind: note.isTask ? RetrievalKind.task : RetrievalKind.note,
              title: note.title,
              text: note.body,
              tags: note.tags,
              updatedAt: note.updatedAt,
            ),
      ];

  static bool matchesNote(Note note, String query) {
    final needle = normalize(query);
    if (needle.isEmpty) return true;
    return scoreText(
          query: needle,
          title: note.title,
          text: note.isVisual ? '' : note.body,
          tags: note.tags,
        ) >
        0;
  }

  static int scoreText({
    required String query,
    required String title,
    String text = '',
    List<String> tags = const [],
  }) {
    final needle = normalize(query);
    if (needle.isEmpty) return 1;

    final normalizedTitle = normalize(title);
    final normalizedText = normalize(text);
    final normalizedTags = tags.map(normalize).toList(growable: false);
    if (normalizedTitle == needle) return 1000;
    if (normalizedTitle.startsWith(needle)) return 800;

    var score = 0;
    if (normalizedTitle.contains(needle)) score += 500;
    if (normalizedText.contains(needle)) score += 260;
    if (normalizedTags.any((tag) => tag == needle)) score += 420;
    if (normalizedTags.any((tag) => tag.contains(needle))) score += 220;

    final terms = tokenize(needle);
    if (terms.isEmpty) return score;
    for (final term in terms) {
      if (normalizedTitle.split(' ').any((token) => token.startsWith(term))) {
        score += 90;
      }
      if (normalizedText.contains(term)) score += 35;
      if (normalizedTags.any((tag) => tag.contains(term))) score += 55;
    }
    return score;
  }

  static List<RetrievalHit> search(
    String query,
    Iterable<RetrievalDocument> documents, {
    int limit = 30,
  }) {
    final needle = normalize(query);
    if (needle.isEmpty) return const [];
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = <RetrievalHit>[];
    for (final document in documents) {
      final base = scoreText(
        query: needle,
        title: document.title,
        text: document.text,
        tags: document.tags,
      );
      if (base <= 0) continue;
      final ageDays = document.updatedAt <= 0
          ? 3650
          : math.max(0, (now - document.updatedAt) ~/ 86400000);
      final recency = math.max(0, 20 - ageDays.clamp(0, 20));
      final kindBoost = switch (document.kind) {
        RetrievalKind.note => 16,
        RetrievalKind.task => 12,
        RetrievalKind.ocr => 10,
        RetrievalKind.study => 8,
        RetrievalKind.pdfAnnotation => 7,
        RetrievalKind.research => 6,
        RetrievalKind.metadata => 6,
        RetrievalKind.relation => 6,
        RetrievalKind.derivative => 5,
      };
      rows.add(
        RetrievalHit(
          document: document,
          score: base.toDouble() + recency + kindBoost,
          excerpt: excerpt(document.text, needle),
        ),
      );
    }
    rows.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      final updated = b.document.updatedAt.compareTo(a.document.updatedAt);
      if (updated != 0) return updated;
      return a.document.id.compareTo(b.document.id);
    });

    final seen = <String>{};
    final result = <RetrievalHit>[];
    for (final hit in rows) {
      if (!seen.add(hit.document.noteId)) continue;
      result.add(hit);
      if (result.length >= limit.clamp(1, 100)) break;
    }
    return result;
  }

  static String normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static List<String> tokenize(String value) => normalize(value)
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .split(' ')
      .where((term) => term.length >= 2)
      .toList(growable: false);

  static String excerpt(String text, String query) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) return 'Nessun estratto.';
    final normalized = compact.toLowerCase();
    var index = normalized.indexOf(query.toLowerCase());
    if (index < 0) {
      for (final term in tokenize(query)) {
        index = normalized.indexOf(term);
        if (index >= 0) break;
      }
    }
    final start = index < 0 ? 0 : math.max(0, index - 90);
    final end = math.min(compact.length, start + 260);
    return '${start > 0 ? '…' : ''}${compact.substring(start, end)}'
        '${end < compact.length ? '…' : ''}';
  }
}
