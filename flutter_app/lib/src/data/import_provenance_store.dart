import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/import_provenance.dart';

class ImportProvenanceStore {
  Database? _db;

  Future<Database> get database async {
    final current = _db;
    if (current != null) return current;
    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'notes-imports.db'),
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE import_records (
            source TEXT NOT NULL,
            sourceInstance TEXT NOT NULL,
            externalId TEXT NOT NULL,
            targetNoteId TEXT NOT NULL,
            externalFingerprint TEXT NOT NULL,
            localFingerprint TEXT NOT NULL,
            lastBatchId TEXT NOT NULL,
            importedAt INTEGER NOT NULL,
            lastSeenAt INTEGER NOT NULL,
            PRIMARY KEY(source, sourceInstance, externalId)
          )
        ''');
        await database.execute(
          'CREATE INDEX index_import_records_target '
          'ON import_records(targetNoteId)',
        );
        await database.execute('''
          CREATE TABLE import_batches (
            id TEXT NOT NULL PRIMARY KEY,
            source TEXT NOT NULL,
            sourceInstance TEXT NOT NULL,
            startedAt INTEGER NOT NULL,
            completedAt INTEGER,
            summaryJson TEXT
          )
        ''');
        await database.execute(
          'CREATE INDEX index_import_batches_source '
          'ON import_batches(source, sourceInstance, startedAt)',
        );
      },
    );
    _db = db;
    return db;
  }

  Future<String> beginBatch({
    required String source,
    required String sourceInstance,
  }) async {
    final identity = ImportIdentity(
      source: source,
      sourceInstance: sourceInstance,
      externalId: '_batch',
    )..validate();
    final id = const Uuid().v4();
    final db = await database;
    await db.insert('import_batches', {
      'id': id,
      'source': identity.source,
      'sourceInstance': identity.sourceInstance,
      'startedAt': DateTime.now().millisecondsSinceEpoch,
    });
    return id;
  }

  Future<void> completeBatch(String id, ImportSummary summary) async {
    final db = await database;
    final changed = await db.update(
      'import_batches',
      {
        'completedAt': DateTime.now().millisecondsSinceEpoch,
        'summaryJson': jsonEncode(summary.toMap()),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changed != 1) {
      throw const FormatException('Batch import non trovato.');
    }
  }

  Future<ImportRecord?> find(ImportIdentity identity) async {
    identity.validate();
    final db = await database;
    final rows = await db.query(
      'import_records',
      where: 'source = ? AND sourceInstance = ? AND externalId = ?',
      whereArgs: [
        identity.source,
        identity.sourceInstance,
        identity.externalId,
      ],
      limit: 1,
    );
    return rows.isEmpty ? null : ImportRecord.fromMap(rows.first);
  }

  Future<Map<String, ImportRecord>> findAll(
    Iterable<ImportIdentity> identities,
  ) async {
    final result = <String, ImportRecord>{};
    for (final identity in identities) {
      final record = await find(identity);
      if (record != null) result[identity.key] = record;
    }
    return result;
  }

  Future<void> upsert(ImportRecord record) async {
    record.identity.validate();
    if (record.targetNoteId.trim().isEmpty ||
        record.externalFingerprint.length != 64 ||
        record.localFingerprint.length != 64 ||
        record.lastBatchId.trim().isEmpty ||
        record.importedAt < 0 ||
        record.lastSeenAt < 0) {
      throw const FormatException('Record import non valido.');
    }
    final db = await database;
    await db.insert(
      'import_records',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteForNote(String noteId) async {
    if (noteId.trim().isEmpty) return;
    final db = await database;
    await db.delete(
      'import_records',
      where: 'targetNoteId = ?',
      whereArgs: [noteId],
    );
  }

  Future<Map<String, Object?>> exportBackup() async {
    final db = await database;
    return {
      'version': 1,
      'records': await db.query(
        'import_records',
        orderBy: 'source ASC, sourceInstance ASC, externalId ASC',
      ),
      'batches': await db.query(
        'import_batches',
        orderBy: 'startedAt ASC, id ASC',
      ),
    };
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }
}
