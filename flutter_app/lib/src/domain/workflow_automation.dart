import 'note.dart';
import 'planner.dart';

enum WorkflowTrigger { itemCreated, itemUpdated, taskCompleted }

enum WorkflowSubject { any, note, task }

enum WorkflowActionKind { addTag, moveToCollection, pin, setPriority }

class WorkflowRule {
  const WorkflowRule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.trigger,
    required this.subject,
    required this.actionKind,
    required this.actionValue,
    required this.createdAt,
    required this.updatedAt,
    this.requiredTag,
    this.titleContains,
  });

  final String id;
  final String name;
  final bool enabled;
  final WorkflowTrigger trigger;
  final WorkflowSubject subject;
  final String? requiredTag;
  final String? titleContains;
  final WorkflowActionKind actionKind;
  final String actionValue;
  final int createdAt;
  final int updatedAt;

  WorkflowRule copyWith({
    String? name,
    bool? enabled,
    WorkflowTrigger? trigger,
    WorkflowSubject? subject,
    Object? requiredTag = _unset,
    Object? titleContains = _unset,
    WorkflowActionKind? actionKind,
    String? actionValue,
    int? updatedAt,
  }) =>
      WorkflowRule(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        trigger: trigger ?? this.trigger,
        subject: subject ?? this.subject,
        requiredTag:
            identical(requiredTag, _unset) ? this.requiredTag : requiredTag as String?,
        titleContains: identical(titleContains, _unset)
            ? this.titleContains
            : titleContains as String?,
        actionKind: actionKind ?? this.actionKind,
        actionValue: actionValue ?? this.actionValue,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'enabled': enabled ? 1 : 0,
        'trigger': trigger.name,
        'subject': subject.name,
        'requiredTag': requiredTag,
        'titleContains': titleContains,
        'actionKind': actionKind.name,
        'actionValue': actionValue,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory WorkflowRule.fromMap(Map<String, Object?> row) => WorkflowRule(
        id: row['id']?.toString() ?? '',
        name: row['name']?.toString() ?? '',
        enabled: (row['enabled'] as num?)?.toInt() == 1,
        trigger: WorkflowTrigger.values.byName(row['trigger']?.toString() ?? ''),
        subject: WorkflowSubject.values.byName(row['subject']?.toString() ?? ''),
        requiredTag: _optional(row['requiredTag']),
        titleContains: _optional(row['titleContains']),
        actionKind:
            WorkflowActionKind.values.byName(row['actionKind']?.toString() ?? ''),
        actionValue: row['actionValue']?.toString() ?? '',
        createdAt: (row['createdAt'] as num?)?.toInt() ?? -1,
        updatedAt: (row['updatedAt'] as num?)?.toInt() ?? -1,
      );
}

class WorkflowRun {
  const WorkflowRun({
    required this.id,
    required this.ruleId,
    required this.noteId,
    required this.trigger,
    required this.actionKind,
    required this.ranAt,
  });

  final String id;
  final String ruleId;
  final String noteId;
  final WorkflowTrigger trigger;
  final WorkflowActionKind actionKind;
  final int ranAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'ruleId': ruleId,
        'noteId': noteId,
        'trigger': trigger.name,
        'actionKind': actionKind.name,
        'ranAt': ranAt,
      };

  factory WorkflowRun.fromMap(Map<String, Object?> row) => WorkflowRun(
        id: row['id']?.toString() ?? '',
        ruleId: row['ruleId']?.toString() ?? '',
        noteId: row['noteId']?.toString() ?? '',
        trigger: WorkflowTrigger.values.byName(row['trigger']?.toString() ?? ''),
        actionKind:
            WorkflowActionKind.values.byName(row['actionKind']?.toString() ?? ''),
        ranAt: (row['ranAt'] as num?)?.toInt() ?? -1,
      );
}

class WorkflowEvaluation {
  const WorkflowEvaluation({
    required this.note,
    required this.trigger,
    required this.appliedRules,
  });

  final Note note;
  final WorkflowTrigger? trigger;
  final List<WorkflowRule> appliedRules;

  bool get changed => appliedRules.isNotEmpty;
}

abstract final class WorkflowAutomationRules {
  static const maxRules = 100;
  static const maxRuns = 500;

  static void validateRule(WorkflowRule rule) {
    if (rule.id.trim().isEmpty ||
        rule.id.length > 200 ||
        rule.name.trim().isEmpty ||
        rule.name.trim().length > 120 ||
        rule.createdAt < 0 ||
        rule.updatedAt < rule.createdAt) {
      throw const FormatException('Regola automazione non valida.');
    }
    final requiredTag = rule.requiredTag?.trim();
    final titleContains = rule.titleContains?.trim();
    if ((requiredTag?.length ?? 0) > 80 || (titleContains?.length ?? 0) > 200) {
      throw const FormatException('Condizione automazione troppo lunga.');
    }

    switch (rule.actionKind) {
      case WorkflowActionKind.addTag:
        if (rule.actionValue.trim().isEmpty || rule.actionValue.trim().length > 80) {
          throw const FormatException('Tag automazione non valido.');
        }
        break;
      case WorkflowActionKind.moveToCollection:
        if (rule.actionValue.trim().isEmpty ||
            rule.actionValue.trim().length > 200) {
          throw const FormatException('Raccolta automazione non valida.');
        }
        break;
      case WorkflowActionKind.pin:
        if (rule.actionValue.trim().isNotEmpty) {
          throw const FormatException('Azione pin non valida.');
        }
        break;
      case WorkflowActionKind.setPriority:
        final priority = int.tryParse(rule.actionValue.trim());
        if (priority == null || priority < 0 || priority > 3) {
          throw const FormatException('Priorità automazione non valida.');
        }
        break;
    }
  }

  static void validateRun(WorkflowRun run) {
    if (run.id.trim().isEmpty ||
        run.ruleId.trim().isEmpty ||
        run.noteId.trim().isEmpty ||
        run.ranAt < 0) {
      throw const FormatException('Esecuzione automazione non valida.');
    }
  }
}

abstract final class WorkflowAutomations {
  static WorkflowEvaluation evaluate({
    required Note? before,
    required Note incoming,
    required Iterable<WorkflowRule> rules,
    required Set<String> validCollectionIds,
    required int now,
  }) {
    final trigger = _detect(before, incoming);
    if (trigger == null || incoming.isDeleted) {
      return WorkflowEvaluation(
        note: incoming,
        trigger: trigger,
        appliedRules: const [],
      );
    }

    final ordered = rules.where((rule) => rule.enabled).toList(growable: false)
      ..sort((a, b) {
        final created = a.createdAt.compareTo(b.createdAt);
        return created != 0 ? created : a.id.compareTo(b.id);
      });

    var next = incoming;
    final applied = <WorkflowRule>[];
    for (final rule in ordered) {
      WorkflowAutomationRules.validateRule(rule);
      if (rule.trigger != trigger || !_matches(rule, next)) continue;
      final changed = _apply(
        rule,
        next,
        validCollectionIds: validCollectionIds,
        now: now,
      );
      if (identical(changed, next)) continue;
      next = changed;
      applied.add(rule);
    }

    return WorkflowEvaluation(
      note: next,
      trigger: trigger,
      appliedRules: List.unmodifiable(applied),
    );
  }

  static WorkflowTrigger? _detect(Note? before, Note incoming) {
    if (before == null) return WorkflowTrigger.itemCreated;
    if (before.isDeleted || incoming.isDeleted) return null;
    if (before.isTask &&
        incoming.isTask &&
        !before.taskCompleted &&
        incoming.taskCompleted) {
      return WorkflowTrigger.taskCompleted;
    }
    if (_same(before, incoming)) return null;
    return WorkflowTrigger.itemUpdated;
  }

  static bool _matches(WorkflowRule rule, Note note) {
    final subjectMatches = switch (rule.subject) {
      WorkflowSubject.any => true,
      WorkflowSubject.note => !note.isTask,
      WorkflowSubject.task => note.isTask,
    };
    if (!subjectMatches) return false;

    final requiredTag = rule.requiredTag?.trim().toLowerCase();
    if (requiredTag != null &&
        requiredTag.isNotEmpty &&
        !note.tags.any((tag) => tag.trim().toLowerCase() == requiredTag)) {
      return false;
    }

    final title = rule.titleContains?.trim().toLowerCase();
    if (title != null &&
        title.isNotEmpty &&
        !note.title.toLowerCase().contains(title)) {
      return false;
    }
    return true;
  }

  static Note _apply(
    WorkflowRule rule,
    Note note, {
    required Set<String> validCollectionIds,
    required int now,
  }) {
    switch (rule.actionKind) {
      case WorkflowActionKind.addTag:
        final value = rule.actionValue.trim();
        if (note.tags.any((tag) => tag.toLowerCase() == value.toLowerCase())) {
          return note;
        }
        return note.copyWith(
          tags: [...note.tags, value],
          updatedAt: _timestamp(note.updatedAt, now),
        );
      case WorkflowActionKind.moveToCollection:
        final id = rule.actionValue.trim();
        if (!validCollectionIds.contains(id) || note.collectionId == id) {
          return note;
        }
        return note.copyWith(
          collectionId: id,
          updatedAt: _timestamp(note.updatedAt, now),
        );
      case WorkflowActionKind.pin:
        if (note.pinned) return note;
        return note.copyWith(
          pinned: true,
          updatedAt: _timestamp(note.updatedAt, now),
        );
      case WorkflowActionKind.setPriority:
        if (!note.isTask) return note;
        final details = TaskDetails.tryDecode(note.taskJson);
        final priority = int.tryParse(rule.actionValue.trim());
        if (details == null || priority == null || details.priority == priority) {
          return note;
        }
        return note.copyWith(
          taskJson: details.copyWith(priority: priority).encode(),
          updatedAt: _timestamp(note.updatedAt, now),
        );
    }
  }

  static int _timestamp(int current, int now) => now > current ? now : current;

  static bool _same(Note a, Note b) =>
      a.title == b.title &&
      a.body == b.body &&
      a.collectionId == b.collectionId &&
      a.favorite == b.favorite &&
      a.deletedAt == b.deletedAt &&
      a.pinned == b.pinned &&
      a.archived == b.archived &&
      _sameList(a.tags, b.tags) &&
      a.taskJson == b.taskJson &&
      a.sketchJson == b.sketchJson;

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}

const _unset = Object();

String? _optional(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
