import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/note.dart';
import '../domain/planner.dart';
import '../domain/project_workspace.dart';
import '../domain/shared_spaces.dart';
import '../state/project_workspace_controller.dart';
import '../state/shared_live_sync_controller.dart';
import '../state/shared_spaces_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/editorial.dart';
import '../widgets/ui_resilience.dart';

enum _ProjectScope { active, archive, trash }

class ProjectWorkspaceScreen extends ConsumerStatefulWidget {
  const ProjectWorkspaceScreen({
    required this.onOpenItem,
    required this.onCreateNote,
    required this.onCreateTask,
    required this.onSaveTask,
    this.initialProjectId,
    super.key,
  });

  final Future<void> Function(Note note, bool readOnly) onOpenItem;
  final Future<void> Function(ProjectWorkspace project) onCreateNote;
  final Future<void> Function(ProjectWorkspace project) onCreateTask;
  final Future<void> Function(ProjectWorkspace project, Note task) onSaveTask;
  final String? initialProjectId;

  @override
  ConsumerState<ProjectWorkspaceScreen> createState() =>
      _ProjectWorkspaceScreenState();
}

class _ProjectWorkspaceScreenState
    extends ConsumerState<ProjectWorkspaceScreen> {
  _ProjectScope _scope = _ProjectScope.active;
  bool _initialOpened = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(projectWorkspaceProvider);
    final shared = ref.watch(sharedSpacesProvider);
    final identity = shared.identity;

    if (!_initialOpened &&
        !state.loading &&
        widget.initialProjectId?.isNotEmpty == true) {
      _initialOpened = true;
      final project = state.byId(widget.initialProjectId!);
      if (project != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _open(project);
        });
      }
    }

    final projects = state.projects.where((project) {
      return switch (_scope) {
        _ProjectScope.active => project.isActive,
        _ProjectScope.archive => project.isArchived && !project.isDeleted,
        _ProjectScope.trash => project.isDeleted,
      };
    }).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const EditorialAppTitle(
          'Progetti',
          eyebrow: 'PROJECT WORKSPACE',
        ),
      ),
      floatingActionButton: _scope == _ProjectScope.active
          ? FloatingActionButton.extended(
              onPressed: state.loading ? null : () => _create(shared),
              icon: const Icon(Icons.add),
              label: const Text('Nuovo progetto'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => ref.read(projectWorkspaceProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
          children: [
            const EditorialEyebrow('UN SOLO LAVORO, PIÙ VISTE'),
            const SizedBox(height: 6),
            Text(
              'Organizza il lavoro senza duplicarlo.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Note, attività, disegni e contenuti condivisi restano gli oggetti '
              'canonici di Notes. Il progetto li raccoglie e li mostra come lista, '
              'board, tabella, calendario o timeline.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            SegmentedButton<_ProjectScope>(
              segments: const [
                ButtonSegment(
                  value: _ProjectScope.active,
                  label: Text('Attivi'),
                  icon: Icon(Icons.work_outline),
                ),
                ButtonSegment(
                  value: _ProjectScope.archive,
                  label: Text('Archivio'),
                  icon: Icon(Icons.archive_outlined),
                ),
                ButtonSegment(
                  value: _ProjectScope.trash,
                  label: Text('Cestino'),
                  icon: Icon(Icons.delete_outline),
                ),
              ],
              selected: {_scope},
              onSelectionChanged: (values) {
                setState(() => _scope = values.first);
              },
            ),
            const SizedBox(height: 18),
            if (state.loading && state.projects.isEmpty)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.error != null && state.projects.isEmpty)
              _InfoCard(
                icon: Icons.error_outline,
                title: 'Progetti non disponibili',
                detail: userErrorText(state.error),
                action: TextButton(
                  onPressed: () =>
                      ref.read(projectWorkspaceProvider.notifier).refresh(),
                  child: const Text('Riprova'),
                ),
              )
            else if (projects.isEmpty)
              _InfoCard(
                icon: _scope == _ProjectScope.active
                    ? Icons.work_outline
                    : _scope == _ProjectScope.archive
                        ? Icons.archive_outlined
                        : Icons.delete_outline,
                title: _scope == _ProjectScope.active
                    ? 'Nessun progetto'
                    : _scope == _ProjectScope.archive
                        ? 'Archivio vuoto'
                        : 'Cestino vuoto',
                detail: _scope == _ProjectScope.active
                    ? 'Crea un progetto personale oppure collegalo a uno Shared Space.'
                    : 'Qui compariranno i progetti spostati in questa sezione.',
              )
            else
              ...projects.map((project) {
                final space = project.sharedSpaceId == null
                    ? null
                    : shared.byId(project.sharedSpaceId!);
                final role = identity == null || space == null
                    ? null
                    : space.roleFor(identity.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _open(project),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              child: Icon(
                                space == null
                                    ? Icons.work_outline
                                    : Icons.groups_outlined,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    project.name,
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                  if (project.description
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      project.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      Chip(
                                        avatar: const Icon(
                                          Icons.view_quilt_outlined,
                                          size: 17,
                                        ),
                                        label: Text(
                                          project.preferredView.label,
                                        ),
                                      ),
                                      if (space != null)
                                        Chip(
                                          avatar: const Icon(
                                            Icons.groups_outlined,
                                            size: 17,
                                          ),
                                          label: Text(
                                            role == null
                                                ? space.name
                                                : '${space.name} · ${role.label}',
                                          ),
                                        ),
                                      if (project.sharedSpaceId != null &&
                                          space == null)
                                        const Chip(
                                          avatar: Icon(
                                            Icons.sync_problem_outlined,
                                            size: 17,
                                          ),
                                          label: Text(
                                            'Shared Space non disponibile',
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _open(ProjectWorkspace project) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ProjectDetailScreen(
          projectId: project.id,
          onOpenItem: widget.onOpenItem,
          onCreateNote: widget.onCreateNote,
          onCreateTask: widget.onCreateTask,
          onSaveTask: widget.onSaveTask,
        ),
      ),
    );
    if (mounted) {
      await ref.read(projectWorkspaceProvider.notifier).refresh();
    }
  }

  Future<void> _create(SharedSpacesState shared) async {
    final name = TextEditingController();
    final description = TextEditingController();
    String? selectedSpaceId;
    final readableSpaces = shared.identity == null
        ? const <SharedSpace>[]
        : shared.spaces
            .where((space) => space.canRead(shared.identity!.id))
            .toList(growable: false);

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nuovo progetto'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    maxLength: ProjectWorkspaceRules.maxNameLength,
                    decoration: const InputDecoration(
                      labelText: 'Nome',
                      hintText: 'Es. Lancio prodotto',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: description,
                    maxLines: 3,
                    maxLength: ProjectWorkspaceRules.maxDescriptionLength,
                    decoration: const InputDecoration(
                      labelText: 'Descrizione',
                    ),
                  ),
                  if (readableSpaces.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Collaborazione',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Facoltativo: usa uno Shared Space come membership e contenuto '
                      'collaborativo canonico del progetto.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    ChoiceChip(
                      label: const Text('Solo personale'),
                      selected: selectedSpaceId == null,
                      onSelected: (_) {
                        setDialogState(() => selectedSpaceId = null);
                      },
                    ),
                    const SizedBox(height: 6),
                    ...readableSpaces.map(
                      (space) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ChoiceChip(
                          avatar: const Icon(Icons.groups_outlined, size: 18),
                          label: Text(space.name),
                          selected: selectedSpaceId == space.id,
                          onSelected: (_) {
                            setDialogState(() => selectedSpaceId = space.id);
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Crea progetto'),
            ),
          ],
        ),
      ),
    );

    if (created != true || !mounted) return;
    try {
      final project = await ref.read(projectWorkspaceProvider.notifier).create(
            name: name.text,
            description: description.text,
            sharedSpaceId: selectedSpaceId,
          );
      if (!mounted) return;
      await _open(project);
    } on Object catch (error) {
      if (!mounted) return;
      _message(error);
    }
  }

  void _message(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          userErrorText(error),
        ),
      ),
    );
  }
}

class _ProjectDetailScreen extends ConsumerStatefulWidget {
  const _ProjectDetailScreen({
    required this.projectId,
    required this.onOpenItem,
    required this.onCreateNote,
    required this.onCreateTask,
    required this.onSaveTask,
  });

  final String projectId;
  final Future<void> Function(Note note, bool readOnly) onOpenItem;
  final Future<void> Function(ProjectWorkspace project) onCreateNote;
  final Future<void> Function(ProjectWorkspace project) onCreateTask;
  final Future<void> Function(ProjectWorkspace project, Note task) onSaveTask;

  @override
  ConsumerState<_ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<_ProjectDetailScreen> {
  List<ProjectItemLink> _personalLinks = const [];
  bool _loadingLinks = true;
  String _query = '';
  bool _showCompleted = true;

  @override
  void initState() {
    super.initState();
    _reloadLinks();
  }

  Future<void> _reloadLinks() async {
    try {
      final links =
          await ref.read(projectStoreProvider).loadLinks(widget.projectId);
      if (!mounted) return;
      setState(() {
        _personalLinks = links;
        _loadingLinks = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loadingLinks = false);
      _message(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectState = ref.watch(projectWorkspaceProvider);
    final workspace = ref.watch(workspaceProvider);
    final shared = ref.watch(sharedSpacesProvider);
    final project = projectState.byId(widget.projectId);

    if (project == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Progetto')),
        body: const Center(child: Text('Progetto non disponibile.')),
      );
    }

    final space = project.sharedSpaceId == null
        ? null
        : shared.byId(project.sharedSpaceId!);
    final identity = shared.identity;
    final role =
        identity == null || space == null ? null : space.roleFor(identity.id);
    final canEdit = project.isActive &&
        (project.sharedSpaceId == null || (role?.canEdit ?? false));
    final links = _effectiveLinks(project, space);
    final allItems = ProjectWorkViews.project(
      notes: workspace.notes,
      links: links,
      query: _query,
      showCompleted: _showCompleted,
    );
    final items = allItems.take(500).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: EditorialAppTitle(
          project.name,
          eyebrow: space == null ? 'PROJECT WORKSPACE' : 'TEAM PROJECT',
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => _projectAction(project, value),
            itemBuilder: (context) => [
              if (!project.isDeleted) ...[
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Modifica progetto'),
                ),
                PopupMenuItem(
                  value: 'archive',
                  child: Text(project.isArchived
                      ? 'Rimuovi dall’archivio'
                      : 'Archivia progetto'),
                ),
                const PopupMenuItem(
                  value: 'trash',
                  child: Text('Sposta progetto nel cestino'),
                ),
              ] else ...[
                const PopupMenuItem(
                  value: 'restore',
                  child: Text('Ripristina progetto'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Elimina definitivamente'),
                ),
              ],
            ],
          ),
        ],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _addMenu(project, space),
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
        children: [
          if (project.description.trim().isNotEmpty)
            Text(
              project.description,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          if (space != null) ...[
            const SizedBox(height: 12),
            _TeamBanner(space: space, role: role),
          ] else if (project.sharedSpaceId != null) ...[
            const SizedBox(height: 12),
            const _InfoCard(
              icon: Icons.sync_problem_outlined,
              title: 'Shared Space non disponibile',
              detail: 'Questo progetto resta intatto, ma i contenuti team '
                  'torneranno visibili quando lo Shared Space sarà disponibile.',
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CountChip(
                icon: Icons.layers_outlined,
                label: '${allItems.length} elementi',
              ),
              _CountChip(
                icon: Icons.check_circle_outline,
                label:
                    '${allItems.where((item) => item.kind == ProjectWorkItemKind.task).length} task',
              ),
              if (space != null)
                _CountChip(
                  icon: Icons.people_outline,
                  label: '${space.activeMembers.length} membri',
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: ProjectWorkViewType.values
                  .map(
                    (view) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(view.label),
                        selected: project.preferredView == view,
                        onSelected: project.isDeleted
                            ? null
                            : (_) => ref
                                .read(projectWorkspaceProvider.notifier)
                                .setPreferredView(project, view),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Cerca nel progetto…',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _showCompleted,
            onChanged: (value) => setState(() => _showCompleted = value),
            title: const Text('Mostra attività completate'),
          ),
          if (_loadingLinks && project.sharedSpaceId == null)
            const LinearProgressIndicator(),
          if (allItems.length > items.length)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Per mantenere la vista fluida sono mostrati i primi '
                '${items.length} di ${allItems.length} elementi. '
                'Usa la ricerca per restringere.',
              ),
            ),
          if (items.isEmpty && !_loadingLinks)
            const _InfoCard(
              icon: Icons.inbox_outlined,
              title: 'Progetto vuoto',
              detail:
                  'Aggiungi una nota, un’attività o un contenuto esistente. '
                  'Le viste cambiano, i dati restano gli stessi.',
            )
          else
            _WorkView(
              type: project.preferredView,
              items: items,
              onOpen: (item) => widget.onOpenItem(item.note, !canEdit),
              onRemove: canEdit
                  ? (item) => _remove(project, space, item.note.id)
                  : null,
              onStage: canEdit
                  ? (item, stage) => _changeStage(project, item, stage)
                  : null,
            ),
        ],
      ),
    );
  }

  List<ProjectItemLink> _effectiveLinks(
    ProjectWorkspace project,
    SharedSpace? space,
  ) {
    if (project.sharedSpaceId == null) return _personalLinks;
    if (space == null) return const [];
    final ids = space.contentIds.toList()..sort();
    return [
      for (var index = 0; index < ids.length; index++)
        ProjectItemLink(
          projectId: project.id,
          noteId: ids[index],
          position: index,
          addedAt: space.contentAddedAt[ids[index]] ?? 0,
          updatedAt: space.contentAddedAt[ids[index]] ?? space.updatedAt,
        ),
    ];
  }

  Future<void> _addMenu(ProjectWorkspace project, SharedSpace? space) async {
    final action = await showNotesBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('Nuova nota'),
              onTap: () => Navigator.pop(context, 'note'),
            ),
            ListTile(
              leading: const Icon(Icons.add_task),
              title: const Text('Nuova attività'),
              onTap: () => Navigator.pop(context, 'task'),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Aggiungi esistente'),
              onTap: () => Navigator.pop(context, 'existing'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    try {
      switch (action) {
        case 'note':
          await widget.onCreateNote(project);
          break;
        case 'task':
          await widget.onCreateTask(project);
          break;
        case 'existing':
          await _pickExisting(project, space);
          break;
      }
      await _reloadLinks();
    } on Object catch (error) {
      if (mounted) _message(error);
    }
  }

  Future<void> _pickExisting(
    ProjectWorkspace project,
    SharedSpace? space,
  ) async {
    final workspace = ref.read(workspaceProvider);
    final currentIds =
        _effectiveLinks(project, space).map((link) => link.noteId).toSet();
    final candidates = workspace.notes
        .where((note) => !note.isDeleted && !currentIds.contains(note.id))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final selected = await showDialog<Note>(
      context: context,
      builder: (context) => _ExistingItemDialog(notes: candidates),
    );
    if (selected == null) return;

    if (project.sharedSpaceId == null) {
      await ref
          .read(projectWorkspaceProvider.notifier)
          .attach(project.id, selected.id);
    } else {
      if (space == null) {
        throw const FormatException('Shared Space non disponibile.');
      }
      await ref
          .read(sharedSpacesProvider.notifier)
          .linkContent(space.id, selected.id);
      await ref.read(sharedLiveSyncProvider.notifier).syncSoon();
    }
  }

  Future<void> _remove(
    ProjectWorkspace project,
    SharedSpace? space,
    String noteId,
  ) async {
    try {
      if (project.sharedSpaceId == null) {
        await ref
            .read(projectWorkspaceProvider.notifier)
            .detach(project.id, noteId);
      } else {
        if (space == null) {
          throw const FormatException('Shared Space non disponibile.');
        }
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Rimuovere dal progetto team?'),
            content: const Text(
              'L’elemento verrà rimosso dallo Shared Space per tutti i membri. '
              'La nota o attività originale non verrà eliminata.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Rimuovi'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await ref
            .read(sharedSpacesProvider.notifier)
            .unlinkContent(space.id, noteId);
        await ref.read(sharedLiveSyncProvider.notifier).syncSoon();
      }
      await _reloadLinks();
    } on Object catch (error) {
      if (mounted) _message(error);
    }
  }

  Future<void> _changeStage(
    ProjectWorkspace project,
    ProjectWorkItem item,
    String stage,
  ) async {
    if (!item.note.isTask || item.completed) return;
    final details = TaskDetails.tryDecode(item.note.taskJson);
    if (details == null) return;
    final updated = item.note.copyWith(
      taskJson: details.copyWith(stage: stage).encode(),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    try {
      await widget.onSaveTask(project, updated);
    } on Object catch (error) {
      if (mounted) _message(error);
    }
  }

  Future<void> _projectAction(
    ProjectWorkspace project,
    String action,
  ) async {
    try {
      switch (action) {
        case 'edit':
          await _edit(project);
          return;
        case 'archive':
          await ref
              .read(projectWorkspaceProvider.notifier)
              .archive(project.id, !project.isArchived);
          break;
        case 'trash':
          final confirmed = await _confirm(
            'Spostare il progetto nel cestino?',
            'Note, attività e contenuti condivisi non verranno eliminati. '
                'Potrai ripristinare il progetto dal cestino.',
            'Sposta',
          );
          if (!confirmed) return;
          await ref.read(projectWorkspaceProvider.notifier).trash(project.id);
          break;
        case 'restore':
          await ref.read(projectWorkspaceProvider.notifier).restore(project.id);
          break;
        case 'delete':
          final confirmed = await _confirm(
            'Eliminare definitivamente il progetto?',
            'Verrà eliminata solo l’organizzazione del progetto. '
                'Note, attività e Shared Space resteranno intatti. '
                'Questa operazione non è reversibile.',
            'Elimina definitivamente',
          );
          if (!confirmed) return;
          await ref
              .read(projectWorkspaceProvider.notifier)
              .deleteForever(project.id);
          break;
      }
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) _message(error);
    }
  }

  Future<void> _edit(ProjectWorkspace project) async {
    final name = TextEditingController(text: project.name);
    final description = TextEditingController(text: project.description);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifica progetto'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                maxLength: ProjectWorkspaceRules.maxNameLength,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              TextField(
                controller: description,
                maxLines: 4,
                maxLength: ProjectWorkspaceRules.maxDescriptionLength,
                decoration: const InputDecoration(labelText: 'Descrizione'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await ref.read(projectWorkspaceProvider.notifier).update(
          project.copyWith(
            name: name.text.trim(),
            description: description.text.trim(),
          ),
        );
  }

  Future<bool> _confirm(
    String title,
    String body,
    String action,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _message(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          userErrorText(error),
        ),
      ),
    );
  }
}

class _ExistingItemDialog extends StatefulWidget {
  const _ExistingItemDialog({required this.notes});
  final List<Note> notes;

  @override
  State<_ExistingItemDialog> createState() => _ExistingItemDialogState();
}

class _ExistingItemDialogState extends State<_ExistingItemDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    final filtered = widget.notes
        .where((note) {
          if (needle.isEmpty) return true;
          return note.title.toLowerCase().contains(needle) ||
              (!note.isVisual && note.body.toLowerCase().contains(needle)) ||
              note.tags.any((tag) => tag.toLowerCase().contains(needle));
        })
        .take(250)
        .toList(growable: false);

    return AlertDialog(
      title: const Text('Aggiungi esistente'),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Nota, attività o disegno…',
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('Nessun elemento disponibile.'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final note = filtered[index];
                        return ListTile(
                          leading: Icon(_itemIcon(note)),
                          title: Text(
                            note.title.trim().isEmpty
                                ? 'Senza titolo'
                                : note.title,
                          ),
                          subtitle: Text(_itemKind(note)),
                          onTap: () => Navigator.pop(context, note),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Chiudi'),
        ),
      ],
    );
  }
}

class _WorkView extends StatelessWidget {
  const _WorkView({
    required this.type,
    required this.items,
    required this.onOpen,
    this.onRemove,
    this.onStage,
  });

  final ProjectWorkViewType type;
  final List<ProjectWorkItem> items;
  final ValueChanged<ProjectWorkItem> onOpen;
  final ValueChanged<ProjectWorkItem>? onRemove;
  final void Function(ProjectWorkItem item, String stage)? onStage;

  @override
  Widget build(BuildContext context) => switch (type) {
        ProjectWorkViewType.list => _list(context),
        ProjectWorkViewType.board => _board(context),
        ProjectWorkViewType.table => _table(context),
        ProjectWorkViewType.calendar => _calendar(context),
        ProjectWorkViewType.timeline => _timeline(context),
      };

  Widget _list(BuildContext context) => Column(
        children: items
            .map(
              (item) => Card(
                child: ListTile(
                  leading: Icon(_workIcon(item.kind)),
                  title: Text(item.title),
                  subtitle: Text(_subtitle(item)),
                  onTap: () => onOpen(item),
                  trailing: onRemove == null
                      ? null
                      : IconButton(
                          tooltip: 'Rimuovi dal progetto',
                          onPressed: () => onRemove!(item),
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            )
            .toList(growable: false),
      );

  Widget _board(BuildContext context) {
    final board = ProjectWorkViews.board(items);
    return SizedBox(
      height: 520,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: ProjectWorkViews.boardLanes.map((lane) {
          final laneItems = board[lane] ?? const <ProjectWorkItem>[];
          return SizedBox(
            width: 290,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _laneLabel(lane),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Text('${laneItems.length}'),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: laneItems.isEmpty
                            ? const Center(child: Text('Nessun elemento'))
                            : ListView.builder(
                                itemCount: laneItems.length,
                                itemBuilder: (context, index) {
                                  final item = laneItems[index];
                                  return Card(
                                    child: InkWell(
                                      onTap: () => onOpen(item),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.title,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall,
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              _subtitle(item),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                            if (item.kind ==
                                                    ProjectWorkItemKind.task &&
                                                !item.completed &&
                                                onStage != null)
                                              Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: PopupMenuButton<String>(
                                                  tooltip: 'Cambia colonna',
                                                  onSelected: (stage) =>
                                                      onStage!(item, stage),
                                                  itemBuilder: (context) =>
                                                      const [
                                                    PopupMenuItem(
                                                      value: 'TODO',
                                                      child: Text('Da fare'),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'DOING',
                                                      child: Text('In corso'),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'DONE',
                                                      child: Text('Fatto'),
                                                    ),
                                                  ],
                                                  icon: const Icon(
                                                    Icons.swap_horiz,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }

  Widget _table(BuildContext context) => Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Elemento')),
              DataColumn(label: Text('Tipo')),
              DataColumn(label: Text('Stato')),
              DataColumn(label: Text('Data')),
              DataColumn(label: Text('Priorità')),
            ],
            rows: items
                .map(
                  (item) => DataRow(
                    onSelectChanged: (_) => onOpen(item),
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 240,
                          child: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text(_kindLabel(item.kind))),
                      DataCell(Text(_laneLabel(item.stage))),
                      DataCell(Text(item.effectiveDate ?? '—')),
                      DataCell(
                          Text(item.priority == 0 ? '—' : '${item.priority}')),
                    ],
                  ),
                )
                .toList(growable: false),
          ),
        ),
      );

  Widget _calendar(BuildContext context) {
    final groups = ProjectWorkViews.calendar(items);
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a == 'UNDATED') return 1;
        if (b == 'UNDATED') return -1;
        return a.compareTo(b);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: keys.map((key) {
        final parsed = key == 'UNDATED' ? null : DateTime.tryParse(key);
        final label = parsed == null
            ? 'Senza data'
            : DateFormat('EEEE d MMMM', 'it_IT').format(parsed);
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EditorialSection(label),
              ...groups[key]!.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_workIcon(item.kind)),
                  title: Text(item.title),
                  subtitle: Text(
                    item.plannedTime == null
                        ? _subtitle(item)
                        : '${item.plannedTime} · ${_subtitle(item)}',
                  ),
                  onTap: () => onOpen(item),
                ),
              ),
            ],
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _timeline(BuildContext context) {
    final ordered = ProjectWorkViews.timeline(items);
    return Column(
      children: ordered.map((item) {
        final date = item.effectiveDate;
        final parsed = date == null ? null : DateTime.tryParse(date);
        final dateLabel = parsed == null
            ? 'Senza data'
            : DateFormat('d MMM yyyy', 'it_IT').format(parsed);
        return Card(
          child: ListTile(
            leading: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timeline),
                Text(
                  item.plannedTime ?? '',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            title: Text(item.title),
            subtitle: Text(
              '$dateLabel · ${item.plannedMinutes} min · ${_subtitle(item)}',
            ),
            onTap: () => onOpen(item),
          ),
        );
      }).toList(growable: false),
    );
  }

  String _subtitle(ProjectWorkItem item) {
    if (item.kind != ProjectWorkItemKind.task) return _kindLabel(item.kind);
    final parts = <String>[
      _laneLabel(item.stage),
      if (item.plannedDate != null) 'Pianificata ${item.plannedDate}',
      if (item.due != null) 'Scade ${item.due}',
      if (item.completed) 'Completata',
    ];
    return parts.join(' · ');
  }
}

class _TeamBanner extends StatelessWidget {
  const _TeamBanner({required this.space, required this.role});

  final SharedSpace space;
  final SharedRole? role;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.groups_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      space.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      role == null
                          ? 'Accesso team non disponibile'
                          : '${role!.label} · ${space.activeMembers.length} membri · '
                              'contenuti gestiti da Shared Spaces',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(icon, size: 17),
        label: Text(label),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              Icon(icon, size: 34),
              const SizedBox(height: 10),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(detail, textAlign: TextAlign.center),
              if (action != null) ...[
                const SizedBox(height: 8),
                action!,
              ],
            ],
          ),
        ),
      );
}

IconData _workIcon(ProjectWorkItemKind kind) => switch (kind) {
      ProjectWorkItemKind.note => Icons.description_outlined,
      ProjectWorkItemKind.task => Icons.check_circle_outline,
      ProjectWorkItemKind.sketch => Icons.draw_outlined,
      ProjectWorkItemKind.whiteboard => Icons.dashboard_customize_outlined,
    };

IconData _itemIcon(Note note) {
  if (note.isTask) return Icons.check_circle_outline;
  if (note.visualKind == VisualDocumentKind.sketch) return Icons.draw_outlined;
  if (note.visualKind == VisualDocumentKind.whiteboard) {
    return Icons.dashboard_customize_outlined;
  }
  return Icons.description_outlined;
}

String _itemKind(Note note) {
  if (note.isTask) return 'Attività';
  if (note.visualKind == VisualDocumentKind.sketch) return 'Disegno';
  if (note.visualKind == VisualDocumentKind.whiteboard) return 'Lavagna';
  return 'Nota';
}

String _kindLabel(ProjectWorkItemKind kind) => switch (kind) {
      ProjectWorkItemKind.note => 'Nota',
      ProjectWorkItemKind.task => 'Attività',
      ProjectWorkItemKind.sketch => 'Disegno',
      ProjectWorkItemKind.whiteboard => 'Lavagna',
    };

String _laneLabel(String stage) => switch (stage) {
      'TODO' => 'Da fare',
      'DOING' => 'In corso',
      'DONE' => 'Fatto',
      'REFERENCE' => 'Riferimenti',
      _ => stage,
    };
