import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/research.dart';

class KnowledgeStore {
  Database? _db;

  Future<Database> get database async {
    final current = _db;
    if (current != null) return current;
    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'notes-knowledge.db'),
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE research_sources (
            id TEXT NOT NULL PRIMARY KEY,
            noteId TEXT NOT NULL,
            title TEXT NOT NULL,
            url TEXT,
            author TEXT,
            publishedAt TEXT,
            quote TEXT,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX index_research_sources_noteId '
          'ON research_sources(noteId)',
        );
        await database.execute('''
          CREATE TABLE note_relations (
            id TEXT NOT NULL PRIMARY KEY,
            sourceId TEXT NOT NULL,
            targetId TEXT NOT NULL,
            label TEXT NOT NULL,
            updatedAt INTEGER NOT NULL,
            UNIQUE(sourceId, targetId, label)
          )
        ''');
        await database.execute(
          'CREATE INDEX index_note_relations_source '
          'ON note_relations(sourceId)',
        );
        await database.execute(
          'CREATE INDEX index_note_relations_target '
          'ON note_relations(targetId)',
        );
        await database.execute('''
          CREATE TABLE synced_blocks (
            id TEXT NOT NULL PRIMARY KEY,
            markdown TEXT NOT NULL,
            updatedAt INTEGER NOT NULL
          )
        ''');
      },
    );
    _db = db;
    return db;
  }

  Future<List<ResearchSource>> sourcesFor(String noteId) async {
    final db = await database;
    final rows = await db.query(
      'research_sources',
      where: 'noteId = ?',
      whereArgs: [noteId],
      orderBy: 'updatedAt DESC, id ASC',
    );
    return rows.map(ResearchSource.fromMap).toList(growable: false);
  }

  Future<ResearchSource> addSource({
    required String noteId,
    required String title,
    String? url,
    String? author,
    String? publishedAt,
    String? quote,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final source = ResearchSource(
      id: const Uuid().v4(),
      noteId: noteId,
      title: title.trim(),
      url: _nullable(url),
      author: _nullable(author),
      publishedAt: _nullable(publishedAt),
      quote: _nullable(quote),
      createdAt: now,
      updatedAt: now,
    );
    ResearchRules.validateSource(source);
    final db = await database;
    await db.insert('research_sources', source.toMap());
    return source;
  }

  Future<void> deleteSource(String id) async {
    final db = await database;
    await db.delete('research_sources', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<NoteRelation>> relationsFor(String noteId) async {
    final db = await database;
    final rows = await db.query(
      'note_relations',
      where: 'sourceId = ? OR targetId = ?',
      whereArgs: [noteId, noteId],
      orderBy: 'updatedAt DESC, id ASC',
    );
    return rows.map(NoteRelation.fromMap).toList(growable: false);
  }

  Future<NoteRelation> addRelation({
    required String sourceId,
    required String targetId,
    String label = 'related',
  }) async {
    if (sourceId.trim().isEmpty ||
        targetId.trim().isEmpty ||
        sourceId == targetId ||
        label.trim().isEmpty ||
        label.length > 80) {
      throw const FormatException('Relazione non valida.');
    }
    final normalizedSource =
        sourceId.compareTo(targetId) <= 0 ? sourceId : targetId;
    final normalizedTarget =
        sourceId.compareTo(targetId) <= 0 ? targetId : sourceId;
    final relation = NoteRelation(
      id: const Uuid().v4(),
      sourceId: normalizedSource,
      targetId: normalizedTarget,
      label: label.trim(),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final db = await database;
    try {
      await db.insert('note_relations', relation.toMap());
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const FormatException('Relazione già presente.');
      }
      rethrow;
    }
    return relation;
  }

  Future<void> deleteRelation(String id) async {
    final db = await database;
    await db.delete('note_relations', where: 'id = ?', whereArgs: [id]);
  }

  Future<SyncedBlock> upsertSyncedBlock({
    String? id,
    required String markdown,
  }) async {
    if (markdown.trim().isEmpty || markdown.length > 200000) {
      throw const FormatException('Blocco sincronizzato non valido.');
    }
    final block = SyncedBlock(
      id: id ?? const Uuid().v4(),
      markdown: markdown,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final db = await database;
    await db.insert(
      'synced_blocks',
      block.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return block;
  }

  Future<Map<String, SyncedBlock>> syncedBlocks() async {
    final db = await database;
    final rows = await db.query('synced_blocks', orderBy: 'updatedAt DESC');
    return {
      for (final row in rows)
        SyncedBlock.fromMap(row).id: SyncedBlock.fromMap(row),
    };
  }

  Future<void> deleteForNote(String noteId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'research_sources',
        where: 'noteId = ?',
        whereArgs: [noteId],
      );
      await txn.delete(
        'note_relations',
        where: 'sourceId = ? OR targetId = ?',
        whereArgs: [noteId, noteId],
      );
    });
  }

  Future<Map<String, Object?>> exportBackup() async {
    final db = await database;
    return {
      'version': 1,
      'sources': await db.query(
        'research_sources',
        orderBy: 'updatedAt ASC, id ASC',
      ),
      'relations': await db.query(
        'note_relations',
        orderBy: 'updatedAt ASC, id ASC',
      ),
      'syncedBlocks': await db.query(
        'synced_blocks',
        orderBy: 'updatedAt ASC, id ASC',
      ),
    };
  }

  Future<Map<String, String>> importBackup(
    Map<String, Object?> payload, {
    required Map<String, String> noteIdMap,
  }) async {
    if (payload.isEmpty) return const {};
    if (payload['version'] != 1 ||
        payload['sources'] is! List ||
        payload['relations'] is! List ||
        payload['syncedBlocks'] is! List) {
      throw const FormatException('Backup knowledge non valido.');
    }
    final sources = payload['sources'] as List;
    final relations = payload['relations'] as List;
    final blocks = payload['syncedBlocks'] as List;
    if (sources.length > 100000 ||
        relations.length > 100000 ||
        blocks.length > 10000) {
      throw const FormatException('Backup knowledge troppo grande.');
    }

    for (final raw in sources) {
      if (raw is! Map) {
        throw const FormatException('Fonte knowledge non valida.');
      }
      final source = ResearchSource.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      ResearchRules.validateSource(source);
      final noteId = noteIdMap[source.noteId];
      if (noteId == null) continue;
      await addSource(
        noteId: noteId,
        title: source.title,
        url: source.url,
        author: source.author,
        publishedAt: source.publishedAt,
        quote: source.quote,
      );
    }

    for (final raw in relations) {
      if (raw is! Map) {
        throw const FormatException('Relazione knowledge non valida.');
      }
      final relation = NoteRelation.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      final sourceId = noteIdMap[relation.sourceId];
      final targetId = noteIdMap[relation.targetId];
      if (sourceId == null || targetId == null || sourceId == targetId) continue;
      try {
        await addRelation(
          sourceId: sourceId,
          targetId: targetId,
          label: relation.label,
        );
      } on FormatException catch (error) {
        if (!error.message.toString().contains('già presente')) rethrow;
      }
    }

    final blockMap = <String, String>{};
    for (final raw in blocks) {
      if (raw is! Map) {
        throw const FormatException('Synced Block non valido.');
      }
      final source = SyncedBlock.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (source.id.trim().isEmpty ||
          source.markdown.trim().isEmpty ||
          source.markdown.length > 200000) {
        throw const FormatException('Synced Block non valido.');
      }
      final created = await upsertSyncedBlock(markdown: source.markdown);
      blockMap[source.id.toLowerCase()] = created.id;
    }
    return Map.unmodifiable(blockMap);
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }

  static String? _nullable(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
