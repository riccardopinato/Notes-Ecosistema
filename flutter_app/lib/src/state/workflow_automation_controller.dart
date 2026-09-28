import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/workflow_automation_store.dart';
import '../domain/workflow_automation.dart';

final workflowAutomationStoreProvider = Provider<WorkflowAutomationStore>((ref) {
  final store = WorkflowAutomationStore();
  ref.onDispose(store.close);
  return store;
});

class WorkflowAutomationState {
  const WorkflowAutomationState({
    this.rules = const [],
    this.runs = const [],
    this.loading = true,
    this.error,
  });

  final List<WorkflowRule> rules;
  final List<WorkflowRun> runs;
  final bool loading;
  final Object? error;
}

class WorkflowAutomationController
    extends StateNotifier<WorkflowAutomationState> {
  WorkflowAutomationController(this._store)
      : super(const WorkflowAutomationState()) {
    refresh();
  }

  final WorkflowAutomationStore _store;
  int _generation = 0;

  Future<void> refresh() async {
    final generation = ++_generation;
    state = WorkflowAutomationState(
      rules: state.rules,
      runs: state.runs,
      loading: true,
    );
    try {
      final rules = await _store.loadRules();
      final runs = await _store.recentRuns();
      if (generation != _generation) return;
      state = WorkflowAutomationState(
        rules: rules,
        runs: runs,
        loading: false,
      );
    } catch (error) {
      if (generation != _generation) return;
      state = WorkflowAutomationState(
        rules: state.rules,
        runs: state.runs,
        loading: false,
        error: error,
      );
    }
  }

  Future<void> save({
    WorkflowRule? existing,
    required String name,
    required bool enabled,
    required WorkflowTrigger trigger,
    required WorkflowSubject subject,
    String? requiredTag,
    String? titleContains,
    required WorkflowActionKind actionKind,
    required String actionValue,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rule = WorkflowRule(
      id: existing?.id ?? const Uuid().v4(),
      name: name.trim(),
      enabled: enabled,
      trigger: trigger,
      subject: subject,
      requiredTag: _optional(requiredTag),
      titleContains: _optional(titleContains),
      actionKind: actionKind,
      actionValue: actionValue.trim(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await _store.upsertRule(rule);
    await refresh();
  }

  Future<void> setEnabled(WorkflowRule rule, bool enabled) async {
    await _store.setEnabled(rule.id, enabled);
    await refresh();
  }

  Future<void> delete(WorkflowRule rule) async {
    await _store.deleteRule(rule.id);
    await refresh();
  }
}

final workflowAutomationProvider = StateNotifierProvider<
    WorkflowAutomationController, WorkflowAutomationState>((ref) {
  return WorkflowAutomationController(ref.watch(workflowAutomationStoreProvider));
});

String? _optional(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}
