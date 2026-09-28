import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/attachments.dart';
import '../domain/documents.dart';

class DocumentStore {
  Database? _db;

  Future<Database> get database async {
    final current = _db;
    if (current != null) return current;
    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'notes-documents.db'),
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE pdf_annotations (
            id TEXT NOT NULL PRIMARY KEY,
            noteId TEXT NOT NULL,
            assetKey TEXT NOT NULL,
            page INTEGER NOT NULL,
            x REAL,
            y REAL,
            width REAL,
            height REAL,
            kind TEXT NOT NULL,
            selectedText TEXT NOT NULL,
            comment TEXT NOT NULL,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX index_pdf_annotations_asset '
          'ON pdf_annotations(noteId, assetKey, page, createdAt)',
        );
      },
    );
    _db = db;
    return db;
  }

  Future<List<PdfAnnotation>> forAsset(
    String noteId,
    String assetKey,
  ) async {
    final db = await database;
    final rows = await db.query(
      'pdf_annotations',
      where: 'noteId = ? AND assetKey = ?',
      whereArgs: [noteId, assetKey],
      orderBy: 'page ASC, createdAt ASC, id ASC',
    );
    return rows.map(PdfAnnotation.fromMap).toList(growable: false);
  }

  Future<PdfAnnotation> add({
    required String noteId,
    required String assetKey,
    required PdfAnchor anchor,
    required PdfAnnotationKind kind,
    String selectedText = '',
    String comment = '',
  }) async {
    if (!Attachments.validKey(assetKey) ||
        Attachments.type(assetKey) != AttachmentType.pdf) {
      throw const FormatException('PDF non valido.');
    }
    final db = await database;
    final count = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM pdf_annotations '
            'WHERE noteId = ? AND assetKey = ?',
            [noteId, assetKey],
          ),
        ) ??
        0;
    if (count >= DocumentRules.maxAnnotationsPerAsset) {
      throw const FormatException('Limite annotazioni PDF raggiunto.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final item = PdfAnnotation(
      id: const Uuid().v4(),
      noteId: noteId,
      assetKey: assetKey,
      anchor: anchor,
      kind: kind,
      selectedText: selectedText.trim(),
      comment: comment.trim(),
      createdAt: now,
      updatedAt: now,
    );
    DocumentRules.validateAnnotation(item);
    await db.insert(
      'pdf_annotations',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return item;
  }

  Future<void> update(PdfAnnotation item) async {
    final next = PdfAnnotation(
      id: item.id,
      noteId: item.noteId,
      assetKey: item.assetKey,
      anchor: item.anchor,
      kind: item.kind,
      selectedText: item.selectedText,
      comment: item.comment,
      createdAt: item.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    DocumentRules.validateAnnotation(next);
    final db = await database;
    final changed = await db.update(
      'pdf_annotations',
      next.toMap(),
      where: 'id = ?',
      whereArgs: [next.id],
    );
    if (changed != 1) {
      throw const FormatException('Annotazione PDF non trovata.');
    }
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete('pdf_annotations', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteForNote(String noteId) async {
    final db = await database;
    await db.delete(
      'pdf_annotations',
      where: 'noteId = ?',
      whereArgs: [noteId],
    );
  }

  Future<Map<String, Object?>> exportBackup() async {
    final db = await database;
    return {
      'version': 1,
      'annotations': await db.query(
        'pdf_annotations',
        orderBy: 'createdAt ASC, id ASC',
      ),
    };
  }

  Future<void> restoreBackupExact(
    Map<String, Object?> payload, {
    required Set<String> noteIds,
    required Set<String> assetKeys,
  }) async {
    if (payload['version'] != 1 || payload['annotations'] is! List) {
      throw const FormatException('Backup documenti non valido.');
    }
    final raw = payload['annotations'] as List;
    if (raw.length > 200000) {
      throw const FormatException('Backup documenti troppo grande.');
    }
    final items = raw.map((value) {
      if (value is! Map) {
        throw const FormatException('Annotazione PDF non valida.');
      }
      final item = PdfAnnotation.fromMap(
        value.map((key, value) => MapEntry(key.toString(), value)),
      );
      DocumentRules.validateAnnotation(item);
      if (!noteIds.contains(item.noteId) ||
          !assetKeys.contains(item.assetKey) ||
          Attachments.type(item.assetKey) != AttachmentType.pdf) {
        throw const FormatException(
          'Annotazione PDF verso sorgente mancante.',
        );
      }
      return item;
    }).toList(growable: false);
    if (items.map((item) => item.id).toSet().length != items.length) {
      throw const FormatException('Annotazioni PDF duplicate.');
    }

    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('pdf_annotations');
      for (final item in items) {
        await txn.insert(
          'pdf_annotations',
          item.toMap(),
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
