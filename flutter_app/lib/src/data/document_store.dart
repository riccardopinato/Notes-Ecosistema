import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/document_workspace.dart';

class DocumentStore {
  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final root = await getDatabasesPath();
    _db = await openDatabase(
      p.join(root, 'notes-documents.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE ocr_layers (
            noteId TEXT NOT NULL,
            assetKey TEXT NOT NULL,
            page INTEGER NOT NULL,
            originalText TEXT NOT NULL,
            correctedText TEXT,
            sourceFingerprint TEXT NOT NULL,
            updatedAt INTEGER NOT NULL,
            PRIMARY KEY(noteId, assetKey, page)
          )
        ''');
        await db.execute('''
          CREATE TABLE document_annotations (
            id TEXT NOT NULL PRIMARY KEY,
            noteId TEXT NOT NULL,
            assetKey TEXT NOT NULL,
            page INTEGER NOT NULL,
            kind TEXT NOT NULL,
            x REAL NOT NULL,
            y REAL NOT NULL,
            width REAL NOT NULL,
            height REAL NOT NULL,
            text TEXT NOT NULL,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX doc_ocr_note_idx ON ocr_layers(noteId, assetKey, page)',
        );
        await db.execute(
          'CREATE INDEX doc_annotation_note_idx ON document_annotations(noteId, assetKey, page)',
        );
      },
    );
    return _db!;
  }

  Future<List<DocumentOcrLayer>> ocrFor(
    String noteId,
    String assetKey,
  ) async {
    final db = await database;
    final rows = await db.query(
      'ocr_layers',
      where: 'noteId = ? AND assetKey = ?',
      whereArgs: [noteId, assetKey],
      orderBy: 'page ASC',
    );
    return rows.map(DocumentOcrLayer.fromMap).toList(growable: false);
  }

  Future<List<DocumentAnnotation>> annotationsFor(
    String noteId,
    String assetKey,
  ) async {
    final db = await database;
    final rows = await db.query(
      'document_annotations',
      where: 'noteId = ? AND assetKey = ?',
      whereArgs: [noteId, assetKey],
      orderBy: 'page ASC, createdAt ASC, id ASC',
    );
    return rows.map(DocumentAnnotation.fromMap).toList(growable: false);
  }

  Future<void> upsertOcr(DocumentOcrLayer layer) async {
    DocumentWorkspaceRules.validateOcr(layer);
    final db = await database;
    await db.insert(
      'ocr_layers',
      layer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> correctOcr({
    required String noteId,
    required String assetKey,
    required int page,
    required String correctedText,
  }) async {
    if (correctedText.length > DocumentWorkspaceRules.maxOcrCharsPerPage) {
      throw const FormatException('Correzione OCR troppo lunga.');
    }
    final db = await database;
    final changed = await db.update(
      'ocr_layers',
      {
        'correctedText': correctedText,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'noteId = ? AND assetKey = ? AND page = ?',
      whereArgs: [noteId, assetKey, page],
    );
    if (changed != 1) {
      throw const FormatException('Pagina OCR non trovata.');
    }
  }

  Future<DocumentAnnotation> addAnnotation({
    required String noteId,
    required String assetKey,
    required int page,
    required DocumentAnnotationKind kind,
    required double x,
    required double y,
    required double width,
    required double height,
    required String text,
  }) async {
    final existing = await annotationsFor(noteId, assetKey);
    if (existing.length >= DocumentWorkspaceRules.maxAnnotationsPerAsset) {
      throw const FormatException('Troppe annotazioni nel documento.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final annotation = DocumentAnnotation(
      id: const Uuid().v4(),
      noteId: noteId,
      assetKey: assetKey,
      page: page,
      kind: kind,
      x: x,
      y: y,
      width: width,
      height: height,
      text: text.trim(),
      createdAt: now,
      updatedAt: now,
    );
    DocumentWorkspaceRules.validateAnnotation(annotation);
    final db = await database;
    await db.insert('document_annotations', annotation.toMap());
    return annotation;
  }

  Future<void> deleteAnnotation(String id) async {
    final db = await database;
    await db.delete('document_annotations', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<DocumentSearchHit>> search(
    String query, {
    int limit = 100,
  }) async {
    final needle = query.trim();
    if (needle.isEmpty) return const [];
    final db = await database;
    final rows = await db.query(
      'ocr_layers',
      where: '(correctedText LIKE ? OR originalText LIKE ?)',
      whereArgs: ['%$needle%', '%$needle%'],
      orderBy: 'updatedAt DESC',
      limit: limit.clamp(1, 500),
    );
    return rows.map((row) {
      final layer = DocumentOcrLayer.fromMap(row);
      final text = layer.searchableText;
      final lower = text.toLowerCase();
      final at = lower.indexOf(needle.toLowerCase());
      final start = at < 0 ? 0 : (at - 60).clamp(0, text.length);
      final end = at < 0
          ? text.length.clamp(0, 180)
          : (at + needle.length + 120).clamp(0, text.length);
      return DocumentSearchHit(
        noteId: layer.noteId,
        assetKey: layer.assetKey,
        page: layer.page,
        snippet: text.substring(start, end),
      );
    }).toList(growable: false);
  }

  Future<void> deleteForNote(String noteId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('ocr_layers', where: 'noteId = ?', whereArgs: [noteId]);
      await txn.delete(
        'document_annotations',
        where: 'noteId = ?',
        whereArgs: [noteId],
      );
    });
  }

  Future<Map<String, Object?>> exportBackup() async {
    final db = await database;
    return {
      'version': 1,
      'ocr': await db.query(
        'ocr_layers',
        orderBy: 'noteId ASC, assetKey ASC, page ASC',
      ),
      'annotations': await db.query(
        'document_annotations',
        orderBy: 'noteId ASC, assetKey ASC, page ASC, id ASC',
      ),
    };
  }

  Future<void> restoreExact(
    Map<String, Object?> payload, {
    required Set<String> noteIds,
  }) async {
    if (payload['version'] != 1 ||
        payload['ocr'] is! List ||
        payload['annotations'] is! List) {
      throw const FormatException('Backup Document Workspace non valido.');
    }
    final ocr = (payload['ocr'] as List).map((raw) {
      if (raw is! Map) throw const FormatException('OCR non valido.');
      final layer = DocumentOcrLayer.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      DocumentWorkspaceRules.validateOcr(layer);
      if (!noteIds.contains(layer.noteId)) {
        throw const FormatException('OCR con nota mancante.');
      }
      return layer;
    }).toList(growable: false);
    final annotations = (payload['annotations'] as List).map((raw) {
      if (raw is! Map) throw const FormatException('Annotazione non valida.');
      final item = DocumentAnnotation.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      DocumentWorkspaceRules.validateAnnotation(item);
      if (!noteIds.contains(item.noteId)) {
        throw const FormatException('Annotazione con nota mancante.');
      }
      return item;
    }).toList(growable: false);

    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('document_annotations');
      await txn.delete('ocr_layers');
      for (final layer in ocr) {
        await txn.insert('ocr_layers', layer.toMap());
      }
      for (final item in annotations) {
        await txn.insert('document_annotations', item.toMap());
      }
    });
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }
}
