import 'editing.dart';
import 'note.dart';
import 'project_workspace.dart';

/// Explicit dependency mutations via canonical task tags; no new task store.
abstract final class ProjectDependencyActions {
  static const maxTargets = 8;

  static List<ProjectWorkItem> eligibleTargets(
      Note source, Iterable<ProjectWorkItem> scopedItems) {
    final grouped = <String, List<ProjectWorkItem>>{};
    for (final item in scopedItems) {
      if (item.kind != ProjectWorkItemKind.task ||
          item.note.isDeleted ||
          item.note.archived) {
        continue;
      }
      grouped.putIfAbsent(item.note.id.toLowerCase(), () => []).add(item);
    }
    final results = <ProjectWorkItem>[];
    for (final values in grouped.values) {
      if (values.length != 1) continue;
      final item = values.single;
      if (!item.completed &&
          item.note.id.toLowerCase() != source.id.toLowerCase() &&
          _validTargetId(item.note.id)) {
        results.add(item);
      }
    }
    results.sort((a, b) => a.title.compareTo(b.title));
    return List.unmodifiable(results);
  }

  static List<String> existingVisibleTargets(
      Note source, List<ProjectWorkItem> available) {
    final eligible =
        available.map((item) => item.note.id.toLowerCase()).toSet();
    return List.unmodifiable(source.tags
        .where((tag) => tag.startsWith('dep_'))
        .map((tag) => tag.substring(4).toLowerCase())
        .where(eligible.contains)
        .toSet());
  }

  static Note update({
    required Note source,
    required Iterable<ProjectWorkItem> scopedItems,
    required Iterable<String> selectedTargetIds,
    required int nowMilliseconds,
  }) {
    if (!source.isTask ||
        source.isDeleted ||
        source.archived ||
        source.taskCompleted ||
        nowMilliseconds <= 0) {
      throw const FormatException('DEPENDENCY_SOURCE_NOT_EDITABLE');
    }
    final grouped = <String, List<ProjectWorkItem>>{};
    for (final item in scopedItems) {
      if (item.kind != ProjectWorkItemKind.task ||
          item.note.isDeleted ||
          item.note.archived) {
        continue;
      }
      grouped.putIfAbsent(item.note.id.toLowerCase(), () => []).add(item);
    }
    final self = source.id.toLowerCase();
    if (grouped[self]?.length != 1 ||
        !sameTaskRevision(source, grouped[self]!.single.note)) {
      throw const FormatException('DEPENDENCY_STALE_SOURCE');
    }
    final selected = selectedTargetIds.toList(growable: false);
    final ids = selected.map((id) => id.toLowerCase()).toSet();
    if (selected.length > maxTargets || selected.length != ids.length) {
      throw const FormatException('DEPENDENCY_TOO_MANY_OR_DUPLICATE');
    }
    for (final id in ids) {
      if (id == self ||
          !_validTargetId(id) ||
          grouped[id]?.length != 1 ||
          grouped[id]!.single.completed) {
        throw const FormatException('DEPENDENCY_TARGET_OUT_OF_SCOPE');
      }
    }
    // Preserve invisible or completed legacy links, never discard them
    // merely because a permission-scoped picker cannot display them.
    final eligible = eligibleTargets(source, scopedItems)
        .map((item) => item.note.id.toLowerCase())
        .toSet();
    final preserved = source.tags.where((tag) {
      if (!tag.startsWith('dep_')) return false;
      return !eligible.contains(tag.substring(4).toLowerCase());
    }).toList(growable: false);

    final graph = <String, Set<String>>{};
    for (final entry in grouped.entries) {
      if (entry.value.length != 1 || entry.value.single.completed) continue;
      graph[entry.key] = entry.value.single.note.tags
          .where((tag) => tag.startsWith('dep_'))
          .map((tag) => tag.substring(4).toLowerCase())
          .where((id) =>
              grouped[id]?.length == 1 && !grouped[id]!.single.completed)
          .toSet();
    }
    graph[self] = {
      ...ids,
      ...preserved
          .map((tag) => tag.substring(4).toLowerCase())
          .where(graph.containsKey),
    };
    for (final target in graph[self]!) {
      if (_reaches(graph, target, self)) {
        throw const FormatException('DEPENDENCY_CYCLE');
      }
    }
    final nextTags = NoteTags.normalize([
      ...source.tags.where((tag) => !tag.startsWith('dep_')),
      ...preserved,
      ...ids.map((id) => 'dep_$id'),
    ]);
    if (_sameTags(source.tags, nextTags)) return source;
    return source.copyWith(tags: nextTags, updatedAt: nowMilliseconds);
  }

  static bool _reaches(
      Map<String, Set<String>> graph, String from, String sought) {
    final visited = <String>{};
    final stack = <String>[from];
    while (stack.isNotEmpty && visited.length <= 5000) {
      final current = stack.removeLast();
      if (current == sought) return true;
      if (!visited.add(current)) continue;
      stack.addAll(graph[current] ?? const <String>{});
    }
    return false;
  }

  static bool _validTargetId(String id) =>
      id.isNotEmpty && id.length <= 36 && RegExp(r'^[a-z0-9_-]+$').hasMatch(id);

  static bool _sameTags(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  static bool sameTaskRevision(Note expected, Note current) =>
      expected.id == current.id &&
      current.isTask &&
      !current.isDeleted &&
      !current.archived &&
      expected.updatedAt == current.updatedAt &&
      expected.createdAt == current.createdAt &&
      expected.title == current.title &&
      expected.body == current.body &&
      expected.collectionId == current.collectionId &&
      expected.taskJson == current.taskJson &&
      _sameTags(expected.tags, current.tags);
}
