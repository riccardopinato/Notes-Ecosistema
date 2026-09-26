import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/derivatives.dart';

class DerivativeStore {
  Database? _db;

  Future<Database> get database async {
    final current = _db;
    if (current != null) return current;
    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'notes-derivatives.db'),
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE derivatives (
            id TEXT NOT NULL PRIMARY KEY,
            sourceNoteId TEXT NOT NULL,
            sourceAssetKey TEXT,
            kind TEXT NOT NULL,
            content TEXT NOT NULL,
            sourceFingerprint TEXT NOT NULL,
            createdAt INTEGER NOT NULL,
            engine TEXT NOT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX index_derivatives_source '
          'ON derivatives(sourceNoteId, createdAt DESC)',
        );
      },
    );
    _db = db;
    return db;
  }

  Future<List<SourceDerivative>> forNote(String noteId) async {
    final db = await database;
    final rows = await db.query(
      'derivatives',
      where: 'sourceNoteId = ?',
      whereArgs: [noteId],
      orderBy: 'createdAt DESC, id ASC',
    );
    return rows.map(SourceDerivative.fromMap).toList(growable: false);
  }

  Future<SourceDerivative> add({
    required String sourceNoteId,
    required DerivativeKind kind,
    required String content,
    required String sourceText,
    String? sourceAssetKey,
    String engine = 'local-deterministic-v1',
  }) async {
    if (sourceNoteId.trim().isEmpty ||
        content.trim().isEmpty ||
        content.length > 500000) {
      throw const FormatException('Derivato non valido.');
    }
    final derivative = SourceDerivative(
      id: const Uuid().v4(),
      sourceNoteId: sourceNoteId,
      sourceAssetKey: sourceAssetKey,
      kind: kind,
      content: content,
      sourceFingerprint: sha256.convert(sourceText.codeUnits).toString(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
      engine: engine,
    );
    final db = await database;
    await db.insert('derivatives', derivative.toMap());
    return derivative;
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete('derivatives', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteForNote(String noteId) async {
    final db = await database;
    await db.delete(
      'derivatives',
      where: 'sourceNoteId = ?',
      whereArgs: [noteId],
    );
  }

  Future<Map<String, Object?>> exportBackup() async {
    final db = await database;
    return {
      'version': 1,
      'derivatives': await db.query(
        'derivatives',
        orderBy: 'createdAt ASC, id ASC',
      ),
    };
  }

  Future<void> importBackup(
    Map<String, Object?> payload, {
    required Map<String, String> noteIdMap,
  }) async {
    if (payload.isEmpty) return;
    if (payload['version'] != 1 || payload['derivatives'] is! List) {
      throw const FormatException('Backup derivati non valido.');
    }
    final rawItems = payload['derivatives'] as List;
    if (rawItems.length > 100000) {
      throw const FormatException('Backup derivati troppo grande.');
    }
    final db = await database;
    await db.transaction((txn) async {
      for (final raw in rawItems) {
        if (raw is! Map) {
          throw const FormatException('Derivato importato non valido.');
        }
        final source = SourceDerivative.fromMap(
          raw.map((key, value) => MapEntry(key.toString(), value)),
        );
        final noteId = noteIdMap[source.sourceNoteId];
        if (noteId == null) continue;
        if (source.content.trim().isEmpty ||
            source.content.length > 500000 ||
            source.sourceFingerprint.trim().isEmpty ||
            source.engine.trim().isEmpty) {
          throw const FormatException('Derivato importato non valido.');
        }
        await txn.insert(
          'derivatives',
          SourceDerivative(
            id: const Uuid().v4(),
            sourceNoteId: noteId,
            sourceAssetKey: source.sourceAssetKey,
            kind: source.kind,
            content: source.content,
            sourceFingerprint: source.sourceFingerprint,
            createdAt: source.createdAt,
            engine: source.engine,
          ).toMap(),
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
