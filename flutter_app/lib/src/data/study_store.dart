import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/study.dart';

class StudySnapshot {
  const StudySnapshot({
    required this.items,
    required this.logs,
  });

  final List<LearningItem> items;
  final List<ReviewLog> logs;
}

class StudyStore {
  Database? _db;

  Future<Database> get database async {
    final current = _db;
    if (current != null) return current;
    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'notes-study.db'),
      version: 1,
      onConfigure: (database) async =>
          database.execute('PRAGMA foreign_keys=ON'),
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE learning_items (
            id TEXT NOT NULL PRIMARY KEY,
            sourceNoteId TEXT NOT NULL,
            prompt TEXT NOT NULL,
            answer TEXT NOT NULL,
            sourceSnapshot TEXT NOT NULL,
            sourceUpdatedAt INTEGER NOT NULL,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX index_learning_items_source '
          'ON learning_items(sourceNoteId, updatedAt DESC)',
        );
        await database.execute('''
          CREATE TABLE review_logs (
            id TEXT NOT NULL PRIMARY KEY,
            itemId TEXT NOT NULL,
            reviewedAt INTEGER NOT NULL,
            rating TEXT NOT NULL,
            intervalDays INTEGER NOT NULL,
            FOREIGN KEY(itemId) REFERENCES learning_items(id) ON DELETE CASCADE
          )
        ''');
        await database.execute(
          'CREATE INDEX index_review_logs_item '
          'ON review_logs(itemId, reviewedAt ASC)',
        );
      },
    );
    _db = db;
    return db;
  }

  Future<StudySnapshot> snapshot() async {
    final db = await database;
    final items = await db.query(
      'learning_items',
      orderBy: 'createdAt ASC, id ASC',
    );
    final logs = await db.query(
      'review_logs',
      orderBy: 'reviewedAt ASC, id ASC',
    );
    return StudySnapshot(
      items: items.map(LearningItem.fromMap).toList(growable: false),
      logs: logs.map(ReviewLog.fromMap).toList(growable: false),
    );
  }

  Future<LearningItem> create({
    required String sourceNoteId,
    required String prompt,
    required String answer,
    required String sourceSnapshot,
    required int sourceUpdatedAt,
  }) async {
    final db = await database;
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM learning_items'),
        ) ??
        0;
    if (count >= StudyRules.maxItems) {
      throw const FormatException('Limite elementi di studio raggiunto.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final item = LearningItem(
      id: const Uuid().v4(),
      sourceNoteId: sourceNoteId,
      prompt: prompt.trim(),
      answer: answer.trim(),
      sourceSnapshot: sourceSnapshot,
      sourceUpdatedAt: sourceUpdatedAt,
      createdAt: now,
      updatedAt: now,
    );
    StudyRules.validateItem(item);
    await db.insert(
      'learning_items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return item;
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete('learning_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<ReviewLog> review({
    required LearningItem item,
    required StudyRating rating,
    StudyScheduler scheduler = const SimpleStudyScheduler(),
  }) async {
    final snapshot = await this.snapshot();
    final now = DateTime.now().millisecondsSinceEpoch;
    final state = scheduler.stateFor(item, snapshot.logs, now: now);
    final log = ReviewLog(
      id: const Uuid().v4(),
      itemId: item.id,
      reviewedAt: now,
      rating: rating,
      intervalDays: scheduler.nextIntervalDays(state, rating),
    );
    StudyRules.validateLog(log);
    final db = await database;
    await db.insert(
      'review_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return log;
  }

  Future<Map<String, Object?>> exportBackup() async {
    final data = await snapshot();
    return {
      'version': 1,
      'items': data.items.map((item) => item.toMap()).toList(growable: false),
      'logs': data.logs.map((item) => item.toMap()).toList(growable: false),
    };
  }

  Future<void> restoreBackupExact(
    Map<String, Object?> payload, {
    required Set<String> noteIds,
  }) async {
    if (payload['version'] != 1 ||
        payload['items'] is! List ||
        payload['logs'] is! List) {
      throw const FormatException('Backup Study non valido.');
    }
    final rawItems = payload['items'] as List;
    final rawLogs = payload['logs'] as List;
    if (rawItems.length > StudyRules.maxItems || rawLogs.length > 1000000) {
      throw const FormatException('Backup Study troppo grande.');
    }

    final items = rawItems.map((raw) {
      if (raw is! Map) throw const FormatException('LearningItem non valido.');
      final item = LearningItem.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      StudyRules.validateItem(item);
      if (!noteIds.contains(item.sourceNoteId)) {
        // Historical evidence remains meaningful when the source was purged;
        // the ID is intentionally preserved and the snapshot stays usable.
      }
      return item;
    }).toList(growable: false);
    if (items.map((item) => item.id).toSet().length != items.length) {
      throw const FormatException('LearningItem duplicati.');
    }
    final itemIds = items.map((item) => item.id).toSet();

    final logs = rawLogs.map((raw) {
      if (raw is! Map) throw const FormatException('ReviewLog non valido.');
      final log = ReviewLog.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      StudyRules.validateLog(log);
      if (!itemIds.contains(log.itemId)) {
        throw const FormatException('ReviewLog senza LearningItem.');
      }
      return log;
    }).toList(growable: false);
    if (logs.map((item) => item.id).toSet().length != logs.length) {
      throw const FormatException('ReviewLog duplicati.');
    }

    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('review_logs');
      await txn.delete('learning_items');
      for (final item in items) {
        await txn.insert(
          'learning_items',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      for (final log in logs) {
        await txn.insert(
          'review_logs',
          log.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }
}
