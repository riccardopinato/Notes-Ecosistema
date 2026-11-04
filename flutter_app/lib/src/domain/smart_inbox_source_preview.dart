import 'contextual_work_insights.dart';
import 'note.dart';

/// Deterministic, read-only review of source-authored candidates.
class SmartInboxSourcePreview {
  const SmartInboxSourcePreview(this.source, this.reasonCode, this.candidates,
      this.sourceExcerpt);
  final Note source;
  final String reasonCode;
  final List<String> candidates;
  final String sourceExcerpt;

  static final RegExp _checkbox = RegExp(r'^\s*[-*] \[ \]\s+(.+?)\s*$');
  static final RegExp _tag = RegExp(
    r'(^|\s)#([\p{L}\p{M}\p{N}_]{2,32})(?![\p{L}\p{M}\p{N}_])',
    unicode: true,
  );

  static SmartInboxSourcePreview? inspect(InboxReviewSuggestion suggestion) {
    final source = suggestion.note;
    if (source.id.trim().isEmpty ||
        source.isDeleted ||
        source.archived ||
        source.isTask ||
        source.isVisual) {
      return null;
    }
    final candidates = <String>[];
    final seen = <String>{};
    final existing = source.tags.map((tag) => tag.toLowerCase()).toSet();
    var excerpt = '';
    for (final line in source.body.split('\n')) {
      final values = suggestion.kind == InboxReviewKind.checklist
          ? [_checkbox.firstMatch(line)?.group(1)]
          : _tag.allMatches(line).map((match) => match.group(2)).toList();
      for (final value in values) {
        final candidate = value?.trim() ?? '';
        if (candidate.isEmpty || candidate.length > 200) continue;
        final key = candidate.toLowerCase();
        if (existing.contains(key) || !seen.add(key)) continue;
        candidates.add(candidate);
        if (excerpt.isEmpty) excerpt = line.trim();
        if (candidates.length >= 8) break;
      }
      if (candidates.length >= 8) break;
    }
    if (candidates.isEmpty) return null;
    if (excerpt.length > 180) excerpt = excerpt.substring(0, 180) + '…';
    return SmartInboxSourcePreview(
        source, suggestion.reasonCode, List.unmodifiable(candidates), excerpt);
  }

  /// Reject absent, duplicate, stale, hidden or changed note snapshots.
  /// The canonical editor remains responsible for final save-time ACL checks.
  Note? current(Iterable<Note> visibleNotes) {
    Note? match;
    for (final note in visibleNotes) {
      if (note.id != source.id) continue;
      if (match != null) return null;
      match = note;
    }
    if (match == null ||
        match.isDeleted ||
        match.archived ||
        match.isTask ||
        match.isVisual ||
        match.updatedAt != source.updatedAt ||
        match.title != source.title ||
        match.body != source.body ||
        match.tags.length != source.tags.length) {
      return null;
    }
    for (var index = 0; index < match.tags.length; index++) {
      if (match.tags[index] != source.tags[index]) return null;
    }
    return match;
  }
}
