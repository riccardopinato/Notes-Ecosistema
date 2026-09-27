import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/project_workspace.dart';

class ProjectStore {
  Database? _db;

  Future<Database> get database async {
    final current = _db;
    if (current != null) return current;

    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'notes-projects.db'),
      version: 1,
      onConfigure: (database) async =>
          database.execute('PRAGMA foreign_keys=ON'),
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE projects (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT NOT NULL,
            sharedSpaceId TEXT,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL,
            archivedAt INTEGER,
            deletedAt INTEGER,
            preferredView TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE project_items (
            projectId TEXT NOT NULL,
            noteId TEXT NOT NULL,
            position INTEGER NOT NULL,
            addedAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL,
            PRIMARY KEY(projectId, noteId),
            FOREIGN KEY(projectId)
              REFERENCES projects(id)
              ON DELETE CASCADE
          )
        ''');
        await database.execute(
          'CREATE INDEX index_project_items_noteId '
          'ON project_items(noteId)',
        );
        await database.execute(
          'CREATE INDEX index_projects_updatedAt '
          'ON projects(updatedAt DESC)',
        );
      },
    );
    _db = db;
    return db;
  }

  Future<List<ProjectWorkspace>> loadProjects() async {
    final db = await database;
    final rows = await db.query(
      'projects',
      orderBy: 'updatedAt DESC, name COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(ProjectWorkspace.fromMap).toList(growable: false);
  }

  Future<ProjectWorkspace?> loadProject(String id) async {
    final db = await database;
    final rows = await db.query(
      'projects',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : ProjectWorkspace.fromMap(rows.single);
  }

  Future<ProjectWorkspace> createProject({
    required String name,
    String description = '',
    String? sharedSpaceId,
  }) async {
    final db = await database;
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM projects'),
        ) ??
        0;
    if (count >= ProjectWorkspaceRules.maxProjects) {
      throw const FormatException('Limite progetti raggiunto.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final project = ProjectWorkspace(
      id: const Uuid().v4(),
      name: name.trim(),
      description: description.trim(),
      sharedSpaceId:
          sharedSpaceId?.trim().isEmpty == true ? null : sharedSpaceId?.trim(),
      createdAt: now,
      updatedAt: now,
    );
    ProjectWorkspaceRules.validateProject(project);
    await db.insert('projects', project.toMap());
    return project;
  }

  Future<void> updateProject(ProjectWorkspace project) async {
    ProjectWorkspaceRules.validateProject(project);
    final db = await database;
    final next = project.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final changed = await db.update(
      'projects',
      next.toMap(),
      where: 'id = ?',
      whereArgs: [project.id],
    );
    if (changed != 1) {
      throw const FormatException('Progetto non trovato.');
    }
  }

  Future<void> setArchived(String id, bool value) async {
    final project = await _requireProject(id);
    if (project.isDeleted) {
      throw const FormatException(
        'Ripristina il progetto dal cestino prima di archiviarlo.',
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await updateProject(
      project.copyWith(
        archivedAt: value ? now : null,
        updatedAt: now,
      ),
    );
  }

  Future<void> trash(String id) async {
    final project = await _requireProject(id);
    if (project.isDeleted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await updateProject(
      project.copyWith(
        deletedAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> restore(String id) async {
    final project = await _requireProject(id);
    if (!project.isDeleted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await updateProject(
      project.copyWith(
        deletedAt: null,
        updatedAt: now,
      ),
    );
  }

  Future<void> deleteForever(String id) async {
    final project = await _requireProject(id);
    if (!project.isDeleted) {
      throw const FormatException(
        'Un progetto può essere eliminato definitivamente solo dal cestino.',
      );
    }
    final db = await database;
    final changed = await db.delete(
      'projects',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changed != 1) {
      throw const FormatException('Progetto non trovato.');
    }
  }

  Future<List<ProjectItemLink>> loadLinks(String projectId) async {
    final db = await database;
    final rows = await db.query(
      'project_items',
      where: 'projectId = ?',
      whereArgs: [projectId],
      orderBy: 'position ASC, addedAt ASC, noteId ASC',
    );
    return rows.map(ProjectItemLink.fromMap).toList(growable: false);
  }

  Future<void> attach(String projectId, String noteId) async {
    final project = await _requireProject(projectId);
    if (project.isDeleted) {
      throw const FormatException(
        'Non puoi aggiungere elementi a un progetto nel cestino.',
      );
    }
    final cleanNoteId = noteId.trim();
    if (cleanNoteId.isEmpty) {
      throw const FormatException('Elemento progetto non valido.');
    }

    final db = await database;
    final existing = await db.query(
      'project_items',
      where: 'projectId = ? AND noteId = ?',
      whereArgs: [projectId, cleanNoteId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    final count = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM project_items WHERE projectId = ?',
            [projectId],
          ),
        ) ??
        0;
    if (count >= ProjectWorkspaceRules.maxItemsPerProject) {
      throw const FormatException('Il progetto contiene troppi elementi.');
    }
    final maxPosition = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT MAX(position) FROM project_items WHERE projectId = ?',
            [projectId],
          ),
        ) ??
        -1;
    final now = DateTime.now().millisecondsSinceEpoch;
    final link = ProjectItemLink(
      projectId: projectId,
      noteId: cleanNoteId,
      position: maxPosition + 1,
      addedAt: now,
      updatedAt: now,
    );
    ProjectWorkspaceRules.validateLink(link);

    await db.transaction((txn) async {
      await txn.insert('project_items', link.toMap());
      await txn.update(
        'projects',
        {'updatedAt': now},
        where: 'id = ?',
        whereArgs: [projectId],
      );
    });
  }

  Future<void> detach(String projectId, String noteId) async {
    final project = await _requireProject(projectId);
    if (project.isDeleted) {
      throw const FormatException(
        'Ripristina il progetto prima di modificarne i contenuti.',
      );
    }
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete(
        'project_items',
        where: 'projectId = ? AND noteId = ?',
        whereArgs: [projectId, noteId],
      );
      await txn.update(
        'projects',
        {'updatedAt': now},
        where: 'id = ?',
        whereArgs: [projectId],
      );
    });
  }

  Future<void> deleteLinksForNote(String noteId) async {
    if (noteId.trim().isEmpty) return;
    final db = await database;
    await db.delete(
      'project_items',
      where: 'noteId = ?',
      whereArgs: [noteId],
    );
  }

  Future<ProjectWorkspaceSnapshot> snapshot() async {
    final db = await database;
    final projects = await loadProjects();
    final rows = await db.query(
      'project_items',
      orderBy: 'projectId ASC, position ASC, noteId ASC',
    );
    return ProjectWorkspaceSnapshot(
      projects: projects,
      links: rows.map(ProjectItemLink.fromMap).toList(growable: false),
    );
  }

  Future<Map<String, Object?>> exportBackup() async {
    final data = await snapshot();
    return {
      'version': 1,
      'projects': data.projects.map((item) => item.toMap()).toList(),
      'links': data.links.map((item) => item.toMap()).toList(),
    };
  }

  Future<void> importBackup(
    Map<String, Object?> payload, {
    required Map<String, String> noteIdMap,
  }) async {
    if (payload.isEmpty) return;
    if (payload['version'] != 1 ||
        payload['projects'] is! List ||
        payload['links'] is! List) {
      throw const FormatException('Backup progetti non valido.');
    }

    final rawProjects = payload['projects'] as List;
    final rawLinks = payload['links'] as List;
    if (rawProjects.length > ProjectWorkspaceRules.maxProjects ||
        rawLinks.length >
            ProjectWorkspaceRules.maxProjects *
                ProjectWorkspaceRules.maxItemsPerProject) {
      throw const FormatException('Backup progetti troppo grande.');
    }

    final sourceProjects = rawProjects.map((raw) {
      if (raw is! Map) {
        throw const FormatException('Progetto importato non valido.');
      }
      return ProjectWorkspace.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    }).toList(growable: false);

    final sourceLinks = rawLinks.map((raw) {
      if (raw is! Map) {
        throw const FormatException('Collegamento progetto non valido.');
      }
      return ProjectItemLink.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    }).toList(growable: false);

    final projectIdMap = <String, String>{
      for (final project in sourceProjects) project.id: const Uuid().v4(),
    };
    final validSourceIds = projectIdMap.keys.toSet();
    if (validSourceIds.length != sourceProjects.length) {
      throw const FormatException('Progetti duplicati nel backup.');
    }

    final db = await database;
    await db.transaction((txn) async {
      for (final source in sourceProjects) {
        final next = ProjectWorkspace(
          id: projectIdMap[source.id]!,
          name: source.name,
          description: source.description,
          sharedSpaceId: source.sharedSpaceId,
          createdAt: source.createdAt,
          updatedAt: source.updatedAt,
          archivedAt: source.archivedAt,
          deletedAt: source.deletedAt,
          preferredView: source.preferredView,
        );
        ProjectWorkspaceRules.validateProject(next);
        await txn.insert('projects', next.toMap());
      }

      final seen = <String>{};
      for (final source in sourceLinks) {
        final projectId = projectIdMap[source.projectId];
        final noteId = noteIdMap[source.noteId];
        if (projectId == null || noteId == null) continue;
        final key = '$projectId\u0000$noteId';
        if (!seen.add(key)) continue;
        final next = ProjectItemLink(
          projectId: projectId,
          noteId: noteId,
          position: source.position,
          addedAt: source.addedAt,
          updatedAt: source.updatedAt,
        );
        ProjectWorkspaceRules.validateLink(next);
        await txn.insert('project_items', next.toMap());
      }
    });
  }

  Future<ProjectWorkspace> _requireProject(String id) async {
    final project = await loadProject(id);
    if (project == null) {
      throw const FormatException('Progetto non trovato.');
    }
    return project;
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }
}
