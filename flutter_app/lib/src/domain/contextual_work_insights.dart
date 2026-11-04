import 'note.dart';
import 'project_workspace.dart';

/// Read-only projections from the canonical project links and task records.
enum NextActionKind { missingNextAction, unplannedPriority, excessiveWip }

class NextActionInsight {
  const NextActionInsight(this.kind, this.sourceId, this.reasonCode);
  final NextActionKind kind;
  final String? sourceId;
  final String reasonCode;
}

abstract final class NextActionInsights {
  static List<NextActionInsight> forProject(
    List<ProjectWorkItem> items,
  ) {
    // Filter lifecycle before diagnosing missing work or WIP.
    final active = items
        .where((item) => !item.note.isDeleted && !item.note.archived)
        .toList(growable: false);
    if (active.isEmpty) return const [];
    final pending = active
        .where(
            (item) => item.kind == ProjectWorkItemKind.task && !item.completed)
        .toList(growable: false);
    if (pending.isEmpty) {
      return const [
        NextActionInsight(
          NextActionKind.missingNextAction,
          null,
          'PROJECT_WITHOUT_OPEN_TASK',
        ),
      ];
    }
    final suggestions = <NextActionInsight>[];
    final doing = pending.where((item) => item.stage == 'DOING').length;
    if (doing > 3) {
      suggestions.add(
        const NextActionInsight(
          NextActionKind.excessiveWip,
          null,
          'MORE_THAN_THREE_IN_PROGRESS',
        ),
      );
    }
    for (final item in pending) {
      if (item.priority >= 2 && item.plannedDate == null && item.due == null) {
        suggestions.add(
          NextActionInsight(
            NextActionKind.unplannedPriority,
            item.note.id,
            'HIGH_PRIORITY_WITHOUT_DATE',
          ),
        );
        break;
      }
    }
    return List.unmodifiable(suggestions.take(2));
  }
}

enum InboxReviewKind { checklist, explicitTags }

class InboxReviewSuggestion {
  const InboxReviewSuggestion(this.note, this.kind, this.reasonCode);
  final Note note;
  final InboxReviewKind kind;
  final String reasonCode;
}

abstract final class SmartInboxReview {
  static List<InboxReviewSuggestion> suggest(
    Iterable<Note> notes, {
    int limit = 3,
    bool Function(InboxReviewSuggestion suggestion)? include,
  }) {
    if (limit < 0 || limit > 20) {
      throw const FormatException('INVALID_REVIEW_LIMIT');
    }
    if (limit == 0) return const [];
    final results = <InboxReviewSuggestion>[];
    final ordered = notes
        .where((note) =>
            !note.isDeleted &&
            !note.archived &&
            !note.isTask &&
            !note.isVisual &&
            note.body.trim().isNotEmpty)
        .toList(growable: false)
      ..sort((a, b) {
        final change = b.updatedAt.compareTo(a.updatedAt);
        return change != 0 ? change : a.id.compareTo(b.id);
      });
    for (final note in ordered) {
      InboxReviewSuggestion? suggestion;
      if (RegExp(r'^\s*[-*] \[ \]', multiLine: true).hasMatch(note.body)) {
        suggestion = InboxReviewSuggestion(
          note,
          InboxReviewKind.checklist,
          'EXPLICIT_UNCHECKED_LIST',
        );
      } else if (note.tags.isEmpty &&
          RegExp(r'(^|\s)#[\p{L}\p{N}_]{2,32}(?![\p{L}\p{N}_])',
                  multiLine: true, unicode: true)
              .hasMatch(note.body)) {
        suggestion = InboxReviewSuggestion(
          note,
          InboxReviewKind.explicitTags,
          'EXPLICIT_HASHTAGS_NOT_APPLIED',
        );
      }
      if (suggestion != null && (include == null || include(suggestion))) {
        results.add(suggestion);
        if (results.length >= limit) break;
      }
    }
    return List.unmodifiable(results);
  }
}
