import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/semantic_embeddings.dart';
import '../domain/unified_retrieval.dart';

class SemanticMatch {
  const SemanticMatch({
    required this.documentId,
    required this.noteId,
    required this.score,
  });

  final String documentId;
  final String noteId;
  final double score;
}

class SemanticIndexStats {
  const SemanticIndexStats({
    required this.documents,
    required this.engine,
    required this.dimensions,
  });

  final int documents;
  final String engine;
  final int dimensions;
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
            documentId TEXT NOT NULL PRIMARY KEY,
            noteId TEXT NOT NULL,
            kind TEXT NOT NULL,
            fingerprint TEXT NOT NULL,
            engine TEXT NOT NULL,
            dimensions INTEGER NOT NULL,
            vector BLOB NOT NULL,
            updatedAt INTEGER NOT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX index_semantic_note '
          'ON semantic_embeddings(noteId)',
        );
        await database.execute(
          'CREATE INDEX index_semantic_engine '
          'ON semantic_embeddings(engine, dimensions)',
        );
      },
    );
    _db = db;
    return db;
  }

  Future<void> syncDocuments(
    Iterable<RetrievalDocument> source,
    SemanticEmbeddingEngine engine,
  ) async {
    final documents = source
        .where(
          (document) =>
              document.id.trim().isNotEmpty &&
              document.noteId.trim().isNotEmpty &&
              _embeddingText(document).trim().isNotEmpty,
        )
        .toList(growable: false);
    if (documents.length > 50000) {
      throw const FormatException('Indice semantico troppo grande.');
    }

    final db = await database;
    final existingRows = await db.query(
      'semantic_embeddings',
      columns: ['documentId', 'fingerprint', 'engine', 'dimensions'],
    );
    final existing = <String, Map<String, Object?>>{
      for (final row in existingRows) row['documentId']! as String: row,
    };
    final liveIds = documents.map((document) => document.id).toSet();
    final changed = <({RetrievalDocument document, String fingerprint})>[];

    for (final document in documents) {
      final fingerprint = _fingerprint(document, engine);
      final row = existing[document.id];
      final unchanged = row != null &&
          row['fingerprint'] == fingerprint &&
          row['engine'] == engine.id &&
          row['dimensions'] == engine.dimensions;
      if (!unchanged) {
        changed.add((document: document, fingerprint: fingerprint));
      }
    }

    await db.transaction((txn) async {
      if (existing.isNotEmpty) {
        for (final id in existing.keys) {
          if (!liveIds.contains(id)) {
            await txn.delete(
              'semantic_embeddings',
              where: 'documentId = ?',
              whereArgs: [id],
            );
          }
        }
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      for (final entry in changed) {
        final vector = engine.embed(_embeddingText(entry.document));
        if (vector.length != engine.dimensions) {
          throw const FormatException('Vettore semantico non valido.');
        }
        await txn.insert(
          'semantic_embeddings',
          {
            'documentId': entry.document.id,
            'noteId': entry.document.noteId,
            'kind': entry.document.kind.name,
            'fingerprint': entry.fingerprint,
            'engine': engine.id,
            'dimensions': engine.dimensions,
            'vector': _encodeVector(vector),
            'updatedAt': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<SemanticMatch>> search(
    String query,
    SemanticEmbeddingEngine engine, {
    int limit = 80,
    Set<String> excludeNoteIds = const {},
  }) async {
    final queryVector = engine.embed(query);
    if (queryVector.every((value) => value == 0)) return const [];

    final db = await database;
    final rows = await db.query(
      'semantic_embeddings',
      columns: ['documentId', 'noteId', 'vector'],
      where: 'engine = ? AND dimensions = ?',
      whereArgs: [engine.id, engine.dimensions],
    );
    final matches = <SemanticMatch>[];
    for (final row in rows) {
      final noteId = row['noteId']?.toString() ?? '';
      if (noteId.isEmpty || excludeNoteIds.contains(noteId)) continue;
      final vector = _decodeVector(row['vector'], engine.dimensions);
      if (vector == null) continue;
      final score = LocalHashEmbeddingEngine.cosine(queryVector, vector);
      if (score < 0.10) continue;
      matches.add(
        SemanticMatch(
          documentId: row['documentId']?.toString() ?? '',
          noteId: noteId,
          score: score,
        ),
      );
    }
    matches.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      final note = a.noteId.compareTo(b.noteId);
      if (note != 0) return note;
      return a.documentId.compareTo(b.documentId);
    });
    return matches.take(limit.clamp(1, 200)).toList(growable: false);
  }

  Future<List<SemanticMatch>> related(
    RetrievalDocument source,
    SemanticEmbeddingEngine engine, {
    int limit = 60,
  }) async {
    final vector = engine.embed(_embeddingText(source));
    if (vector.every((value) => value == 0)) return const [];

    final db = await database;
    final rows = await db.query(
      'semantic_embeddings',
      columns: ['documentId', 'noteId', 'vector'],
      where: 'engine = ? AND dimensions = ? AND noteId != ?',
      whereArgs: [engine.id, engine.dimensions, source.noteId],
    );
    final matches = <SemanticMatch>[];
    for (final row in rows) {
      final candidate = _decodeVector(row['vector'], engine.dimensions);
      if (candidate == null) continue;
      final score = LocalHashEmbeddingEngine.cosine(vector, candidate);
      if (score < 0.12) continue;
      matches.add(
        SemanticMatch(
          documentId: row['documentId']?.toString() ?? '',
          noteId: row['noteId']?.toString() ?? '',
          score: score,
        ),
      );
    }
    matches.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      return a.documentId.compareTo(b.documentId);
    });
    return matches.take(limit.clamp(1, 200)).toList(growable: false);
  }

  Future<void> deleteForNote(String noteId) async {
    final db = await database;
    await db.delete(
      'semantic_embeddings',
      where: 'noteId = ?',
      whereArgs: [noteId],
    );
  }

  Future<void> clear() async {
    final db = await database;
    await db.delete('semantic_embeddings');
  }

  Future<SemanticIndexStats> stats(
    SemanticEmbeddingEngine engine,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM semantic_embeddings '
      'WHERE engine = ? AND dimensions = ?',
      [engine.id, engine.dimensions],
    );
    return SemanticIndexStats(
      documents: (rows.firstOrNull?['count'] as num?)?.toInt() ?? 0,
      engine: engine.id,
      dimensions: engine.dimensions,
    );
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }

  static String _embeddingText(RetrievalDocument document) {
    final parts = <String>[
      document.title,
      if (document.tags.isNotEmpty) document.tags.join(' '),
      document.text,
    ];
    return parts.join('\n').trim();
  }

  static String _fingerprint(
    RetrievalDocument document,
    SemanticEmbeddingEngine engine,
  ) {
    final payload = [
      engine.id,
      engine.dimensions.toString(),
      document.id,
      document.noteId,
      document.kind.name,
      document.updatedAt.toString(),
      _embeddingText(document),
    ].join('\u001f');
    return sha256.convert(utf8.encode(payload)).toString();
  }

  static Uint8List _encodeVector(List<double> vector) {
    final data = ByteData(vector.length * 4);
    for (var i = 0; i < vector.length; i++) {
      data.setFloat32(i * 4, vector[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static List<double>? _decodeVector(Object? raw, int dimensions) {
    if (raw is! Uint8List || raw.lengthInBytes != dimensions * 4) return null;
    final data = ByteData.sublistView(raw);
    return List<double>.generate(
      dimensions,
      (index) => data.getFloat32(index * 4, Endian.little),
      growable: false,
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
