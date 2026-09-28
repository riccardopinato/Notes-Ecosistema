import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/backup.dart';
import '../domain/blocks.dart';
import '../domain/editing.dart';
import '../domain/library.dart';
import '../domain/note.dart';
import '../domain/planner.dart';
import '../domain/sync.dart';

class LegacyNotesDatabase {
  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'notes.db'),
      version: 8,
      onCreate: _createV8,
      onOpen: (database) async => database.execute('PRAGMA foreign_keys=ON'),
    );
    _db = db;
    return db;
  }

  Future<void> _createV8(Database db, int version) async {
    await db.execute(
        'CREATE TABLE IF NOT EXISTS collections (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS index_collections_name ON collections(name)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notes (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        collectionId TEXT,
        favorite INTEGER NOT NULL,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        deletedAt INTEGER,
        pinned INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0,
        tagsJson TEXT NOT NULL DEFAULT '[]',
        taskJson TEXT DEFAULT NULL,
        sketchJson TEXT DEFAULT NULL,
        FOREIGN KEY(collectionId) REFERENCES collections(id) ON UPDATE NO ACTION ON DELETE SET NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS index_notes_collectionId ON notes(collectionId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS index_notes_deletedAt ON notes(deletedAt)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS index_notes_updatedAt ON notes(updatedAt)');
    await db.execute(
        "CREATE TABLE IF NOT EXISTS drafts (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL, collectionId TEXT, updatedAt INTEGER NOT NULL, tagsJson TEXT NOT NULL DEFAULT '[]')");
    await db.execute(
        "CREATE TABLE IF NOT EXISTS note_revisions (revisionId TEXT NOT NULL PRIMARY KEY, noteId TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL, collectionId TEXT, savedAt INTEGER NOT NULL, tagsJson TEXT NOT NULL DEFAULT '[]')");
    await db.execute(
        'CREATE INDEX IF NOT EXISTS index_note_revisions_noteId ON note_revisions(noteId)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS content_blocks (
        id TEXT NOT NULL PRIMARY KEY,
        ownerId TEXT NOT NULL,
        ownerType TEXT NOT NULL,
        parentBlockId TEXT,
        position INTEGER NOT NULL,
        type TEXT NOT NULL,
        text TEXT NOT NULL,
        checked INTEGER,
        metadataJson TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS index_content_blocks_ownerType_ownerId_position ON content_blocks(ownerType, ownerId, position)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS index_content_blocks_ownerType_ownerId ON content_blocks(ownerType, ownerId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS index_content_blocks_parentBlockId ON content_blocks(parentBlockId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS index_content_blocks_type ON content_blocks(type)');

    // Keep databases created by Flutter valid for the canonical Kotlin Room v8 client.
    await db.execute(
      'CREATE TABLE IF NOT EXISTS room_master_table (id INTEGER PRIMARY KEY,identity_hash TEXT)',
    );
    await db.execute(
      "INSERT OR REPLACE INTO room_master_table (id,identity_hash) VALUES(42, 'c30a9f36c85605f785dca3d9557b5ed0')",
    );
  }

  Future<List<Note>> loadNotes() async {
    final db = await database;
    final rows = await db.query('notes',
        orderBy: 'favorite DESC, pinned DESC, updatedAt DESC, id ASC');
    return rows.map(Note.fromMap).toList(growable: false);
  }

  Future<List<NoteCollection>> loadCollections() async {
    final db = await database;
    final rows = await db.query('collections', orderBy: 'name COLLATE NOCASE');
    return rows.map(NoteCollection.fromMap).toList(growable: false);
  }

  Future<Note?> loadNote(String id) async {
    final db = await database;
    final rows =
        await db.query('notes', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Note.fromMap(rows.first);
  }

  Future<SyncDocument?> syncDocument(String id) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT n.*, c.name AS syncCollectionName '
      'FROM notes n '
      'LEFT JOIN collections c ON c.id = n.collectionId '
      'WHERE n.id = ? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return SyncDocument.fromNote(
      Note.fromMap(row),
      row['syncCollectionName']?.toString(),
    );
  }

  Future<void> saveNote(Note note) async {
    final db = await database;
    await db.transaction((txn) async {
      final currentRows = await txn.query(
        'notes',
        where: 'id = ?',
        whereArgs: [note.id],
        limit: 1,
      );
      final old = currentRows.isEmpty ? null : Note.fromMap(currentRows.first);

      if (old != null &&
          !old.isTask &&
          !old.isVisual &&
          !note.isTask &&
          !note.isVisual) {
        final latest = await txn.query(
          'note_revisions',
          where: 'noteId = ?',
          whereArgs: [old.id],
          orderBy: 'savedAt DESC, revisionId DESC',
          limit: 1,
        );
        final oldTags = old.toMap()['tagsJson'];
        final alreadyPreserved = latest.isNotEmpty &&
            latest.first['title'] == old.title &&
            latest.first['body'] == old.body &&
            latest.first['collectionId'] == old.collectionId &&
            latest.first['tagsJson'] == oldTags;

        if (!alreadyPreserved) {
          await txn.insert('note_revisions', {
            'revisionId': const Uuid().v4(),
            'noteId': old.id,
            'title': old.title,
            'body': old.body,
            'collectionId': old.collectionId,
            'savedAt': DateTime.now().millisecondsSinceEpoch,
            'tagsJson': oldTags,
          });
          await txn.rawDelete(
            'DELETE FROM note_revisions '
            'WHERE noteId = ? AND revisionId NOT IN ('
            'SELECT revisionId FROM note_revisions '
            'WHERE noteId = ? '
            'ORDER BY savedAt DESC, revisionId DESC LIMIT 50'
            ')',
            [old.id, old.id],
          );
        }
      }

      await txn.insert(
        'notes',
        note.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('drafts', where: 'id = ?', whereArgs: [note.id]);
    });
  }

  Future<List<Map<String, Object?>>> loadHistory(String noteId) async {
    final db = await database;
    return db.query(
      'note_revisions',
      where: 'noteId = ?',
      whereArgs: [noteId],
      orderBy: 'savedAt DESC, revisionId DESC',
      limit: 50,
    );
  }

  Future<List<ContentBlock>> loadNoteBlocks(String noteId) async {
    final db = await database;
    final rows = await db.query(
      'content_blocks',
      where: 'ownerType = ? AND ownerId = ?',
      whereArgs: ['note', noteId],
      orderBy: 'position ASC, id ASC',
    );
    return rows.map(ContentBlock.fromMap).toList(growable: false);
  }

  Future<List<ContentBlock>> replaceNoteBlocks(
    String noteId,
    List<ContentBlock> source,
  ) async {
    final db = await database;
    final normalized = ContentBlocks.normalize(noteId, source);
    await db.transaction((txn) async {
      final rows = await txn.query(
        'notes',
        columns: ['id', 'deletedAt', 'taskJson', 'sketchJson'],
        where: 'id = ?',
        whereArgs: [noteId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const FormatException('Nota non trovata.');
      }
      final row = rows.first;
      if (row['deletedAt'] != null) {
        throw const FormatException(
          'Ripristina la nota prima di modificarla.',
        );
      }
      if (row['taskJson'] != null || row['sketchJson'] != null) {
        throw const FormatException(
          'I blocchi sono disponibili solo per le note di testo.',
        );
      }

      final batch = txn.batch()
        ..delete(
          'content_blocks',
          where: 'ownerType = ? AND ownerId = ?',
          whereArgs: ['note', noteId],
        );
      for (final block in normalized) {
        batch.insert(
          'content_blocks',
          block.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
    return normalized;
  }

  Future<void> clearNoteBlocks(String noteId) async {
    final db = await database;
    await db.delete(
      'content_blocks',
      where: 'ownerType = ? AND ownerId = ?',
      whereArgs: ['note', noteId],
    );
  }

  Future<BackupDraft?> loadDraft(String id) async {
    final db = await database;
    final rows = await db.query(
      'drafts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return BackupDraft(
      id: row['id']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
      body: row['body']?.toString() ?? '',
      collectionId: row['collectionId']?.toString(),
      updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
      tags: _decodeTags(row['tagsJson']?.toString()),
    );
  }

  Future<void> saveDraft(BackupDraft draft) async {
    if (draft.id.trim().isEmpty || draft.id.length > 200) {
      throw const FormatException('Bozza non valida.');
    }
    final tags = NoteTags.normalize(draft.tags);
    final db = await database;
    await db.transaction((txn) async {
      final noteRows = await txn.query(
        'notes',
        columns: ['deletedAt', 'archived'],
        where: 'id = ?',
        whereArgs: [draft.id],
        limit: 1,
      );
      if (noteRows.isNotEmpty) {
        if (noteRows.first['deletedAt'] != null ||
            (noteRows.first['archived'] as num?)?.toInt() == 1) {
          throw const FormatException(
            'La nota non è modificabile mentre è archiviata o nel cestino.',
          );
        }
      }
      if (draft.collectionId != null) {
        final collections = await txn.query(
          'collections',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [draft.collectionId],
          limit: 1,
        );
        if (collections.isEmpty) {
          throw const FormatException('Raccolta non più disponibile.');
        }
      }
      await txn.insert(
        'drafts',
        {
          'id': draft.id,
          'title': draft.title,
          'body': draft.body,
          'collectionId': draft.collectionId,
          'updatedAt': draft.updatedAt,
          'tagsJson': jsonEncode(tags),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> discardDraft(String id) async {
    final db = await database;
    await db.delete('drafts', where: 'id = ?', whereArgs: [id]);
  }

  Future<BackupSnapshot> snapshot() async {
    final db = await database;
    final notes = await loadNotes();
    final collections = await loadCollections();
    final rows = await db.query('drafts', orderBy: 'updatedAt DESC, id ASC');
    final drafts = rows
        .map(
          (row) => BackupDraft(
            id: row['id']?.toString() ?? '',
            title: row['title']?.toString() ?? '',
            body: row['body']?.toString() ?? '',
            collectionId: row['collectionId']?.toString(),
            updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
            tags: _decodeTags(row['tagsJson']?.toString()),
          ),
        )
        .toList(growable: false);
    return BackupSnapshot(
      notes: notes,
      collections: collections,
      drafts: drafts,
    );
  }

  Future<Map<String, Object?>> exportRecoveryState() async {
    final db = await database;
    return {
      'version': 1,
      'collections': await db.query('collections', orderBy: 'id ASC'),
      'notes': await db.query('notes', orderBy: 'id ASC'),
      'drafts': await db.query('drafts', orderBy: 'id ASC'),
      'revisions': await db.query(
        'note_revisions',
        orderBy: 'noteId ASC, savedAt ASC, revisionId ASC',
      ),
      'contentBlocks': await db.query(
        'content_blocks',
        orderBy: 'ownerType ASC, ownerId ASC, position ASC, id ASC',
      ),
    };
  }

  Future<void> restoreRecoveryState(Map<String, Object?> payload) async {
    if (payload['version'] != 1 ||
        payload['collections'] is! List ||
        payload['notes'] is! List ||
        payload['drafts'] is! List ||
        payload['revisions'] is! List ||
        payload['contentBlocks'] is! List) {
      throw const FormatException('Backup workspace non valido.');
    }

    Map<String, Object?> row(Object? raw, String label) {
      if (raw is! Map) {
        throw FormatException('$label non valido.');
      }
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }

    final collections = (payload['collections'] as List)
        .map((raw) => row(raw, 'Raccolta'))
        .toList(growable: false);
    final notes = (payload['notes'] as List)
        .map((raw) => row(raw, 'Nota'))
        .toList(growable: false);
    final drafts = (payload['drafts'] as List)
        .map((raw) => row(raw, 'Bozza'))
        .toList(growable: false);
    final revisions = (payload['revisions'] as List)
        .map((raw) => row(raw, 'Revisione'))
        .toList(growable: false);
    final blocks = (payload['contentBlocks'] as List)
        .map((raw) => row(raw, 'Blocco'))
        .toList(growable: false);

    if (notes.length > 10000 ||
        collections.length > 10000 ||
        drafts.length > 10000 ||
        revisions.length > 500000 ||
        blocks.length > 200000) {
      throw const FormatException('Backup workspace troppo grande.');
    }

    final collectionIds = <String>{};
    final collectionModels = <NoteCollection>[];
    for (final value in collections) {
      final id = value['id']?.toString() ?? '';
      final name = value['name']?.toString() ?? '';
      if (id.trim().isEmpty || name.trim().isEmpty || !collectionIds.add(id)) {
        throw const FormatException('Raccolta backup non valida.');
      }
      collectionModels.add(NoteCollection(id: id, name: name));
    }

    final noteModels = notes.map(Note.fromMap).toList(growable: false);
    final noteIds = noteModels.map((note) => note.id).toSet();
    if (noteIds.length != noteModels.length ||
        noteModels.any(
          (note) =>
              note.id.trim().isEmpty ||
              (note.collectionId != null &&
                  !collectionIds.contains(note.collectionId)),
        )) {
      throw const FormatException('Note backup non valide.');
    }

    final draftModels = drafts.map((value) {
      final id = value['id']?.toString() ?? '';
      final updatedAt = (value['updatedAt'] as num?)?.toInt() ?? -1;
      final collectionId = value['collectionId']?.toString();
      if (id.trim().isEmpty ||
          updatedAt < 0 ||
          (collectionId != null && !collectionIds.contains(collectionId))) {
        throw const FormatException('Bozza backup non valida.');
      }
      return BackupDraft(
        id: id,
        title: value['title']?.toString() ?? '',
        body: value['body']?.toString() ?? '',
        collectionId: collectionId,
        updatedAt: updatedAt,
        tags: _decodeTags(value['tagsJson']?.toString()),
      );
    }).toList(growable: false);

    BackupCodec.validate(
      BackupSnapshot(
        notes: noteModels,
        collections: collectionModels,
        drafts: draftModels,
      ),
    );

    final revisionIds = <String>{};
    for (final value in revisions) {
      final id = value['revisionId']?.toString() ?? '';
      final noteId = value['noteId']?.toString() ?? '';
      final savedAt = (value['savedAt'] as num?)?.toInt() ?? -1;
      if (id.trim().isEmpty ||
          !revisionIds.add(id) ||
          !noteIds.contains(noteId) ||
          savedAt < 0) {
        throw const FormatException('Revisione backup non valida.');
      }
    }

    final blockIds = <String>{};
    for (final value in blocks) {
      final model = ContentBlock.fromMap(value);
      ContentBlocks.validate(model);
      if (!blockIds.add(model.id) ||
          model.ownerType != 'note' ||
          !noteIds.contains(model.ownerId)) {
        throw const FormatException('Blocco backup non valido.');
      }
    }

    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('content_blocks');
      await txn.delete('note_revisions');
      await txn.delete('drafts');
      await txn.delete('notes');
      await txn.delete('collections');

      for (final value in collections) {
        await txn.insert(
          'collections',
          value,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      for (final value in notes) {
        await txn.insert(
          'notes',
          value,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      for (final value in drafts) {
        await txn.insert(
          'drafts',
          value,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      for (final value in revisions) {
        await txn.insert(
          'note_revisions',
          value,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      for (final value in blocks) {
        await txn.insert(
          'content_blocks',
          value,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });
  }

  Future<Set<String>> syncDocumentIds() async {
    final db = await database;
    final rows = await db.query('notes', columns: ['id']);
    return rows
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<Map<String, SyncDocument>> syncDocuments() async {
    final notes = await loadNotes();
    final collections = await loadCollections();
    final names = {
      for (final collection in collections) collection.id: collection.name,
    };
    return {
      for (final note in notes)
        note.id: SyncDocument.fromNote(note, names[note.collectionId]),
    };
  }

  Future<void> applySyncDocument(SyncDocument document) async {
    final db = await database;

    final drafts = await db.query(
      'drafts',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [document.id],
      limit: 1,
    );
    if (drafts.isNotEmpty) {
      throw const FormatException(
        'La nota ha una bozza locale: salvala o scartala prima del sync.',
      );
    }

    String? collectionId;
    if (document.collection != null) {
      final rows = await db.query(
        'collections',
        where: 'name = ?',
        whereArgs: [document.collection],
        limit: 1,
      );
      if (rows.isEmpty) {
        collectionId = const Uuid().v4();
        await createCollection(
          NoteCollection(
            id: collectionId,
            name: document.collection!,
          ),
        );
      } else {
        collectionId = rows.first['id']?.toString();
      }
    }

    await saveNote(
      Note(
        id: document.id,
        title: document.title,
        body: document.body,
        collectionId: collectionId,
        favorite: document.favorite,
        createdAt: document.createdAt,
        updatedAt: document.updatedAt,
        deletedAt: document.deletedAt,
        pinned: document.pinned,
        archived: document.archived,
        tags: document.tags,
        taskJson: document.taskJson,
        sketchJson: document.sketchJson,
      ),
    );
  }

  Future<String> saveSyncCopy(
    SyncDocument source, {
    String suffix = ' (copia locale)',
  }) async {
    final id = const Uuid().v4();
    await applySyncDocument(
      SyncDocument(
        id: id,
        title: '${source.title}$suffix',
        body: source.body,
        collection: source.collection,
        favorite: source.favorite,
        createdAt: source.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        deletedAt: null,
        pinned: source.pinned,
        archived: source.archived,
        tags: source.tags,
        taskJson: source.taskJson,
        sketchJson: source.sketchJson,
      ),
    );
    return id;
  }

  Future<BackupImportPlan> importCopies(BackupSnapshot snapshot) async {
    final db = await database;
    final existing = await loadCollections();
    final plan = BackupImport.asCopies(
      snapshot,
      existingCollectionNames: existing.map((item) => item.name).toSet(),
      newId: () => const Uuid().v4(),
    );

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final collection in plan.collections) {
        batch.insert(
          'collections',
          {'id': collection.id, 'name': collection.name},
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      for (final note in plan.notes) {
        batch.insert(
          'notes',
          note.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      for (final draft in plan.drafts) {
        batch.insert(
          'drafts',
          {
            'id': draft.id,
            'title': draft.title,
            'body': draft.body,
            'collectionId': draft.collectionId,
            'updatedAt': draft.updatedAt,
            'tagsJson': jsonEncode(draft.tags),
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      await batch.commit(noResult: true);
    });
    return plan;
  }

  Future<void> createCollection(NoteCollection collection) async {
    final db = await database;
    await db.insert(
      'collections',
      {'id': collection.id, 'name': collection.name},
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<int> bulkEdit(
    List<Note> expected,
    BulkChange change,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final planned = planBulkEdit(expected, change, now);
    final db = await database;
    return db.transaction((txn) async {
      final ids = expected.map((note) => note.id).toList(growable: false);
      final placeholders = List.filled(ids.length, '?').join(',');
      final currentRows = await txn.query(
        'notes',
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );
      final currentById = <String, Note>{
        for (final row in currentRows)
          if (row['id'] != null) row['id'].toString(): Note.fromMap(row),
      };
      if (currentById.length != expected.length) {
        throw const FormatException(
          'Una nota non è più disponibile. Aggiorna la selezione.',
        );
      }

      for (final before in expected) {
        final actual = currentById[before.id];
        if (actual == null ||
            actual.updatedAt != before.updatedAt ||
            actual.deletedAt != before.deletedAt ||
            actual.collectionId != before.collectionId ||
            actual.tags.toString() != before.tags.toString()) {
          throw const FormatException(
            'Una nota è cambiata. Aggiorna la selezione e riprova.',
          );
        }
      }

      final batch = txn.batch();
      for (var index = 0; index < expected.length; index++) {
        batch.update(
          'notes',
          planned[index].toMap(),
          where: 'id = ?',
          whereArgs: [expected[index].id],
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      await batch.commit(noResult: true);
      return planned.length;
    });
  }

  Future<void> renameCollection(
    NoteCollection expected,
    String rawName,
  ) async {
    final name = rawName.trim();
    if (name.isEmpty || name.length > 120) {
      throw const FormatException('Usa un nome di 1–120 caratteri.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final current = await txn.query(
        'collections',
        where: 'id = ?',
        whereArgs: [expected.id],
        limit: 1,
      );
      if (current.isEmpty ||
          current.first['name']?.toString() != expected.name) {
        throw const FormatException(
          'La raccolta è cambiata. Riapri la gestione raccolte.',
        );
      }
      final duplicate = await txn.query(
        'collections',
        columns: ['id'],
        where: 'lower(name) = lower(?) AND id != ?',
        whereArgs: [name, expected.id],
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        throw const FormatException(
          'Esiste già una raccolta con questo nome.',
        );
      }
      await txn.update(
        'collections',
        {'name': name},
        where: 'id = ?',
        whereArgs: [expected.id],
      );
    });
  }

  Future<void> deleteEmptyCollection(NoteCollection expected) async {
    final db = await database;
    await db.transaction((txn) async {
      final current = await txn.query(
        'collections',
        where: 'id = ?',
        whereArgs: [expected.id],
        limit: 1,
      );
      if (current.isEmpty ||
          current.first['name']?.toString() != expected.name) {
        throw const FormatException(
          'La raccolta è cambiata. Riapri la gestione raccolte.',
        );
      }
      final notes = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM notes WHERE collectionId = ?',
              [expected.id],
            ),
          ) ??
          0;
      final drafts = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM drafts WHERE collectionId = ?',
              [expected.id],
            ),
          ) ??
          0;
      final revisions = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM note_revisions WHERE collectionId = ?',
              [expected.id],
            ),
          ) ??
          0;
      if (notes + drafts + revisions != 0) {
        throw const FormatException(
          'Puoi eliminare solo raccolte completamente vuote.',
        );
      }
      await txn.delete(
        'collections',
        where: 'id = ?',
        whereArgs: [expected.id],
      );
    });
  }

  Future<bool> snoozeReminder(
    String id,
    int expectedAt,
    int nextAt,
  ) async {
    if (id.trim().isEmpty || nextAt <= expectedAt) return false;
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'notes',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final note = Note.fromMap(rows.first);
      final task = TaskDetails.tryDecode(note.taskJson);
      if (task == null ||
          note.isDeleted ||
          note.archived ||
          task.completed ||
          task.reminderAt != expectedAt) {
        return false;
      }
      final drafts = await txn.query(
        'drafts',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (drafts.isNotEmpty) return false;

      final old = DateTime.fromMillisecondsSinceEpoch(expectedAt);
      final fallbackTime =
          '${old.hour.toString().padLeft(2, '0')}:${old.minute.toString().padLeft(2, '0')}';
      final updated = task.copyWith(
        reminderAt: nextAt,
        reminderTime: task.reminderTime ?? fallbackTime,
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      final changed = await txn.update(
        'notes',
        {
          'taskJson': updated.encode(),
          'updatedAt': now,
        },
        where: 'id = ? AND updatedAt = ?',
        whereArgs: [id, note.updatedAt],
      );
      return changed == 1;
    });
  }

  Future<void> toggleFavorite(String id) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE notes SET favorite = CASE favorite WHEN 0 THEN 1 ELSE 0 END, updatedAt = ? WHERE id = ? AND deletedAt IS NULL',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  Future<void> setArchived(String id, bool archived) async {
    final db = await database;
    final rows = await db.query(
      'notes',
      columns: ['deletedAt'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const FormatException('Nota non trovata.');
    }
    if (rows.first['deletedAt'] != null) {
      throw const FormatException('La nota è nel cestino.');
    }
    await db.update(
      'notes',
      {
        'archived': archived ? 1 : 0,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setPinned(String id, bool pinned) async {
    final db = await database;
    await db.update(
        'notes',
        {
          'pinned': pinned ? 1 : 0,
          'updatedAt': DateTime.now().millisecondsSinceEpoch
        },
        where: 'id = ? AND deletedAt IS NULL',
        whereArgs: [id]);
  }

  Future<void> trash(String id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final changed = await txn.update(
        'notes',
        {'deletedAt': now, 'updatedAt': now},
        where: 'id = ? AND deletedAt IS NULL',
        whereArgs: [id],
      );
      if (changed == 0) return;
      await txn.delete('drafts', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> restore(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'notes',
        columns: ['deletedAt'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const FormatException('Elemento non trovato.');
      }
      if (rows.first['deletedAt'] == null) {
        throw const FormatException('L’elemento non è nel cestino.');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.update(
        'notes',
        {'deletedAt': null, 'updatedAt': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<Note> deleteForever(String id) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'notes',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const FormatException('Elemento non trovato.');
      }
      final note = Note.fromMap(rows.first);
      if (!note.isDeleted) {
        throw const FormatException(
          'Sposta prima l’elemento nel cestino.',
        );
      }

      await txn.delete('drafts', where: 'id = ?', whereArgs: [id]);
      await txn.delete(
        'note_revisions',
        where: 'noteId = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'content_blocks',
        where: 'ownerType = ? AND ownerId = ?',
        whereArgs: ['note', id],
      );
      final removed = await txn.delete(
        'notes',
        where: 'id = ? AND deletedAt IS NOT NULL',
        whereArgs: [id],
      );
      if (removed != 1) {
        throw const FormatException(
          'L’elemento è cambiato. Aggiorna il cestino e riprova.',
        );
      }
      return note;
    });
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static List<String> _decodeTags(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((item) => item.toString()).toList(growable: false);
      }
    } catch (_) {}
    return const [];
  }
}
