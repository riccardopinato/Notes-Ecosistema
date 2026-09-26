import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/project_store.dart';
import '../domain/project_workspace.dart';

final projectStoreProvider = Provider<ProjectStore>((ref) {
  final store = ProjectStore();
  ref.onDispose(store.close);
  return store;
});

class ProjectWorkspaceState {
  const ProjectWorkspaceState({
    this.projects = const [],
    this.loading = true,
    this.error,
  });

  final List<ProjectWorkspace> projects;
  final bool loading;
  final Object? error;

  ProjectWorkspace? byId(String id) {
    for (final project in projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  ProjectWorkspaceState copyWith({
    List<ProjectWorkspace>? projects,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) =>
      ProjectWorkspaceState(
        projects: projects ?? this.projects,
        loading: loading ?? this.loading,
        error: clearError ? null : error ?? this.error,
      );
}

class ProjectWorkspaceController extends StateNotifier<ProjectWorkspaceState> {
  ProjectWorkspaceController(this._store)
      : super(const ProjectWorkspaceState()) {
    refresh();
  }

  final ProjectStore _store;
  int _generation = 0;

  Future<void> refresh() async {
    final generation = ++_generation;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final projects = await _store.loadProjects();
      if (generation != _generation) return;
      state = ProjectWorkspaceState(projects: projects, loading: false);
    } catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(loading: false, error: error);
    }
  }

  Future<ProjectWorkspace> create({
    required String name,
    String description = '',
    String? sharedSpaceId,
  }) async {
    final project = await _store.createProject(
      name: name,
      description: description,
      sharedSpaceId: sharedSpaceId,
    );
    await refresh();
    return project;
  }

  Future<void> update(ProjectWorkspace project) async {
    await _store.updateProject(project);
    await refresh();
  }

  Future<void> setPreferredView(
    ProjectWorkspace project,
    ProjectWorkViewType view,
  ) async {
    if (project.preferredView == view) return;
    await _store.updateProject(project.copyWith(preferredView: view));
    await refresh();
  }

  Future<void> archive(String id, bool value) async {
    await _store.setArchived(id, value);
    await refresh();
  }

  Future<void> trash(String id) async {
    await _store.trash(id);
    await refresh();
  }

  Future<void> restore(String id) async {
    await _store.restore(id);
    await refresh();
  }

  Future<void> deleteForever(String id) async {
    await _store.deleteForever(id);
    await refresh();
  }

  Future<void> attach(String projectId, String noteId) async {
    await _store.attach(projectId, noteId);
    await refresh();
  }

  Future<void> detach(String projectId, String noteId) async {
    await _store.detach(projectId, noteId);
    await refresh();
  }
}

final projectWorkspaceProvider =
    StateNotifierProvider<ProjectWorkspaceController, ProjectWorkspaceState>(
  (ref) => ProjectWorkspaceController(ref.watch(projectStoreProvider)),
);
