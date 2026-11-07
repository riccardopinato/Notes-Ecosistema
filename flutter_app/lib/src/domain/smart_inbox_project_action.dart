import 'note.dart';
import 'project_workspace.dart';
import 'smart_inbox_source_preview.dart';

/// CAP-0148: bounded, explicit project-link action over the existing
/// canonical ProjectWorkspaceStore. This class creates no separate storage.
abstract final class SmartInboxProjectAction {
  /// Never propose an archived/deleted/shared project for a private-source
  /// Smart Inbox action. Permission revalidation remains mandatory at commit.
  static List<ProjectWorkspace> privateTargets(
    Iterable<ProjectWorkspace> projects,
  ) {
    final selected = <ProjectWorkspace>[];
    final seen = <String>{};
    for (final project in projects) {
      if (!project.isActive ||
          project.sharedSpaceId != null ||
          !seen.add(project.id)) {
        continue;
      }
      selected.add(project);
      if (selected.length >= 40) break;
    }
    return List.unmodifiable(selected);
  }

  static ProjectWorkspace validateTarget(
    String projectId,
    Iterable<ProjectWorkspace> allowed,
  ) {
    if (projectId.trim().isEmpty) {
      throw const FormatException('SMART_INBOX_PROJECT_NOT_SELECTED');
    }
    final matches = privateTargets(allowed)
        .where((project) => project.id == projectId)
        .toList(growable: false);
    if (matches.length != 1) {
      throw const FormatException('SMART_INBOX_PROJECT_NO_LONGER_AVAILABLE');
    }
    return matches.single;
  }

  /// Source in the current user's private Note list must be unchanged.
  static bool validSource(Note original, Iterable<Note> visible) {
    final matches = visible
        .where((note) => note.id == original.id)
        .toList(growable: false);
    return matches.length == 1 &&
        SmartInboxSourcePreview.sameCanonicalRevision(
          original,
          matches.single,
        );
  }

  static bool canUndo(
    ProjectItemLink recorded,
    ProjectItemLink current,
  ) =>
      recorded.projectId == current.projectId &&
      recorded.noteId == current.noteId &&
      recorded.addedAt == current.addedAt &&
      recorded.updatedAt == current.updatedAt &&
      recorded.position == current.position;
}
