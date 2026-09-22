import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/note.dart';

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
    await db.execute('CREATE TABLE IF NOT EXISTS collections (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL)');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS index_collections_name ON collections(name)');
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
    await db.execute('CREATE INDEX IF NOT EXISTS index_notes_collectionId ON notes(collectionId)');
    await db.execute('CREATE INDEX IF NOT EXISTS index_notes_deletedAt ON notes(deletedAt)');
    await db.execute('CREATE INDEX IF NOT EXISTS index_notes_updatedAt ON notes(updatedAt)');
    await db.execute("CREATE TABLE IF NOT EXISTS drafts (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL, collectionId TEXT, updatedAt INTEGER NOT NULL, tagsJson TEXT NOT NULL DEFAULT '[]')");
    await db.execute("CREATE TABLE IF NOT EXISTS note_revisions (revisionId TEXT NOT NULL PRIMARY KEY, noteId TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL, collectionId TEXT, savedAt INTEGER NOT NULL, tagsJson TEXT NOT NULL DEFAULT '[]')");
    await db.execute('CREATE INDEX IF NOT EXISTS index_note_revisions_noteId ON note_revisions(noteId)');
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
    await db.execute('CREATE INDEX IF NOT EXISTS index_content_blocks_ownerType_ownerId_position ON content_blocks(ownerType, ownerId, position)');
    await db.execute('CREATE INDEX IF NOT EXISTS index_content_blocks_ownerType_ownerId ON content_blocks(ownerType, ownerId)');
    await db.execute('CREATE INDEX IF NOT EXISTS index_content_blocks_parentBlockId ON content_blocks(parentBlockId)');
    await db.execute('CREATE INDEX IF NOT EXISTS index_content_blocks_type ON content_blocks(type)');

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
    final rows = await db.query('notes', orderBy: 'favorite DESC, pinned DESC, updatedAt DESC, id ASC');
    return rows.map(Note.fromMap).toList(growable: false);
  }

  Future<List<NoteCollection>> loadCollections() async {
    final db = await database;
    final rows = await db.query('collections', orderBy: 'name COLLATE NOCASE');
    return rows.map(NoteCollection.fromMap).toList(growable: false);
  }

  Future<Note?> loadNote(String id) async {
    final db = await database;
    final rows = await db.query('notes', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Note.fromMap(rows.first);
  }

  Future<void> saveNote(Note note) async {
    final db = await database;
    await db.insert('notes', note.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> createCollection(NoteCollection collection) async {
    final db = await database;
    await db.insert(
      'collections',
      {'id': collection.id, 'name': collection.name},
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> toggleFavorite(String id) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE notes SET favorite = CASE favorite WHEN 0 THEN 1 ELSE 0 END, updatedAt = ? WHERE id = ? AND deletedAt IS NULL',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  Future<void> setPinned(String id, bool pinned) async {
    final db = await database;
    await db.update('notes', {'pinned': pinned ? 1 : 0, 'updatedAt': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ? AND deletedAt IS NULL', whereArgs: [id]);
  }

  Future<void> trash(String id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update('notes', {'deletedAt': now, 'updatedAt': now},
        where: 'id = ? AND deletedAt IS NULL', whereArgs: [id]);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
