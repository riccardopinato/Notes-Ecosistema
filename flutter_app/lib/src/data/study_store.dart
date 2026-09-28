import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/note.dart';
import '../domain/study.dart';

class StudySnapshot {
  const StudySnapshot({
    required this.items,
    required this.states,
    required this.logs,
  });

  final List<LearningItem> items;
  final List<ReviewState> states;
  final List<ReviewLog> logs;
}

class StudyStore {
  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final root = await getDatabasesPath();
    _db = await openDatabase(
      p.join(root, 'notes-study.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE learning_items (
            id TEXT NOT NULL PRIMARY KEY,
            sourceNoteId TEXT NOT NULL,
            sourceSnapshot TEXT NOT NULL,
            sourceFingerprint TEXT NOT NULL,
            sourceUpdatedAt INTEGER NOT NULL,
            prompt TEXT NOT NULL,
            answer TEXT NOT NULL,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL,
            suspended INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE review_states (
            itemId TEXT NOT NULL PRIMARY KEY,
            dueAt INTEGER NOT NULL,
            lastReviewedAt INTEGER,
            intervalDays INTEGER NOT NULL,
            ease REAL NOT NULL,
            repetitions INTEGER NOT NULL,
            lapses INTEGER NOT NULL,
            FOREIGN KEY(itemId) REFERENCES learning_items(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE TABLE review_logs (
            id TEXT NOT NULL PRIMARY KEY,
            itemId TEXT NOT NULL,
            rating TEXT NOT NULL,
            reviewedAt INTEGER NOT NULL,
            previousDueAt INTEGER NOT NULL,
            nextDueAt INTEGER NOT NULL,
            intervalDays INTEGER NOT NULL,
            FOREIGN KEY(itemId) REFERENCES learning_items(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX study_source_idx ON learning_items(sourceNoteId)',
        );
        await db.execute(
          'CREATE INDEX study_due_idx ON review_states(dueAt)',
        );
        await db.execute(
          'CREATE INDEX study_log_item_idx ON review_logs(itemId, reviewedAt)',
        );
      },
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
    return _db!;
  }

  Future<StudySnapshot> snapshot() async {
    final db = await database;
    final items = (await db.query(
      'learning_items',
      orderBy: 'createdAt ASC, id ASC',
    ))
        .map(LearningItem.fromMap)
        .toList(growable: false);
    final states = (await db.query(
      'review_states',
      orderBy: 'dueAt ASC, itemId ASC',
    ))
        .map(ReviewState.fromMap)
        .toList(growable: false);
    final logs = (await db.query(
      'review_logs',
      orderBy: 'reviewedAt ASC, id ASC',
    ))
        .map(ReviewLog.fromMap)
        .toList(growable: false);
    return StudySnapshot(items: items, states: states, logs: logs);
  }

  Future<LearningItem> createFromNote({
    required Note note,
    required String prompt,
    required String answer,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final item = StudyRules.fromNote(
      id: const Uuid().v4(),
      note: note,
      prompt: prompt,
      answer: answer,
      now: now,
    );
    await db.insert('learning_items', item.toMap());
    return item;
  }

  Future<void> updateFromSource(LearningItem item, Note source) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = StudyRules.fromNote(
      id: item.id,
      note: source,
      prompt: item.prompt,
      answer: item.answer,
      now: item.createdAt,
    );
    final row = next.toMap()
      ..['createdAt'] = item.createdAt
      ..['updatedAt'] = now
      ..['suspended'] = item.suspended ? 1 : 0;
    await db.update(
      'learning_items',
      row,
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> review(
    String itemId,
    StudyRating rating, {
    StudyScheduler scheduler = const SimpleStudyScheduler(),
    int? reviewedAt,
  }) async {
    final db = await database;
    final itemRows = await db.query(
      'learning_items',
      where: 'id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    if (itemRows.isEmpty) {
      throw const FormatException('Learning Item non trovato.');
    }
    final at = reviewedAt ?? DateTime.now().millisecondsSinceEpoch;
    final stateRows = await db.query(
      'review_states',
      where: 'itemId = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    final current = stateRows.isEmpty
        ? ReviewState(
            itemId: itemId,
            dueAt: at,
            intervalDays: 0,
            ease: 2.5,
            repetitions: 0,
            lapses: 0,
          )
        : ReviewState.fromMap(stateRows.first);
    final next = scheduler.next(current, rating, reviewedAt: at);
    StudyRules.validateState(next);
    final log = ReviewLog(
      id: const Uuid().v4(),
      itemId: itemId,
      rating: rating,
      reviewedAt: at,
      previousDueAt: current.dueAt,
      nextDueAt: next.dueAt,
      intervalDays: next.intervalDays,
    );
    await db.transaction((txn) async {
      await txn.insert(
        'review_states',
        next.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert('review_logs', log.toMap());
    });
  }

  Future<void> setSuspended(String itemId, bool value) async {
    final db = await database;
    await db.update(
      'learning_items',
      {
        'suspended': value ? 1 : 0,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> delete(String itemId) async {
    final db = await database;
    await db.delete('learning_items', where: 'id = ?', whereArgs: [itemId]);
  }

  Future<void> deleteForNote(String noteId) async {
    final db = await database;
    await db.delete(
      'learning_items',
      where: 'sourceNoteId = ?',
      whereArgs: [noteId],
    );
  }

  Future<Map<String, Object?>> exportBackup() async {
    final data = await snapshot();
    return {
      'version': 1,
      'items': data.items.map((item) => item.toMap()).toList(),
      'states': data.states.map((item) => item.toMap()).toList(),
      'logs': data.logs.map((item) => item.toMap()).toList(),
    };
  }

  Future<void> restoreExact(
    Map<String, Object?> payload, {
    required Set<String> noteIds,
  }) async {
    if (payload['version'] != 1 ||
        payload['items'] is! List ||
        payload['states'] is! List ||
        payload['logs'] is! List) {
      throw const FormatException('Backup Study non valido.');
    }
    final items = (payload['items'] as List).map((raw) {
      if (raw is! Map) throw const FormatException('Learning Item non valido.');
      final item = LearningItem.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      StudyRules.validateItem(item);
      if (!noteIds.contains(item.sourceNoteId)) {
        throw const FormatException('Fonte Study mancante.');
      }
      return item;
    }).toList(growable: false);
    if (items.length > StudyRules.maxItems ||
        items.map((item) => item.id).toSet().length != items.length) {
      throw const FormatException('Backup Study non valido.');
    }
    final itemIds = items.map((item) => item.id).toSet();
    final states = (payload['states'] as List).map((raw) {
      if (raw is! Map) throw const FormatException('Review State non valido.');
      final state = ReviewState.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      StudyRules.validateState(state);
      if (!itemIds.contains(state.itemId)) {
        throw const FormatException('Review State senza Learning Item.');
      }
      return state;
    }).toList(growable: false);
    final logs = (payload['logs'] as List).map((raw) {
      if (raw is! Map) throw const FormatException('Review Log non valido.');
      final log = ReviewLog.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (!itemIds.contains(log.itemId) ||
          log.id.trim().isEmpty ||
          log.reviewedAt < 0 ||
          log.nextDueAt < 0) {
        throw const FormatException('Review Log non valido.');
      }
      return log;
    }).toList(growable: false);

    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('review_logs');
      await txn.delete('review_states');
      await txn.delete('learning_items');
      for (final item in items) {
        await txn.insert('learning_items', item.toMap());
      }
      for (final state in states) {
        await txn.insert('review_states', state.toMap());
      }
      for (final log in logs) {
        await txn.insert('review_logs', log.toMap());
      }
    });
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }
}
