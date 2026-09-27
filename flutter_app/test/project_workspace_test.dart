import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/planner.dart';
import 'package:notes_ecosistema/src/domain/project_workspace.dart';

void main() {
  Note note(String id, String title) => Note(
        id: id,
        title: title,
        body: 'Body $id',
        favorite: false,
        createdAt: 1,
        updatedAt: 2,
        pinned: false,
        archived: false,
        tags: const [],
      );

  Note task(
    String id, {
    String stage = 'TODO',
    String? due,
    String? plannedDate,
    String? plannedTime,
    int priority = 0,
    bool completed = false,
  }) {
    var details = TaskDetails.empty().copyWith(
      stage: stage,
      due: due,
      plannedDate: plannedDate,
      plannedTime: plannedTime,
      priority: priority,
    );
    if (completed) {
      details = details.toggleCompleted(
        completed: true,
        today: DateTime(2026, 9, 27),
        nowMillis: 1000,
      );
    }
    return Note(
      id: id,
      title: 'Task $id',
      body: '',
      favorite: false,
      createdAt: 1,
      updatedAt: 2,
      pinned: false,
      archived: false,
      tags: const [],
      taskJson: details.encode(),
    );
  }

  ProjectItemLink link(String noteId, int position) => ProjectItemLink(
        projectId: 'project-1',
        noteId: noteId,
        position: position,
        addedAt: 1,
        updatedAt: 2,
      );

  test('project lifecycle is metadata and does not own note content', () {
    const project = ProjectWorkspace(
      id: 'project-1',
      name: 'Project Alpha',
      description: 'Roadmap',
      createdAt: 10,
      updatedAt: 20,
    );

    final trashed = project.copyWith(deletedAt: 30);
    final restored = trashed.copyWith(deletedAt: null);

    expect(project.isActive, isTrue);
    expect(trashed.isDeleted, isTrue);
    expect(restored.isDeleted, isFalse);
    expect(restored.id, project.id);
  });

  test('universal views project the same canonical work items', () {
    final notes = [
      note('n1', 'Specifica'),
      task(
        't1',
        stage: 'DOING',
        due: '2026-09-29',
        priority: 3,
      ),
      task(
        't2',
        stage: 'TODO',
        plannedDate: '2026-09-28',
        plannedTime: '09:30',
      ),
    ];
    final links = [
      link('n1', 0),
      link('t1', 1),
      link('t2', 2),
    ];

    final items = ProjectWorkViews.project(notes: notes, links: links);
    final board = ProjectWorkViews.board(items);
    final calendar = ProjectWorkViews.calendar(items);
    final timeline = ProjectWorkViews.timeline(items);

    expect(items.map((item) => item.note.id), ['n1', 't1', 't2']);
    expect(board['REFERENCE']!.single.note.id, 'n1');
    expect(board['DOING']!.single.note.id, 't1');
    expect(board['TODO']!.single.note.id, 't2');
    expect(calendar['2026-09-28']!.single.note.id, 't2');
    expect(calendar['2026-09-29']!.single.note.id, 't1');
    expect(calendar['UNDATED']!.single.note.id, 'n1');
    expect(timeline.first.note.id, 't2');
    expect(timeline.last.note.id, 'n1');
  });

  test('completed task can be hidden without mutating the source', () {
    final source = task('done', completed: true);
    final visible = ProjectWorkViews.project(
      notes: [source],
      links: [link('done', 0)],
      showCompleted: false,
    );

    expect(visible, isEmpty);
    expect(source.taskCompleted, isTrue);
  });

  test('project search matches title body and tags', () {
    final tagged = note('n1', 'Specifiche').copyWith(tags: const ['backend']);
    final items = ProjectWorkViews.project(
      notes: [tagged],
      links: [link('n1', 0)],
      query: 'backend',
    );
    expect(items.single.note.id, 'n1');
  });

  test('project validation rejects empty names', () {
    expect(
      () => ProjectWorkspaceRules.validateProject(
        const ProjectWorkspace(
          id: 'project-1',
          name: '',
          description: '',
          createdAt: 1,
          updatedAt: 1,
        ),
      ),
      throwsFormatException,
    );
  });
}
