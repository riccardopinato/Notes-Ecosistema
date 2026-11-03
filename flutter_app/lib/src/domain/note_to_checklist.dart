import 'note.dart';
import 'planner.dart';
import 'structured_intelligence.dart';

/// CAP-0093: deterministic, local-only projection of explicit note list rows.
/// This does not modify its source, call AI, or persist anything.
abstract final class NoteToChecklist {
  static const maxItems = StructuredIntelligencePolicy.maxCommands;

  static List<String> candidates(Note note) {
    if (note.isDeleted || note.isTask || note.isVisual) return const [];
    final analysis =
        StructuredIntelligencePolicy.deterministic(body: note.body);
    final seen = <String>{};
    final items = <String>[];
    for (final command in analysis.commands) {
      if (command.kind != StructuredCommandKind.createTask &&
          command.kind != StructuredCommandKind.checklistItem) {
        continue;
      }
      final title = command.title?.trim() ?? '';
      // Completed markdown checkboxes must not become new pending tasks.
      if (title.isEmpty || RegExp(r'^\[[xX]\]\s').hasMatch(title)) continue;
      if (seen.add(title.toLowerCase())) items.add(title);
      if (items.length >= maxItems) break;
    }
    return List<String>.unmodifiable(items);
  }

  /// Build ONE canonical Task with selected subtasks; caller commits it only
  /// after an explicit preview/selection dialog. No duplicate task store.
  static Note buildTask({
    required Note source,
    required List<String> selected,
    required String taskId,
    required int nowMilliseconds,
  }) {
    if (taskId.trim().isEmpty || taskId.length > 128 ||
        nowMilliseconds <= 0 || source.id.trim().isEmpty) {
      throw const FormatException('Identità attività non valida.');
    }
    final allowed = candidates(source).toSet();
    if (selected.isEmpty || selected.length > maxItems ||
        selected.any((item) => !allowed.contains(item)) ||
        selected.toSet().length != selected.length) {
      throw const FormatException('Selezione checklist non valida.');
    }
    final sourceTitle = source.title.trim();
    final label = sourceTitle.isEmpty ? 'Checklist dalla nota' :
        'Checklist · $sourceTitle';
    final title = label.length > 240 ? label.substring(0, 240) : label;
    final details = TaskDetails.empty().copyWith(
      linkedNoteId: source.id,
      subtasks: [
        for (var i = 0; i < selected.length; i++)
          TaskSubtask(
            id: '$taskId:$i',
            title: selected[i],
            completed: false,
          ),
      ],
    );

    return Note(
      id: taskId,
      title: title,
      body: '',
      favorite: false,
      createdAt: nowMilliseconds,
      updatedAt: nowMilliseconds,
      pinned: false,
      archived: false,
      tags: const [],
      taskJson: details.encode(),
    );
  }
}
