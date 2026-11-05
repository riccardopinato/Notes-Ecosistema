import 'contextual_work_insights.dart';
import 'editing.dart';
import 'note.dart';

/// Deterministic, read-only review of source-authored candidates.
class SmartInboxSourcePreview {
  const SmartInboxSourcePreview(
      this.source, this.reasonCode, this.candidates, this.sourceExcerpt);
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
        if ((suggestion.kind == InboxReviewKind.explicitTags &&
                existing.contains(key)) ||
            !seen.add(key)) {
          continue;
        }
        candidates.add(candidate);
        if (excerpt.isEmpty) excerpt = line.trim();
        if (candidates.length >= 8) break;
      }
      if (candidates.length >= 8) break;
    }
    if (candidates.isEmpty) return null;
    if (excerpt.length > 180) excerpt = '${excerpt.substring(0, 180)}…';
    return SmartInboxSourcePreview(
        source, suggestion.reasonCode, List.unmodifiable(candidates), excerpt);
  }

  /// Only source-authored, explicitly selected tags may enter an editor draft.
  /// This method never writes the canonical note.
  List<String> selectedTagDraft(Iterable<String> selected) {
    final selection = selected.toList(growable: false);
    final allow = candidates.toSet();
    if (selection.isEmpty ||
        selection.length > candidates.length ||
        selection.any((tag) => !allow.contains(tag))) {
      throw const FormatException('INVALID_SMART_INBOX_SELECTION');
    }
    return NoteTags.normalize({...source.tags, ...selection});
  }

  /// Compare the authoritative revision before every Smart Inbox Save.
  static bool sameCanonicalRevision(Note expected, Note actual) =>
      expected.id == actual.id &&
      !actual.isDeleted &&
      !actual.archived &&
      !actual.isTask &&
      !actual.isVisual &&
      expected.updatedAt == actual.updatedAt &&
      expected.createdAt == actual.createdAt &&
      expected.title == actual.title &&
      expected.body == actual.body &&
      expected.collectionId == actual.collectionId &&
      expected.favorite == actual.favorite &&
      expected.pinned == actual.pinned &&
      _sameTags(expected.tags, actual.tags) &&
      expected.deletedAt == actual.deletedAt &&
      expected.taskJson == actual.taskJson &&
      expected.sketchJson == actual.sketchJson;

  /// Ignore timestamps only when identifying unchanged submitted edit fields
  /// after a successful canonical write and a failed optional sidecar.
  static bool sameEditorPayload(Note saved, Note proposed) =>
      saved.id == proposed.id &&
      saved.title == proposed.title &&
      saved.body == proposed.body &&
      saved.collectionId == proposed.collectionId &&
      _sameTags(saved.tags, proposed.tags);

  static bool _sameTags(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
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
