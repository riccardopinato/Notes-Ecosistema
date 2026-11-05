import 'contextual_work_insights.dart';
import 'note.dart';
import 'note_to_checklist.dart';
import 'planner.dart';
import 'smart_inbox_source_preview.dart';

/// Local, bounded validation for an explicitly approved Smart Inbox action.
/// The caller owns the canonical writer and must revalidate the live source.
abstract final class SmartInboxChecklistAction {
  static List<String> selectedItems(Note source, Iterable<String> selection) {
    final preview = SmartInboxSourcePreview.inspect(InboxReviewSuggestion(
        source, InboxReviewKind.checklist, 'EXPLICIT_UNCHECKED_LIST'));
    if (preview == null) {
      throw const FormatException('SMART_INBOX_SOURCE_UNAVAILABLE');
    }
    final selected = selection.toList(growable: false);
    final allowed = preview.candidates.toSet();
    final canonical = NoteToChecklist.candidates(source).toSet();
    if (selected.isEmpty ||
        selected.length > 8 ||
        selected.toSet().length != selected.length ||
        selected.any(
            (item) => !allowed.contains(item) || !canonical.contains(item))) {
      throw const FormatException('SMART_INBOX_SELECTION_NOT_IN_SOURCE');
    }
    return List.unmodifiable(selected);
  }

  /// Repeating the same exact selection from the same source is blocked,
  /// including when the previously derived task has been completed.
  static bool alreadyCreated(
      Iterable<Note> canonicalNotes, String sourceId, List<String> selected) {
    final signature = _signature(selected);
    for (final note in canonicalNotes) {
      if (note.isDeleted || !note.isTask) continue;
      final details = TaskDetails.tryDecode(note.taskJson);
      if (details?.linkedNoteId != sourceId) continue;
      if (_signature(details!.subtasks.map((item) => item.title)) ==
          signature) {
        return true;
      }
    }
    return false;
  }

  static bool canUndo(Note committed, Note current) {
    if (!committed.isTask ||
        !current.isTask ||
        current.isDeleted ||
        current.archived) {
      return false;
    }
    if (committed.id != current.id ||
        committed.updatedAt != current.updatedAt ||
        committed.createdAt != current.createdAt ||
        committed.title != current.title ||
        committed.body != current.body ||
        committed.collectionId != current.collectionId ||
        committed.taskJson != current.taskJson ||
        committed.tags.length != current.tags.length) {
      return false;
    }
    for (var index = 0; index < committed.tags.length; index++) {
      if (committed.tags[index] != current.tags[index]) return false;
    }
    return true;
  }

  static String _signature(Iterable<String> values) {
    final items = values.map((value) => value.trim().toLowerCase()).toList()
      ..sort();
    return items.join('\u0000');
  }
}
