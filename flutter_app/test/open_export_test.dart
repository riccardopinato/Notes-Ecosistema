import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/backup.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/open_export.dart';

void main() {
  test('open export keeps human and machine-readable layers separate', () {
    final snapshot = BackupSnapshot(
      notes: const [
        Note(
          id: 'n1',
          title: 'Titolo',
          body: 'Corpo',
          favorite: false,
          createdAt: 1,
          updatedAt: 2,
          pinned: false,
          archived: false,
          tags: ['tag'],
        ),
      ],
      collections: const [],
      drafts: const [],
    );

    final bytes = OpenExportBundle.encodeLoaded(
      snapshot: snapshot,
      properties: const {'version': 1, 'definitions': [], 'values': []},
      knowledge: const {
        'version': 1,
        'sources': [],
        'relations': [],
        'syncedBlocks': [],
      },
      projects: const {'version': 1, 'projects': [], 'links': []},
      study: const {'version': 1, 'items': [], 'logs': []},
      documents: const {'version': 1, 'annotations': []},
      assets: const {},
    );

    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.map((entry) => entry.name).toSet();
    expect(names, contains('workspace.json'));
    expect(names, contains('properties.json'));
    expect(names, contains('knowledge.json'));
    expect(names, contains('projects.json'));
    expect(names, contains('study.json'));
    expect(names, contains('documents.json'));
    expect(names, contains('automations.json'));
    expect(names.any((name) => name.startsWith('notes/')), isTrue);
    expect(names, isNot(contains('revisions.json')));

    final manifestEntry =
        archive.firstWhere((entry) => entry.name == 'manifest.json');
    final manifest = jsonDecode(
      utf8.decode(manifestEntry.readBytes()!),
    ) as Map<String, dynamic>;
    expect(manifest['format'], OpenExportBundle.format);
    expect(manifest['excluded'], contains('revision-history'));
  });
}
