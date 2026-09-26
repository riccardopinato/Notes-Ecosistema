import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/properties.dart';

class PropertyStore {
  Database? _db;

  Future<Database> get database async {
    final current = _db;
    if (current != null) return current;
    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'notes-metadata.db'),
      version: 1,
      onConfigure: (database) async =>
          database.execute('PRAGMA foreign_keys=ON'),
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE property_definitions (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL COLLATE NOCASE UNIQUE,
            type TEXT NOT NULL,
            optionsJson TEXT NOT NULL,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE property_values (
            noteId TEXT NOT NULL,
            definitionId TEXT NOT NULL,
            valueJson TEXT NOT NULL,
            updatedAt INTEGER NOT NULL,
            PRIMARY KEY(noteId, definitionId),
            FOREIGN KEY(definitionId)
              REFERENCES property_definitions(id)
              ON DELETE CASCADE
          )
        ''');
        await database.execute(
          'CREATE INDEX index_property_values_noteId '
          'ON property_values(noteId)',
        );
      },
    );
    _db = db;
    return db;
  }

  Future<List<PropertyDefinition>> loadDefinitions() async {
    final db = await database;
    final rows = await db.query(
      'property_definitions',
      orderBy: 'name COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(PropertyDefinition.fromMap).toList(growable: false);
  }

  Future<PropertyDefinition> createDefinition({
    required String name,
    required NotePropertyType type,
    List<String> options = const [],
  }) async {
    final db = await database;
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM property_definitions'),
        ) ??
        0;
    if (count >= PropertyRules.maxDefinitions) {
      throw const FormatException('Limite di 100 proprietà raggiunto.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final definition = PropertyDefinition(
      id: const Uuid().v4(),
      name: name.trim(),
      type: type,
      options: options.map((value) => value.trim()).toList(growable: false),
      createdAt: now,
      updatedAt: now,
    );
    PropertyRules.validateDefinition(definition);

    try {
      await db.insert(
        'property_definitions',
        definition.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const FormatException(
          'Esiste già una proprietà con questo nome.',
        );
      }
      rethrow;
    }
    return definition;
  }

  Future<void> updateDefinition(PropertyDefinition definition) async {
    PropertyRules.validateDefinition(definition);
    final db = await database;
    final changed = await db.update(
      'property_definitions',
      definition
          .copyWith(
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          )
          .toMap(),
      where: 'id = ?',
      whereArgs: [definition.id],
    );
    if (changed != 1) {
      throw const FormatException('Proprietà non trovata.');
    }
  }

  Future<Map<String, Object?>> loadValues(String noteId) async {
    if (noteId.trim().isEmpty) return const {};
    final db = await database;
    final definitions = {
      for (final item in await loadDefinitions()) item.id: item,
    };
    final rows = await db.query(
      'property_values',
      where: 'noteId = ?',
      whereArgs: [noteId],
      orderBy: 'definitionId ASC',
    );
    final result = <String, Object?>{};
    for (final row in rows) {
      final value = NotePropertyValue.fromMap(row);
      final definition = definitions[value.definitionId];
      if (definition == null) continue;
      result[value.definitionId] =
          PropertyRules.decodeValue(definition, value.valueJson);
    }
    return result;
  }

  Future<void> replaceValues(
    String noteId,
    List<PropertyDefinition> definitions,
    Map<String, Object?> values,
  ) async {
    if (noteId.trim().isEmpty) {
      throw const FormatException('Nota mancante per le proprietà.');
    }
    final byId = {
      for (final definition in definitions) definition.id: definition
    };
    for (final key in values.keys) {
      if (!byId.containsKey(key)) {
        throw const FormatException('Definizione proprietà mancante.');
      }
    }

    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete(
        'property_values',
        where: 'noteId = ?',
        whereArgs: [noteId],
      );
      for (final entry in values.entries) {
        final definition = byId[entry.key]!;
        final normalized = PropertyRules.normalizeValue(
          definition,
          entry.value,
        );
        if (normalized == null ||
            (normalized is List && normalized.isEmpty) ||
            (normalized is String && normalized.isEmpty)) {
          continue;
        }
        final value = NotePropertyValue(
          noteId: noteId,
          definitionId: definition.id,
          valueJson: PropertyRules.encodeValue(definition, normalized),
          updatedAt: now,
        );
        await txn.insert('property_values', value.toMap());
      }
    });
  }

  Future<void> deleteValuesForNote(String noteId) async {
    final db = await database;
    await db.delete(
      'property_values',
      where: 'noteId = ?',
      whereArgs: [noteId],
    );
  }

  Future<PropertySnapshot> snapshot() async {
    final db = await database;
    final definitions = await loadDefinitions();
    final rows = await db.query(
      'property_values',
      orderBy: 'noteId ASC, definitionId ASC',
    );
    return PropertySnapshot(
      definitions: definitions,
      values: rows.map(NotePropertyValue.fromMap).toList(growable: false),
    );
  }

  Future<Map<String, Object?>> exportBackup() async {
    final snapshot = await this.snapshot();
    return {
      'version': 1,
      'definitions':
          snapshot.definitions.map((item) => item.toMap()).toList(growable: false),
      'values':
          snapshot.values.map((item) => item.toMap()).toList(growable: false),
    };
  }

  Future<void> importBackup(
    Map<String, Object?> payload, {
    required Map<String, String> noteIdMap,
  }) async {
    if (payload.isEmpty) return;
    if (payload['version'] != 1 ||
        payload['definitions'] is! List ||
        payload['values'] is! List) {
      throw const FormatException('Backup proprietà non valido.');
    }
    final rawDefinitions = payload['definitions'] as List;
    final rawValues = payload['values'] as List;
    if (rawDefinitions.length > PropertyRules.maxDefinitions ||
        rawValues.length > 200000) {
      throw const FormatException('Backup proprietà troppo grande.');
    }

    final sourceDefinitions = rawDefinitions
        .map((raw) {
          if (raw is! Map) {
            throw const FormatException('Definizione proprietà non valida.');
          }
          return PropertyDefinition.fromMap(
            raw.map((key, value) => MapEntry(key.toString(), value)),
          );
        })
        .toList(growable: false);

    final definitionMap = <String, String>{};
    var current = await loadDefinitions();
    for (final source in sourceDefinitions) {
      final compatible = current.where(
        (item) =>
            item.name.toLowerCase() == source.name.toLowerCase() &&
            item.type == source.type &&
            item.options.join('\u0000') == source.options.join('\u0000'),
      );
      if (compatible.isNotEmpty) {
        definitionMap[source.id] = compatible.first.id;
        continue;
      }

      var name = source.name;
      var suffix = 1;
      while (current.any(
        (item) => item.name.toLowerCase() == name.toLowerCase(),
      )) {
        name = '${source.name} (importata $suffix)';
        suffix++;
      }
      final created = await createDefinition(
        name: name,
        type: source.type,
        options: source.options,
      );
      definitionMap[source.id] = created.id;
      current = [...current, created];
    }

    final targetDefinitions = {
      for (final definition in await loadDefinitions())
        definition.id: definition,
    };
    final db = await database;
    await db.transaction((txn) async {
      for (final raw in rawValues) {
        if (raw is! Map) {
          throw const FormatException('Valore proprietà non valido.');
        }
        final source = NotePropertyValue.fromMap(
          raw.map((key, value) => MapEntry(key.toString(), value)),
        );
        final noteId = noteIdMap[source.noteId];
        final definitionId = definitionMap[source.definitionId];
        if (noteId == null || definitionId == null) continue;
        final definition = targetDefinitions[definitionId];
        if (definition == null) {
          throw const FormatException('Definizione proprietà importata mancante.');
        }
        PropertyRules.decodeValue(definition, source.valueJson);
        await txn.insert(
          'property_values',
          NotePropertyValue(
            noteId: noteId,
            definitionId: definitionId,
            valueJson: source.valueJson,
            updatedAt: source.updatedAt,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
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
