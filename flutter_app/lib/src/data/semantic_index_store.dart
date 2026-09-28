import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/local_intelligence.dart';

class SemanticIndexEntry {
  const SemanticIndexEntry({
    required this.modelId,
    required this.modelVersion,
    required this.documentId,
    required this.noteId,
    required this.fingerprint,
    required this.vector,
    required this.updatedAt,
  });

  final String modelId;
  final String modelVersion;
  final String documentId;
  final String noteId;
  final String fingerprint;
  final SemanticVector vector;
  final int updatedAt;
}

class SemanticIndexStore {
  Database? _db;

  Future<Database> get database async {
    final current = _db;
    if (current != null) return current;
    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'notes-semantic.db'),
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE semantic_embeddings (
            modelId TEXT NOT NULL,
            modelVersion TEXT NOT NULL,
            documentId TEXT NOT NULL,
            noteId TEXT NOT NULL,
            fingerprint TEXT NOT NULL,
            dimensions INTEGER NOT NULL,
            vector BLOB NOT NULL,
            updatedAt INTEGER NOT NULL,
            PRIMARY KEY(modelId, modelVersion, documentId)
          )
        ''');
        await database.execute(
          'CREATE INDEX index_semantic_embeddings_note '
          'ON semantic_embeddings(noteId)',
        );
        await database.execute('''
          CREATE TABLE semantic_meta (
            key TEXT NOT NULL PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
    _db = db;
    return db;
  }

  Future<SemanticIndexEntry?> get({
    required String modelId,
    required String modelVersion,
    required String documentId,
  }) async {
    final db = await database;
    final rows = await db.query(
      'semantic_embeddings',
      where: 'modelId = ? AND modelVersion = ? AND documentId = ?',
      whereArgs: [modelId, modelVersion, documentId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromMap(rows.single);
  }

  Future<List<SemanticIndexEntry>> forModel({
    required String modelId,
    required String modelVersion,
  }) async {
    final db = await database;
    final rows = await db.query(
      'semantic_embeddings',
      where: 'modelId = ? AND modelVersion = ?',
      whereArgs: [modelId, modelVersion],
      orderBy: 'documentId ASC',
    );
    return rows.map(_fromMap).toList(growable: false);
  }

  Future<void> upsert(SemanticIndexEntry entry) async {
    if (entry.modelId.trim().isEmpty ||
        entry.modelVersion.trim().isEmpty ||
        entry.documentId.trim().isEmpty ||
        entry.noteId.trim().isEmpty ||
        entry.fingerprint.length != 64 ||
        entry.updatedAt < 0) {
      throw const FormatException('Indice semantico non valido.');
    }
    final db = await database;
    await db.insert(
      'semantic_embeddings',
      _toMap(entry),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteStale({
    required String modelId,
    required String modelVersion,
    required Set<String> liveDocumentIds,
  }) async {
    final db = await database;
    final rows = await db.query(
      'semantic_embeddings',
      columns: ['documentId'],
      where: 'modelId = ? AND modelVersion = ?',
      whereArgs: [modelId, modelVersion],
    );
    final stale = [
      for (final row in rows)
        if (!liveDocumentIds.contains(row['documentId']?.toString() ?? ''))
          row['documentId']?.toString() ?? '',
    ].where((id) => id.isNotEmpty);
    await db.transaction((txn) async {
      for (final id in stale) {
        await txn.delete(
          'semantic_embeddings',
          where: 'modelId = ? AND modelVersion = ? AND documentId = ?',
          whereArgs: [modelId, modelVersion, id],
        );
      }
    });
  }

  Future<void> deleteForNote(String noteId) async {
    if (noteId.trim().isEmpty) return;
    final db = await database;
    await db.delete(
      'semantic_embeddings',
      where: 'noteId = ?',
      whereArgs: [noteId],
    );
  }

  Future<void> clearModel(String modelId) async {
    if (modelId.trim().isEmpty) return;
    final db = await database;
    await db.delete(
      'semantic_embeddings',
      where: 'modelId = ?',
      whereArgs: [modelId],
    );
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('semantic_embeddings');
    await db.delete('semantic_meta');
  }

  Future<void> setMeta(String key, String value) async {
    if (key.trim().isEmpty || key.length > 120 || value.length > 20000) {
      throw const FormatException('Metadata semantici non validi.');
    }
    final db = await database;
    await db.insert(
      'semantic_meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getMeta(String key) async {
    final db = await database;
    final rows = await db.query(
      'semantic_meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value']?.toString();
  }

  Future<int> count({
    required String modelId,
    required String modelVersion,
  }) async {
    final db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM semantic_embeddings '
            'WHERE modelId = ? AND modelVersion = ?',
            [modelId, modelVersion],
          ),
        ) ??
        0;
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }

  static Map<String, Object?> _toMap(SemanticIndexEntry entry) => {
        'modelId': entry.modelId,
        'modelVersion': entry.modelVersion,
        'documentId': entry.documentId,
        'noteId': entry.noteId,
        'fingerprint': entry.fingerprint,
        'dimensions': entry.vector.values.length,
        'vector': _encode(entry.vector),
        'updatedAt': entry.updatedAt,
      };

  static SemanticIndexEntry _fromMap(Map<String, Object?> row) {
    final dimensions = (row['dimensions'] as num?)?.toInt() ?? 0;
    final raw = row['vector'];
    if (raw is! Uint8List || dimensions <= 0 || dimensions > 4096) {
      throw const FormatException('Embedding persistito non valido.');
    }
    final values = _decode(raw, dimensions);
    return SemanticIndexEntry(
      modelId: row['modelId']?.toString() ?? '',
      modelVersion: row['modelVersion']?.toString() ?? '',
      documentId: row['documentId']?.toString() ?? '',
      noteId: row['noteId']?.toString() ?? '',
      fingerprint: row['fingerprint']?.toString() ?? '',
      vector: SemanticVector(values),
      updatedAt: (row['updatedAt'] as num?)?.toInt() ?? -1,
    );
  }

  static Uint8List _encode(SemanticVector vector) {
    final data = ByteData(vector.values.length * Float32List.bytesPerElement);
    for (var index = 0; index < vector.values.length; index++) {
      data.setFloat32(
        index * Float32List.bytesPerElement,
        vector.values[index],
        Endian.little,
      );
    }
    return data.buffer.asUint8List();
  }

  static List<double> _decode(Uint8List raw, int dimensions) {
    final expected = dimensions * Float32List.bytesPerElement;
    if (raw.length != expected) {
      throw const FormatException('Dimensione embedding persistito incoerente.');
    }
    final data = ByteData.sublistView(raw);
    return List<double>.generate(
      dimensions,
      (index) => data.getFloat32(
        index * Float32List.bytesPerElement,
        Endian.little,
      ),
      growable: false,
    );
  }
}
