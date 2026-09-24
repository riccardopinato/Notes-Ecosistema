import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';

void main() {
  test('reads Room v8 note row without data loss', () {
    final note = Note.fromMap({
      'id': 'n1',
      'title': 'Titolo',
      'body': 'Corpo',
      'collectionId': null,
      'favorite': 1,
      'createdAt': 10,
      'updatedAt': 20,
      'deletedAt': null,
      'pinned': 1,
      'archived': 0,
      'tagsJson': jsonEncode(['casa', 'idee']),
      'taskJson': null,
      'sketchJson': null,
    });

    expect(note.favorite, isTrue);
    expect(note.pinned, isTrue);
    expect(note.tags, ['casa', 'idee']);
    expect(note.toMap()['tagsJson'], jsonEncode(['casa', 'idee']));
  });

  test('detects 0.25 whiteboards while preserving legacy sketches', () {
    final base = {
      'id': 'v1',
      'title': '',
      'body': '{}',
      'collectionId': null,
      'favorite': 0,
      'createdAt': 10,
      'updatedAt': 20,
      'deletedAt': null,
      'pinned': 0,
      'archived': 0,
      'tagsJson': '[]',
      'taskJson': null,
    };

    expect(
        Note.fromMap({...base, 'sketchJson': '{"kind":"WHITEBOARD"}'})
            .visualKind,
        VisualDocumentKind.whiteboard);
    expect(Note.fromMap({...base, 'sketchJson': '{"version":2}'}).visualKind,
        VisualDocumentKind.sketch);
  });
}
