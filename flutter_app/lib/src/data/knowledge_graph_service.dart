import '../domain/documents.dart';
import '../domain/knowledge_graph.dart';
import '../domain/note.dart';
import '../domain/research.dart';
import 'document_store.dart';
import 'knowledge_store.dart';
import 'project_store.dart';
import 'study_store.dart';

class KnowledgeGraphService {
  const KnowledgeGraphService({
    required this.knowledgeStore,
    required this.projectStore,
    required this.studyStore,
    required this.documentStore,
  });

  final KnowledgeStore knowledgeStore;
  final ProjectStore projectStore;
  final StudyStore studyStore;
  final DocumentStore documentStore;

  Future<KnowledgeGraphSnapshot> load(List<Note> notes) async {
    final knowledge = await knowledgeStore.exportBackup();
    final projects = await projectStore.snapshot();
    final study = await studyStore.snapshot();
    final documents = await documentStore.exportBackup();

    final relations = _rows(knowledge['relations'])
        .map(NoteRelation.fromMap)
        .toList(growable: false);
    final annotations = _rows(documents['annotations'])
        .map(PdfAnnotation.fromMap)
        .toList(growable: false);

    return KnowledgeGraph.build(
      KnowledgeGraphBuildInput(
        notes: notes,
        relations: relations,
        projects: projects.projects,
        projectLinks: projects.links,
        studyItems: study.items,
        pdfAnnotations: annotations,
      ),
    );
  }

  static List<Map<String, Object?>> _rows(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((row) {
      return row.map((key, value) => MapEntry(key.toString(), value));
    }).toList(growable: false);
  }
}
