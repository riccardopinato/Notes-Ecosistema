import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notes_ecosistema/src/data/web_workspace_storage.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/workflow_automation.dart';

Note sample(String id, {String body = 'Text'}) => Note(
      id: id,
      title: 'My note $id',
      body: body,
      favorite: false,
      createdAt: 100,
      updatedAt: 101,
      pinned: false,
      archived: false,
      tags: const ['work'],
      taskJson: '{"due":"2026-11-11","priority":2}',
      sketchJson: '{"kind":"WHITEBOARD"}',
    );

Future<WebWorkspaceStore> store() async {
  final prefs = await SharedPreferences.getInstance();
  return WebWorkspaceStore(prefs);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Fresh browser starts empty, with no demo content', () async {
    final repo = await store();
    final snapshot = repo.load();
    expect(snapshot.notes, isEmpty);
    expect(snapshot.collections, isEmpty);
    expect(snapshot.rules, isEmpty);
  });

  test('Saves notes, tasks, sketches, collections and automations', () async {
    final repo = await store();
    repo.load();
    final snapshot = WebWorkspaceSnapshot(
      notes: [sample('one')],
      collections: const [NoteCollection(id: 'work', name: 'Lavoro')],
      rules: const [
        WorkflowRule(
          id: 'rule',
          name: 'Inbox',
          enabled: true,
          trigger: WorkflowTrigger.itemCreated,
          subject: WorkflowSubject.note,
          actionKind: WorkflowActionKind.addTag,
          actionValue: 'inbox',
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
      runs: const [],
    );
    await repo.save(snapshot);
    final refreshed = (await store()).load();
    expect(refreshed.notes.single.id, 'one');
    expect(refreshed.notes.single.taskJson, contains('2026-11-11'));
    expect(refreshed.notes.single.visualKind, VisualDocumentKind.whiteboard);
    expect(refreshed.collections.single.name, 'Lavoro');
    expect(refreshed.rules.single.id, 'rule');
  });

  test('Deletion and empty snapshot stay empty after refresh', () async {
    final repo = await store();
    repo.load();
    await repo.save(WebWorkspaceSnapshot.empty().copyWith(notes: [sample('one')]));
    await repo.save(WebWorkspaceSnapshot.empty());
    expect((await store()).load().notes, isEmpty);
  });

  test('Checksum failure restores previous acknowledged slot', () async {
    final repo = await store();
    repo.load();
    await repo.save(WebWorkspaceSnapshot.empty().copyWith(notes: [sample('a')]));
    await repo.save(WebWorkspaceSnapshot.empty().copyWith(notes: [sample('b')]));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notes.web.workspace.v1.b', '{"broken":true}');
    final recovered = await store();
    expect(recovered.load().notes.single.id, 'a');
    expect(recovered.recoveredPrevious, isTrue);
    await recovered.save(
      WebWorkspaceSnapshot.empty().copyWith(notes: [sample('c')]),
    );
    expect((await store()).load().notes.single.id, 'c');
  });

  test('Two invalid slots fail closed without seeding or overwriting', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notes.web.workspace.v1.a', 'damaged');
    await prefs.setString('notes.web.workspace.v1.b', 'damaged');
    expect(() => WebWorkspaceStore(prefs).load(), throwsFormatException);
    expect(prefs.getString('notes.web.workspace.v1.a'), 'damaged');
  });

  test('Export-import retains all document fields and rejects tampering', () {
    final original = WebWorkspaceSnapshot.empty().copyWith(
      notes: [sample('item', body: '# Important\n- [ ] One')],
    );
    final exported = WebWorkspaceStore.exportJson(original);
    final imported = WebWorkspaceStore.importJson(exported);
    expect(imported.notes.single.body, original.notes.single.body);
    expect(imported.notes.single.sketchJson, original.notes.single.sketchJson);
    expect(
      () => WebWorkspaceStore.importJson(
        exported.replaceFirst('Important', 'Altered'),
      ),
      throwsFormatException,
    );
  });

  test('Rejects conflicting IDs before a restore can replace records', () {
    final data = WebWorkspaceSnapshot.empty().copyWith(
      notes: [sample('repeat'), sample('repeat')],
    );
    expect(
      () => WebWorkspaceStore.importJson(WebWorkspaceStore.exportJson(data)),
      throwsFormatException,
    );
  });

  test('Size guard leaves prior journal state untouched', () async {
    final repo = await store();
    repo.load();
    await repo.save(WebWorkspaceSnapshot.empty().copyWith(notes: [sample('ok')]));
    final oversized = WebWorkspaceSnapshot.empty().copyWith(
      notes: [sample('huge', body: 'x' * WebWorkspaceStore.maxSnapshotBytes)],
    );
    await expectLater(repo.save(oversized), throwsStateError);
    expect((await store()).load().notes.single.id, 'ok');
  });
}
