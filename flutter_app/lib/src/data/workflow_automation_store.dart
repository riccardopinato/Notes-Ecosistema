import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/workflow_automation.dart';

class WorkflowAutomationSnapshot {
  const WorkflowAutomationSnapshot({
    required this.rules,
    required this.runs,
  });

  final List<WorkflowRule> rules;
  final List<WorkflowRun> runs;
}

class WorkflowAutomationStore {
  Database? _db;

  Future<Database> get database async {
    final current = _db;
    if (current != null) return current;
    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'notes-automations.db'),
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE workflow_rules (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            enabled INTEGER NOT NULL,
            trigger TEXT NOT NULL,
            subject TEXT NOT NULL,
            requiredTag TEXT,
            titleContains TEXT,
            actionKind TEXT NOT NULL,
            actionValue TEXT NOT NULL,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX index_workflow_rules_enabled '
          'ON workflow_rules(enabled, createdAt ASC)',
        );
        await database.execute('''
          CREATE TABLE workflow_runs (
            id TEXT NOT NULL PRIMARY KEY,
            ruleId TEXT NOT NULL,
            noteId TEXT NOT NULL,
            trigger TEXT NOT NULL,
            actionKind TEXT NOT NULL,
            ranAt INTEGER NOT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX index_workflow_runs_time '
          'ON workflow_runs(ranAt DESC, id DESC)',
        );
      },
    );
    _db = db;
    return db;
  }

  Future<List<WorkflowRule>> loadRules() async {
    final db = await database;
    final rows = await db.query(
      'workflow_rules',
      orderBy: 'createdAt ASC, id ASC',
    );
    return rows.map(WorkflowRule.fromMap).toList(growable: false);
  }

  Future<List<WorkflowRule>> loadEnabledRules() async {
    final db = await database;
    final rows = await db.query(
      'workflow_rules',
      where: 'enabled = 1',
      orderBy: 'createdAt ASC, id ASC',
    );
    return rows.map(WorkflowRule.fromMap).toList(growable: false);
  }

  Future<List<WorkflowRun>> recentRuns({int limit = 40}) async {
    if (limit < 1 || limit > WorkflowAutomationRules.maxRuns) {
      throw const FormatException('Limite esecuzioni non valido.');
    }
    final db = await database;
    final rows = await db.query(
      'workflow_runs',
      orderBy: 'ranAt DESC, id DESC',
      limit: limit,
    );
    return rows.map(WorkflowRun.fromMap).toList(growable: false);
  }

  Future<void> upsertRule(WorkflowRule rule) async {
    WorkflowAutomationRules.validateRule(rule);
    final db = await database;
    final existing = await db.query(
      'workflow_rules',
      where: 'id = ?',
      whereArgs: [rule.id],
      limit: 1,
    );
    if (existing.isEmpty) {
      final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM workflow_rules'),
          ) ??
          0;
      if (count >= WorkflowAutomationRules.maxRules) {
        throw const FormatException('Limite automazioni raggiunto.');
      }
    }
    await db.insert(
      'workflow_rules',
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final db = await database;
    final changed = await db.update(
      'workflow_rules',
      {
        'enabled': enabled ? 1 : 0,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changed != 1) {
      throw const FormatException('Automazione non trovata.');
    }
  }

  Future<void> deleteRule(String id) async {
    final db = await database;
    await db.delete('workflow_rules', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> recordEvaluation({
    required String noteId,
    required WorkflowTrigger trigger,
    required Iterable<WorkflowRule> rules,
    required int ranAt,
  }) async {
    final applied = rules.toList(growable: false);
    if (applied.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final rule in applied) {
        final run = WorkflowRun(
          id: const Uuid().v4(),
          ruleId: rule.id,
          noteId: noteId,
          trigger: trigger,
          actionKind: rule.actionKind,
          ranAt: ranAt,
        );
        WorkflowAutomationRules.validateRun(run);
        await txn.insert('workflow_runs', run.toMap());
      }
      await txn.rawDelete(
        'DELETE FROM workflow_runs WHERE id NOT IN '
        '(SELECT id FROM workflow_runs ORDER BY ranAt DESC, id DESC LIMIT ?)',
        [WorkflowAutomationRules.maxRuns],
      );
    });
  }

  Future<void> deleteRunsForNote(String noteId) async {
    final clean = noteId.trim();
    if (clean.isEmpty) return;
    final db = await database;
    await db.delete(
      'workflow_runs',
      where: 'noteId = ?',
      whereArgs: [clean],
    );
  }

  Future<WorkflowAutomationSnapshot> snapshot() async =>
      WorkflowAutomationSnapshot(
        rules: await loadRules(),
        runs: await recentRuns(limit: WorkflowAutomationRules.maxRuns),
      );

  Future<Map<String, Object?>> exportBackup() async {
    final data = await snapshot();
    return {
      'version': 1,
      'rules': data.rules.map((item) => item.toMap()).toList(growable: false),
      'runs': data.runs.map((item) => item.toMap()).toList(growable: false),
    };
  }

  Future<void> restoreBackupExact(
    Map<String, Object?> payload, {
    required Set<String> noteIds,
  }) async {
    if (payload['version'] != 1 ||
        payload['rules'] is! List ||
        payload['runs'] is! List) {
      throw const FormatException('Backup automazioni non valido.');
    }
    final rawRules = payload['rules'] as List;
    final rawRuns = payload['runs'] as List;
    if (rawRules.length > WorkflowAutomationRules.maxRules ||
        rawRuns.length > WorkflowAutomationRules.maxRuns) {
      throw const FormatException('Backup automazioni troppo grande.');
    }

    final rules = rawRules.map((raw) {
      if (raw is! Map) throw const FormatException('Regola non valida.');
      final rule = WorkflowRule.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      WorkflowAutomationRules.validateRule(rule);
      return rule;
    }).toList(growable: false);
    if (rules.map((item) => item.id).toSet().length != rules.length) {
      throw const FormatException('Regole automazione duplicate.');
    }
    final runs = rawRuns.map((raw) {
      if (raw is! Map) throw const FormatException('Esecuzione non valida.');
      final run = WorkflowRun.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      WorkflowAutomationRules.validateRun(run);
      if (!noteIds.contains(run.noteId)) {
        throw const FormatException('Esecuzione automazione verso nota mancante.');
      }
      return run;
    }).toList(growable: false);
    if (runs.map((item) => item.id).toSet().length != runs.length) {
      throw const FormatException('Esecuzioni automazione duplicate.');
    }

    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('workflow_runs');
      await txn.delete('workflow_rules');
      for (final rule in rules) {
        await txn.insert('workflow_rules', rule.toMap());
      }
      for (final run in runs) {
        await txn.insert('workflow_runs', run.toMap());
      }
    });
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }
}
