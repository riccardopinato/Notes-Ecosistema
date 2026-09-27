import 'note.dart';
import 'planner.dart';
import 'reference_lifecycle.dart';

const _projectUnset = Object();

enum ProjectWorkViewType { list, board, table, calendar, timeline }

extension ProjectWorkViewTypeUi on ProjectWorkViewType {
  String get label => switch (this) {
        ProjectWorkViewType.list => 'Lista',
        ProjectWorkViewType.board => 'Board',
        ProjectWorkViewType.table => 'Tabella',
        ProjectWorkViewType.calendar => 'Calendario',
        ProjectWorkViewType.timeline => 'Timeline',
      };

  static ProjectWorkViewType parse(String raw) {
    final normalized = raw.trim().toLowerCase();
    return ProjectWorkViewType.values.firstWhere(
      (value) => value.name.toLowerCase() == normalized,
      orElse: () => throw FormatException('Vista progetto non valida: $raw'),
    );
  }
}

class ProjectWorkspace {
  const ProjectWorkspace({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
    this.sharedSpaceId,
    this.archivedAt,
    this.deletedAt,
    this.preferredView = ProjectWorkViewType.list,
  });

  final String id;
  final String name;
  final String description;
  final String? sharedSpaceId;
  final int createdAt;
  final int updatedAt;
  final int? archivedAt;
  final int? deletedAt;
  final ProjectWorkViewType preferredView;

  bool get isArchived => archivedAt != null;
  bool get isDeleted => deletedAt != null;
  bool get isActive => !isArchived && !isDeleted;

  ProjectWorkspace copyWith({
    String? name,
    String? description,
    Object? sharedSpaceId = _projectUnset,
    int? updatedAt,
    Object? archivedAt = _projectUnset,
    Object? deletedAt = _projectUnset,
    ProjectWorkViewType? preferredView,
  }) =>
      ProjectWorkspace(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        sharedSpaceId: identical(sharedSpaceId, _projectUnset)
            ? this.sharedSpaceId
            : sharedSpaceId as String?,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        archivedAt: identical(archivedAt, _projectUnset)
            ? this.archivedAt
            : archivedAt as int?,
        deletedAt: identical(deletedAt, _projectUnset)
            ? this.deletedAt
            : deletedAt as int?,
        preferredView: preferredView ?? this.preferredView,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'sharedSpaceId': sharedSpaceId,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'archivedAt': archivedAt,
        'deletedAt': deletedAt,
        'preferredView': preferredView.name,
      };

  factory ProjectWorkspace.fromMap(Map<String, Object?> row) {
    final project = ProjectWorkspace(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      description: row['description']?.toString() ?? '',
      sharedSpaceId: row['sharedSpaceId']?.toString(),
      createdAt: (row['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
      archivedAt: (row['archivedAt'] as num?)?.toInt(),
      deletedAt: (row['deletedAt'] as num?)?.toInt(),
      preferredView: ProjectWorkViewTypeUi.parse(
        row['preferredView']?.toString() ?? 'list',
      ),
    );
    ProjectWorkspaceRules.validateProject(project);
    return project;
  }
}

class ProjectItemLink {
  const ProjectItemLink({
    required this.projectId,
    required this.noteId,
    required this.position,
    required this.addedAt,
    required this.updatedAt,
  });

  final String projectId;
  final String noteId;
  final int position;
  final int addedAt;
  final int updatedAt;

  Map<String, Object?> toMap() => {
        'projectId': projectId,
        'noteId': noteId,
        'position': position,
        'addedAt': addedAt,
        'updatedAt': updatedAt,
      };

  factory ProjectItemLink.fromMap(Map<String, Object?> row) {
    final link = ProjectItemLink(
      projectId: row['projectId']?.toString() ?? '',
      noteId: row['noteId']?.toString() ?? '',
      position: (row['position'] as num?)?.toInt() ?? 0,
      addedAt: (row['addedAt'] as num?)?.toInt() ?? 0,
      updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
    );
    ProjectWorkspaceRules.validateLink(link);
    return link;
  }
}

class ProjectWorkspaceSnapshot {
  const ProjectWorkspaceSnapshot({
    required this.projects,
    required this.links,
  });

  final List<ProjectWorkspace> projects;
  final List<ProjectItemLink> links;
}

enum ProjectWorkItemKind { note, task, sketch, whiteboard }

class ProjectWorkItem {
  const ProjectWorkItem({
    required this.note,
    required this.kind,
    required this.position,
    required this.stage,
    required this.completed,
    required this.priority,
    required this.due,
    required this.plannedDate,
    required this.plannedTime,
    required this.plannedMinutes,
  });

  final Note note;
  final ProjectWorkItemKind kind;
  final int position;
  final String stage;
  final bool completed;
  final int priority;
  final String? due;
  final String? plannedDate;
  final String? plannedTime;
  final int plannedMinutes;

  String get title =>
      note.title.trim().isEmpty ? 'Senza titolo' : note.title.trim();
  String? get effectiveDate => plannedDate ?? due;

  factory ProjectWorkItem.from(Note note, ProjectItemLink link) {
    final task = TaskDetails.tryDecode(note.taskJson);
    final completed = task?.completed ?? false;
    var stage = task?.stage.toUpperCase() ?? 'REFERENCE';
    if (!const {'TODO', 'DOING', 'DONE'}.contains(stage)) stage = 'TODO';
    if (completed) stage = 'DONE';

    return ProjectWorkItem(
      note: note,
      kind: note.isTask
          ? ProjectWorkItemKind.task
          : note.visualKind == VisualDocumentKind.sketch
              ? ProjectWorkItemKind.sketch
              : note.visualKind == VisualDocumentKind.whiteboard
                  ? ProjectWorkItemKind.whiteboard
                  : ProjectWorkItemKind.note,
      position: link.position,
      stage: note.isTask ? stage : 'REFERENCE',
      completed: completed,
      priority: task?.priority ?? 0,
      due: task?.due,
      plannedDate: task?.plannedDate,
      plannedTime: task?.plannedTime,
      plannedMinutes: task?.plannedMinutes ?? 30,
    );
  }
}

abstract final class ProjectWorkspaceRules {
  static const maxProjects = 200;
  static const maxItemsPerProject = 5000;
  static const maxNameLength = 120;
  static const maxDescriptionLength = 4000;

  static void validateProject(ProjectWorkspace project) {
    final name = project.name.trim();
    if (project.id.trim().isEmpty || project.id.length > 200) {
      throw const FormatException('ID progetto non valido.');
    }
    if (name.isEmpty || name.length > maxNameLength) {
      throw const FormatException('Nome progetto non valido.');
    }
    if (project.description.length > maxDescriptionLength) {
      throw const FormatException('Descrizione progetto troppo lunga.');
    }
    if (project.sharedSpaceId?.trim().isEmpty == true) {
      throw const FormatException('Shared Space progetto non valido.');
    }
    if (project.createdAt < 0 ||
        project.updatedAt < 0 ||
        (project.archivedAt ?? 0) < 0 ||
        (project.deletedAt ?? 0) < 0) {
      throw const FormatException('Data progetto non valida.');
    }
    if (project.deletedAt != null && project.deletedAt! < project.createdAt) {
      throw const FormatException('Lifecycle progetto non valido.');
    }
  }

  static void validateLink(ProjectItemLink link) {
    if (link.projectId.trim().isEmpty || link.noteId.trim().isEmpty) {
      throw const FormatException('Collegamento progetto non valido.');
    }
    if (link.position < 0 || link.addedAt < 0 || link.updatedAt < 0) {
      throw const FormatException('Posizione o data collegamento non valida.');
    }
  }
}

abstract final class ProjectWorkViews {
  static const boardLanes = ['TODO', 'DOING', 'DONE', 'REFERENCE'];

  static List<ProjectWorkItem> project({
    required List<Note> notes,
    required List<ProjectItemLink> links,
    String query = '',
    bool showCompleted = true,
  }) {
    final needle = query.trim().toLowerCase();
    final result = <ProjectWorkItem>[];

    for (final link in links) {
      final resolution = ReferenceLifecycle.noteById(
        id: link.noteId,
        notes: notes,
        kind: ReferenceKind.projectLink,
      );
      if (!resolution.canOpen) continue;
      final note = resolution.value!;
      final item = ProjectWorkItem.from(note, link);
      if (!showCompleted && item.completed) continue;
      if (needle.isNotEmpty) {
        final searchable = [
          note.title,
          if (!note.isVisual) note.body,
          ...note.tags,
        ].join('\n').toLowerCase();
        if (!searchable.contains(needle)) continue;
      }
      result.add(item);
    }

    result.sort(_compare);
    return result;
  }

  static Map<String, List<ProjectWorkItem>> board(
    List<ProjectWorkItem> items,
  ) {
    final lanes = {
      for (final lane in boardLanes) lane: <ProjectWorkItem>[],
    };
    for (final item in items) {
      (lanes[item.stage] ?? lanes['REFERENCE']!).add(item);
    }
    for (final lane in lanes.values) {
      lane.sort(_compare);
    }
    return lanes;
  }

  static Map<String, List<ProjectWorkItem>> calendar(
    List<ProjectWorkItem> items,
  ) {
    final groups = <String, List<ProjectWorkItem>>{};
    for (final item in items) {
      final key = item.effectiveDate ?? 'UNDATED';
      groups.putIfAbsent(key, () => <ProjectWorkItem>[]).add(item);
    }
    for (final group in groups.values) {
      group.sort(_compare);
    }
    return groups;
  }

  static List<ProjectWorkItem> timeline(List<ProjectWorkItem> items) {
    final result = [...items];
    result.sort((a, b) {
      final aDate = a.effectiveDate;
      final bDate = b.effectiveDate;
      if (aDate == null && bDate != null) return 1;
      if (aDate != null && bDate == null) return -1;
      if (aDate != null && bDate != null) {
        final byDate = aDate.compareTo(bDate);
        if (byDate != 0) return byDate;
      }
      final aTime = a.plannedTime;
      final bTime = b.plannedTime;
      if (aTime == null && bTime != null) return 1;
      if (aTime != null && bTime == null) return -1;
      if (aTime != null && bTime != null) {
        final byTime = aTime.compareTo(bTime);
        if (byTime != 0) return byTime;
      }
      return _compare(a, b);
    });
    return result;
  }

  static int _compare(ProjectWorkItem a, ProjectWorkItem b) {
    final byPosition = a.position.compareTo(b.position);
    if (byPosition != 0) return byPosition;
    final byPriority = b.priority.compareTo(a.priority);
    if (byPriority != 0) return byPriority;
    final byUpdate = b.note.updatedAt.compareTo(a.note.updatedAt);
    if (byUpdate != 0) return byUpdate;
    return a.note.id.compareTo(b.note.id);
  }
}
