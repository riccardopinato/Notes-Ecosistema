import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/documents.dart';
import 'package:notes_ecosistema/src/domain/knowledge_graph.dart';
import 'package:notes_ecosistema/src/domain/note.dart';
import 'package:notes_ecosistema/src/domain/project_workspace.dart';
import 'package:notes_ecosistema/src/domain/research.dart';
import 'package:notes_ecosistema/src/domain/study.dart';

void main() {
  const aId = '11111111-1111-4111-8111-111111111111';
  const bId = '22222222-2222-4222-8222-222222222222';

  Note note(String id, String title, String body) => Note(
        id: id,
        title: title,
        body: body,
        favorite: false,
        createdAt: 1,
        updatedAt: 2,
        pinned: false,
        archived: false,
        tags: const [],
      );

  test('graph derives canonical nodes and typed edges without new storage', () {
    final notes = [
      note(aId, 'Alpha', '[Beta](notes://object/$bId)'),
      note(bId, 'Beta', 'Contenuto'),
    ];
    const project = ProjectWorkspace(
      id: 'project-1',
      name: 'Project Alpha',
      description: '',
      createdAt: 1,
      updatedAt: 2,
    );
    const projectLink = ProjectItemLink(
      projectId: 'project-1',
      noteId: aId,
      position: 0,
      addedAt: 1,
      updatedAt: 2,
    );
    const study = LearningItem(
      id: 'study-1',
      sourceNoteId: bId,
      prompt: 'Che cos’è Beta?',
      answer: 'Una nota.',
      sourceSnapshot: 'Contenuto',
      sourceUpdatedAt: 2,
      createdAt: 1,
      updatedAt: 2,
    );
    const relation = NoteRelation(
      id: 'rel-1',
      sourceId: aId,
      targetId: bId,
      label: 'supports',
      updatedAt: 2,
    );
    const annotation = PdfAnnotation(
      id: 'pdf-1',
      noteId: aId,
      assetKey:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf',
      anchor: PdfAnchor(page: 1),
      kind: PdfAnnotationKind.comment,
      comment: 'Commento',
      createdAt: 1,
      updatedAt: 2,
    );

    final graph = KnowledgeGraph.build(
      const KnowledgeGraphBuildInput(
        notes: [],
        relations: [],
        projects: [],
        projectLinks: [],
        studyItems: [],
        pdfAnnotations: [],
      ).copyWithForTest(
        notes: notes,
        relations: const [relation],
        projects: const [project],
        projectLinks: const [projectLink],
        studyItems: const [study],
        pdfAnnotations: const [annotation],
      ),
    );

    expect(graph.nodes.where((node) => node.id == 'note:$aId'), hasLength(1));
    expect(graph.nodes.where((node) => node.id == 'note:$bId'), hasLength(1));
    expect(graph.nodes.any((node) => node.id == 'project:project-1'), isTrue);
    expect(graph.nodes.any((node) => node.id == 'study:study-1'), isTrue);
    expect(
      graph.nodes.any((node) => node.kind == KnowledgeGraphNodeKind.pdf),
      isTrue,
    );

    final kinds = graph.edges.map((edge) => edge.kind).toSet();
    expect(kinds, contains(KnowledgeGraphEdgeKind.link));
    expect(kinds, contains(KnowledgeGraphEdgeKind.relation));
    expect(kinds, contains(KnowledgeGraphEdgeKind.project));
    expect(kinds, contains(KnowledgeGraphEdgeKind.study));
    expect(kinds, contains(KnowledgeGraphEdgeKind.document));
  });

  test('focused projection is bounded and deterministic', () {
    final notes = [
      note(aId, 'Alpha', '[Beta](notes://object/$bId)'),
      note(bId, 'Beta', ''),
      note('33333333-3333-4333-8333-333333333333', 'Gamma', ''),
    ];
    final graph = KnowledgeGraph.build(
      KnowledgeGraphBuildInput(
        notes: notes,
        relations: const [],
        projects: const [],
        projectLinks: const [],
        studyItems: const [],
        pdfAnnotations: const [],
      ),
    );

    final first = KnowledgeGraphProjection.project(
      graph: graph,
      focusNodeId: 'note:$aId',
      scope: KnowledgeGraphScope.neighbors,
    );
    final second = KnowledgeGraphProjection.project(
      graph: graph,
      focusNodeId: 'note:$aId',
      scope: KnowledgeGraphScope.neighbors,
    );

    expect(first.nodes.map((node) => node.id).toSet(), {
      'note:$aId',
      'note:$bId',
    });
    expect(first.positions.keys.toSet(), second.positions.keys.toSet());
    expect(
      first.positions['note:$aId']!.x,
      second.positions['note:$aId']!.x,
    );
    expect(
      first.positions['note:$aId']!.y,
      second.positions['note:$aId']!.y,
    );
  });
}

extension on KnowledgeGraphBuildInput {
  KnowledgeGraphBuildInput copyWithForTest({
    List<Note>? notes,
    List<NoteRelation>? relations,
    List<ProjectWorkspace>? projects,
    List<ProjectItemLink>? projectLinks,
    List<LearningItem>? studyItems,
    List<PdfAnnotation>? pdfAnnotations,
  }) =>
      KnowledgeGraphBuildInput(
        notes: notes ?? this.notes,
        relations: relations ?? this.relations,
        projects: projects ?? this.projects,
        projectLinks: projectLinks ?? this.projectLinks,
        studyItems: studyItems ?? this.studyItems,
        pdfAnnotations: pdfAnnotations ?? this.pdfAnnotations,
      );
}
