import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/project_workspace.dart';
import 'package:notes_ecosistema/src/domain/smart_inbox_project_action.dart';

void main() {
  ProjectWorkspace project(String id,
          {String? sharedSpaceId, int? archivedAt, int? deletedAt}) =>
      ProjectWorkspace(
        id: id,
        name: id,
        description: '',
        createdAt: 1,
        updatedAt: 2,
        archivedAt: archivedAt,
        deletedAt: deletedAt,
        sharedSpaceId: sharedSpaceId,
      );

  Note note() => const Note(
        id: 'source-1',
        title: 'Fonte',
        body: 'Nota con #progetto',
        favorite: false,
        createdAt: 1,
        updatedAt: 2,
        pinned: false,
        archived: false,
        tags: [],
      );

  test('targets only active private projects, deduplicated and bounded', () {
    final eligible = SmartInboxProjectAction.privateTargets([
      project('a'),
      project('a'),
      project('shared', sharedSpaceId: 'space-1'),
      project('archived', archivedAt: 4),
      project('deleted', deletedAt: 5),
      project('b'),
    ]);
    expect(eligible.map((p) => p.id).toList(), ['a', 'b']);
    expect(
      () => SmartInboxProjectAction.validateTarget('shared', eligible),
      throwsFormatException,
    );
    expect(
      () => SmartInboxProjectAction.validateTarget('b', eligible).id,
      returnsNormally,
    );
  });

  test('stale, deleted, archived or duplicate source fails closed', () {
    final original = note();
    expect(SmartInboxProjectAction.validSource(original, [original]), isTrue);
    expect(
      SmartInboxProjectAction.validSource(original, [original, original]),
      isFalse,
    );
    expect(
      SmartInboxProjectAction.validSource(
        original,
        [original.copyWith(updatedAt: 3)],
      ),
      isFalse,
    );
    expect(
      SmartInboxProjectAction.validSource(
        original,
        [original.copyWith(archived: true)],
      ),
      isFalse,
    );
    expect(
      SmartInboxProjectAction.validSource(
        original,
        [original.copyWith(deletedAt: 12)],
      ),
      isFalse,
    );
  });

  test('undo only acts on exactly unchanged canonical project link', () {
    const written = ProjectItemLink(
      projectId: 'a',
      noteId: 'source-1',
      position: 2,
      addedAt: 100,
      updatedAt: 100,
    );
    expect(SmartInboxProjectAction.canUndo(written, written), isTrue);
    expect(
      SmartInboxProjectAction.canUndo(
        written,
        const ProjectItemLink(
          projectId: 'a',
          noteId: 'source-1',
          position: 2,
          addedAt: 100,
          updatedAt: 101,
        ),
      ),
      isFalse,
    );
  });
}
