import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/planner.dart';
import 'package:notes_ecosistema/src/domain/workflow_automation.dart';

void main() {
  Note note({
    required String id,
    String title = 'Nota',
    List<String> tags = const [],
    String? collectionId,
    bool pinned = false,
    String? taskJson,
    int updatedAt = 10,
    int? deletedAt,
  }) =>
      Note(
        id: id,
        title: title,
        body: 'body',
        collectionId: collectionId,
        favorite: false,
        createdAt: 1,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        pinned: pinned,
        archived: false,
        tags: tags,
        taskJson: taskJson,
      );

  WorkflowRule rule({
    required String id,
    required WorkflowTrigger trigger,
    required WorkflowSubject subject,
    required WorkflowActionKind action,
    required String value,
    String? requiredTag,
    String? titleContains,
    int createdAt = 1,
  }) =>
      WorkflowRule(
        id: id,
        name: 'Rule $id',
        enabled: true,
        trigger: trigger,
        subject: subject,
        requiredTag: requiredTag,
        titleContains: titleContains,
        actionKind: action,
        actionValue: value,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

  test('new note can be tagged once with deterministic audit selection', () {
    final incoming = note(id: 'n1', title: 'Progetto Alpha');
    final evaluation = WorkflowAutomations.evaluate(
      before: null,
      incoming: incoming,
      rules: [
        rule(
          id: 'b',
          trigger: WorkflowTrigger.itemCreated,
          subject: WorkflowSubject.note,
          action: WorkflowActionKind.addTag,
          value: 'inbox',
          createdAt: 2,
        ),
        rule(
          id: 'a',
          trigger: WorkflowTrigger.itemCreated,
          subject: WorkflowSubject.note,
          action: WorkflowActionKind.addTag,
          value: 'work',
          titleContains: 'alpha',
          createdAt: 1,
        ),
      ],
      validCollectionIds: const {},
      now: 20,
    );

    expect(evaluation.trigger, WorkflowTrigger.itemCreated);
    expect(evaluation.note.tags, ['work', 'inbox']);
    expect(evaluation.appliedRules.map((item) => item.id), ['a', 'b']);
    expect(evaluation.note.updatedAt, 20);
  });

  test('completion trigger changes task priority without recursion', () {
    final beforeDetails = TaskDetails.empty();
    final afterDetails = beforeDetails.copyWith(completedAt: 50);
    final before = note(id: 't1', taskJson: beforeDetails.encode());
    final incoming = note(
      id: 't1',
      taskJson: afterDetails.encode(),
      updatedAt: 50,
    );

    final evaluation = WorkflowAutomations.evaluate(
      before: before,
      incoming: incoming,
      rules: [
        rule(
          id: 'priority',
          trigger: WorkflowTrigger.taskCompleted,
          subject: WorkflowSubject.task,
          action: WorkflowActionKind.setPriority,
          value: '3',
        ),
      ],
      validCollectionIds: const {},
      now: 60,
    );

    expect(evaluation.trigger, WorkflowTrigger.taskCompleted);
    expect(
      TaskDetails.decode(evaluation.note.taskJson!).priority,
      3,
    );
    expect(evaluation.appliedRules.single.id, 'priority');

    final repeated = WorkflowAutomations.evaluate(
      before: evaluation.note,
      incoming: evaluation.note.copyWith(updatedAt: 61),
      rules: [
        rule(
          id: 'priority',
          trigger: WorkflowTrigger.taskCompleted,
          subject: WorkflowSubject.task,
          action: WorkflowActionKind.setPriority,
          value: '3',
        ),
      ],
      validCollectionIds: const {},
      now: 61,
    );
    expect(repeated.trigger, isNull);
    expect(repeated.changed, isFalse);
  });

  test('idempotent actions and missing collections are safe no-ops', () {
    final incoming = note(
      id: 'n1',
      tags: const ['Inbox'],
      collectionId: 'existing',
    );
    final evaluation = WorkflowAutomations.evaluate(
      before: null,
      incoming: incoming,
      rules: [
        rule(
          id: 'tag',
          trigger: WorkflowTrigger.itemCreated,
          subject: WorkflowSubject.any,
          action: WorkflowActionKind.addTag,
          value: 'inbox',
        ),
        rule(
          id: 'move',
          trigger: WorkflowTrigger.itemCreated,
          subject: WorkflowSubject.any,
          action: WorkflowActionKind.moveToCollection,
          value: 'missing',
          createdAt: 2,
        ),
      ],
      validCollectionIds: const {'existing'},
      now: 20,
    );

    expect(evaluation.changed, isFalse);
    expect(evaluation.note.tags, ['Inbox']);
    expect(evaluation.note.collectionId, 'existing');
  });

  test('deleted content never runs automations', () {
    final incoming = note(id: 'n1', deletedAt: 99);
    final evaluation = WorkflowAutomations.evaluate(
      before: null,
      incoming: incoming,
      rules: [
        rule(
          id: 'pin',
          trigger: WorkflowTrigger.itemCreated,
          subject: WorkflowSubject.any,
          action: WorkflowActionKind.pin,
          value: '',
        ),
      ],
      validCollectionIds: const {},
      now: 100,
    );

    expect(evaluation.changed, isFalse);
    expect(evaluation.note.pinned, isFalse);
  });
}
