import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/note.dart';
import '../domain/planner.dart';
import '../domain/shared_activity.dart';
import '../domain/shared_spaces.dart';
import '../state/shared_live_sync_controller.dart';
import '../state/shared_spaces_controller.dart';
import '../state/workspace_controller.dart';
import '../platform/reminder_bridge.dart';
import '../sync/shared_spaces_live_sync.dart';
import '../widgets/editorial.dart';

class SharedSpacesScreen extends ConsumerStatefulWidget {
  const SharedSpacesScreen({
    required this.onOpenNote,
    required this.onCreateNote,
    required this.onCreateTask,
    required this.onExportBundle,
    required this.onImportBundle,
    super.key,
  });

  final Future<void> Function(Note note, bool readOnly) onOpenNote;
  final Future<void> Function(String spaceId) onCreateNote;
  final Future<void> Function(String spaceId) onCreateTask;
  final Future<void> Function(SharedSpace space) onExportBundle;
  final Future<void> Function() onImportBundle;

  @override
  ConsumerState<SharedSpacesScreen> createState() => _SharedSpacesScreenState();
}

class _SharedSpacesScreenState extends ConsumerState<SharedSpacesScreen> {
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    try {
      setState(() => _error = null);
      await action();
      final live = ref.read(sharedLiveSyncProvider);
      if (live.enabled) {
        unawaited(
          ref.read(sharedLiveSyncProvider.notifier).syncSoon(),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  Future<void> _editIdentity() async {
    final identity = ref.read(sharedSpacesProvider).identity;
    if (identity == null) return;
    final controller = TextEditingController(text: identity.displayName);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Profilo collaborazione'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Nome visibile negli spazi',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    await _run(
      () => ref.read(sharedSpacesProvider.notifier).setIdentityName(value),
    );
  }

  Future<void> _createSpace() async {
    final name = TextEditingController();
    final description = TextEditingController();
    final result = await showDialog<({String name, String description})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuovo Shared Space'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Nome spazio',
              ),
            ),
            TextField(
              controller: description,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descrizione',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              (name: name.text, description: description.text),
            ),
            child: const Text('Crea'),
          ),
        ],
      ),
    );
    name.dispose();
    description.dispose();
    if (result == null) return;
    await _run(() async {
      final id = await ref.read(sharedSpacesProvider.notifier).createSpace(
            result.name,
            description: result.description,
          );
      if (!mounted) return;
      await _openSpace(id);
    });
  }

  Future<void> _joinSpace() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unisciti a uno spazio'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 7,
          decoration: const InputDecoration(
            labelText: 'Codice invito NS26',
            hintText: 'NS26.…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final data = await Clipboard.getData('text/plain');
              if (!context.mounted || data?.text == null) return;
              controller.text = data!.text!;
            },
            child: const Text('Incolla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Unisciti'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null) return;
    await _run(() async {
      final id = await ref.read(sharedSpacesProvider.notifier).joinInvite(code);
      if (!mounted) return;
      await _openSpace(id);
    });
  }

  Future<void> _openSpace(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SharedSpaceDetailScreen(
          spaceId: id,
          onOpenNote: widget.onOpenNote,
          onCreateNote: widget.onCreateNote,
          onCreateTask: widget.onCreateTask,
          onExportBundle: widget.onExportBundle,
          onImportBundle: widget.onImportBundle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shared = ref.watch(sharedSpacesProvider);
    final live = ref.watch(sharedLiveSyncProvider);
    final workspace = ref.watch(workspaceProvider);
    final identity = shared.identity;

    if (shared.loading || identity == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final spaces = shared.spaces
        .where((space) => space.canRead(identity.id))
        .toList(growable: false);
    final notesById = {
      for (final note in workspace.notes) note.id: note,
    };
    final totalUnread = live.totalUnread(identity.id);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
      children: [
        _ProfileCard(
          identity: identity,
          spaceCount: spaces.length,
          onEdit: _editIdentity,
        ),
        const SizedBox(height: 14),
        if (_error != null) _InlineError(message: _error!),
        if (shared.error != null)
          _InlineError(
            message:
                shared.error.toString().replaceFirst('FormatException: ', ''),
          ),
        _PrivacyCard(
          onJoin: _joinSpace,
          onImport: widget.onImportBundle,
        ),
        const SizedBox(height: 12),
        _LiveSyncCard(
          state: live,
          onToggle: (value) => _run(
            () => ref.read(sharedLiveSyncProvider.notifier).setEnabled(value),
          ),
          onSync: () => _run(
            () => ref.read(sharedLiveSyncProvider.notifier).syncNow(),
          ),
          onNotifications: () async {
            final allowed = await ReminderBridge.requestPermission();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  allowed
                      ? 'Notifiche Shared Spaces abilitate.'
                      : 'Notifiche non abilitate. Puoi attivarle dalle impostazioni di Android.',
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: Text(
                'I tuoi spazi',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (totalUnread > 0)
              TextButton.icon(
                onPressed: () =>
                    ref.read(sharedLiveSyncProvider.notifier).markAllRead(),
                icon: const Icon(Icons.done_all),
                label: Text('Letti · $totalUnread'),
              ),
            FilledButton.tonalIcon(
              onPressed: _createSpace,
              icon: const Icon(Icons.add),
              label: const Text('Nuovo'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (spaces.isEmpty)
          _EmptySpaces(onCreate: _createSpace, onJoin: _joinSpace)
        else
          ...spaces.map((space) {
            final content = [
              for (final id in space.contentIds)
                if (notesById[id] case final note?) note,
            ];
            final tasks = content.where((note) => note.isTask).length;
            final planned = content.where((note) {
              final task = TaskDetails.tryDecode(note.taskJson);
              return task?.plannedDate != null || task?.due != null;
            }).length;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SpaceCard(
                space: space,
                role: space.roleFor(identity.id)!,
                contentCount: content.length,
                taskCount: tasks,
                plannedCount: planned,
                syncEnabled: live.enabled,
                syncBusy: live.enabled && live.busy,
                syncSummary: live.spaceSummaries[space.id],
                lastSyncAt: live.lastSyncAt,
                unreadCount: live.unreadFor(space.id, identity.id),
                onTap: () => _openSpace(space.id),
              ),
            );
          }),
      ],
    );
  }
}

class SharedSpaceDetailScreen extends ConsumerStatefulWidget {
  const SharedSpaceDetailScreen({
    required this.spaceId,
    required this.onOpenNote,
    required this.onCreateNote,
    required this.onCreateTask,
    required this.onExportBundle,
    required this.onImportBundle,
    super.key,
  });

  final String spaceId;
  final Future<void> Function(Note note, bool readOnly) onOpenNote;
  final Future<void> Function(String spaceId) onCreateNote;
  final Future<void> Function(String spaceId) onCreateTask;
  final Future<void> Function(SharedSpace space) onExportBundle;
  final Future<void> Function() onImportBundle;

  @override
  ConsumerState<SharedSpaceDetailScreen> createState() =>
      _SharedSpaceDetailScreenState();
}

class _SharedSpaceDetailScreenState
    extends ConsumerState<SharedSpaceDetailScreen> {
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    try {
      setState(() => _error = null);
      await action();
      final live = ref.read(sharedLiveSyncProvider);
      if (live.enabled) {
        unawaited(
          ref.read(sharedLiveSyncProvider.notifier).syncSoon(),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  Future<void> _addExisting(
    SharedSpace space,
    List<Note> notes,
  ) async {
    final available = notes
        .where(
          (note) =>
              !note.isDeleted &&
              !note.archived &&
              !space.contentIds.contains(note.id),
        )
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Non ci sono altri elementi da aggiungere.'),
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<Note>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            const ListTile(
              title: Text('Aggiungi contenuto esistente'),
              subtitle: Text(
                'Solo l’elemento scelto entrerà nello spazio condiviso.',
              ),
            ),
            ...available.take(100).map(
                  (note) => ListTile(
                    leading: Icon(_noteIcon(note)),
                    title: Text(
                      note.title.trim().isEmpty
                          ? 'Senza titolo'
                          : note.title.trim(),
                    ),
                    subtitle: Text(_noteKind(note)),
                    onTap: () => Navigator.pop(context, note),
                  ),
                ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await _run(
      () => ref
          .read(sharedSpacesProvider.notifier)
          .linkContent(space.id, selected.id),
    );
  }

  Future<void> _invite(SharedSpace space) async {
    var role = SharedRole.editor;
    final choice = await showDialog<SharedRole>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Crea invito'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Il codice identifica lo spazio e il ruolo, ma non contiene password o token cloud.',
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: Icon(
                  role == SharedRole.editor
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: const Text('Può modificare'),
                onTap: () => setDialogState(() => role = SharedRole.editor),
              ),
              ListTile(
                leading: Icon(
                  role == SharedRole.viewer
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: const Text('Solo lettura'),
                onTap: () => setDialogState(() => role = SharedRole.viewer),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, role),
              child: const Text('Genera'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    await _run(() async {
      final code = ref
          .read(sharedSpacesProvider.notifier)
          .createInvite(space.id, role: choice);
      await Clipboard.setData(ClipboardData(text: code));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invito copiato'),
          content: SelectableText(code),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fatto'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _editDetails(SharedSpace space) async {
    final name = TextEditingController(text: space.name);
    final description = TextEditingController(text: space.description);
    final result = await showDialog<({String name, String description})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Impostazioni spazio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            TextField(
              controller: description,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descrizione',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              (name: name.text, description: description.text),
            ),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    name.dispose();
    description.dispose();
    if (result == null) return;
    await _run(
      () => ref.read(sharedSpacesProvider.notifier).updateDetails(
            space.id,
            name: result.name,
            description: result.description,
          ),
    );
  }

  Future<void> _forget(SharedSpace space) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rimuovere lo spazio da questo dispositivo?'),
        content: const Text(
          'Le note e le attività resteranno nel tuo archivio personale. '
          'Verrà rimossa solo l’associazione locale allo Shared Space.',
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
    await _run(
      () => ref.read(sharedSpacesProvider.notifier).forgetSpace(space.id),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final shared = ref.watch(sharedSpacesProvider);
    final workspace = ref.watch(workspaceProvider);
    final live = ref.watch(sharedLiveSyncProvider);
    final identity = shared.identity;
    final space = shared.byId(widget.spaceId);

    if (identity == null || shared.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (space == null) {
      return const Scaffold(
        body: Center(child: Text('Spazio non disponibile.')),
      );
    }

    final role = space.roleFor(identity.id);
    if (role == null) {
      return const Scaffold(
        body: Center(child: Text('Accesso allo spazio revocato.')),
      );
    }

    final notesById = {
      for (final note in workspace.notes) note.id: note,
    };
    final contents = [
      for (final id in space.contentIds)
        if (notesById[id] case final note?) note,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final missing = space.contentIds.length - contents.length;
    final canEdit = role.canEdit;
    final canManage = role.canManage;
    final activity = live.activitiesBySpace[space.id] ?? const [];
    final unread = live.unreadFor(space.id, identity.id);
    final lastReadAt = live.lastReadAt[space.id] ?? 0;
    if (unread > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(sharedLiveSyncProvider.notifier).markSpaceRead(space.id);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(space.name),
        actions: [
          if (canManage)
            IconButton(
              tooltip: 'Invita',
              onPressed: () => _invite(space),
              icon: const Icon(Icons.person_add_alt_1),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'export') {
                widget.onExportBundle(space);
              } else if (value == 'import') {
                widget.onImportBundle();
              } else if (value == 'settings') {
                _editDetails(space);
              } else if (value == 'forget') {
                _forget(space);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export',
                child: Text('Esporta aggiornamento'),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Text('Importa aggiornamento'),
              ),
              if (canManage)
                const PopupMenuItem(
                  value: 'settings',
                  child: Text('Impostazioni spazio'),
                ),
              const PopupMenuItem(
                value: 'forget',
                child: Text('Rimuovi dal dispositivo'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 120),
        children: [
          _SpaceHero(space: space, role: role),
          const SizedBox(height: 10),
          _SpaceSyncStatusCard(
            enabled: live.enabled,
            busy: live.enabled && live.busy,
            summary: live.spaceSummaries[space.id],
            lastSyncAt: live.lastSyncAt,
            onSync: () => _run(
              () => ref.read(sharedLiveSyncProvider.notifier).syncNow(),
            ),
          ),
          if (activity.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ActivityFeedCard(
              events: activity,
              space: space,
              notes: workspace.notes,
              identityId: identity.id,
              lastReadAt: lastReadAt,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            _InlineError(message: _error!),
          ],
          const SizedBox(height: 20),
          _SectionTitle(
            title: 'Contenuti condivisi',
            trailing: canEdit
                ? TextButton.icon(
                    onPressed: () => _addExisting(space, workspace.notes),
                    icon: const Icon(Icons.add_link),
                    label: const Text('Aggiungi'),
                  )
                : null,
          ),
          if (missing > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '$missing elementi attendono un aggiornamento importato.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (contents.isEmpty)
            _EmptyContent(
              canEdit: canEdit,
              onAdd: () => _addExisting(space, workspace.notes),
              onCreate: () => widget.onCreateNote(space.id),
            )
          else
            ...contents.map(
              (note) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(_noteIcon(note)),
                  title: Text(
                    note.title.trim().isEmpty
                        ? 'Senza titolo'
                        : note.title.trim(),
                  ),
                  subtitle: Text(_noteKind(note)),
                  onTap: () => widget.onOpenNote(note, !canEdit),
                  trailing: canEdit
                      ? PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'remove') {
                              _run(
                                () => ref
                                    .read(sharedSpacesProvider.notifier)
                                    .unlinkContent(space.id, note.id),
                              );
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'remove',
                              child: Text('Rendi di nuovo privato'),
                            ),
                          ],
                        )
                      : null,
                ),
              ),
            ),
          if (canEdit) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => widget.onCreateNote(space.id),
                    icon: const Icon(Icons.note_add_outlined),
                    label: const Text('Nuova nota'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => widget.onCreateTask(space.id),
                    icon: const Icon(Icons.add_task),
                    label: const Text('Nuova attività'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 26),
          _SectionTitle(
            title: 'Membri · ${space.activeMembers.length}',
            trailing: canManage
                ? TextButton.icon(
                    onPressed: () => _invite(space),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Invita'),
                  )
                : null,
          ),
          ...space.activeMembers.map(
            (member) => _MemberTile(
              member: member,
              isSelf: member.id == identity.id,
              canManage: canManage,
              isOwner: member.id == space.ownerId,
              onRole: (role) => _run(
                () => ref
                    .read(sharedSpacesProvider.notifier)
                    .setMemberRole(space.id, member.id, role),
              ),
              onRemove: () => _run(
                () => ref
                    .read(sharedSpacesProvider.notifier)
                    .removeMember(space.id, member.id),
              ),
            ),
          ),
          const SizedBox(height: 22),
          _SyncInfoCard(
            onExport: () => widget.onExportBundle(space),
            onImport: widget.onImportBundle,
          ),
        ],
      ),
    );
  }
}

class SharedTaskReadOnlyScreen extends StatelessWidget {
  const SharedTaskReadOnlyScreen({
    required this.note,
    super.key,
  });

  final Note note;

  @override
  Widget build(BuildContext context) {
    final task = TaskDetails.tryDecode(note.taskJson);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attività condivisa'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 60),
        children: [
          const EditorialEyebrow('SOLO LETTURA · SHARED SPACE'),
          const SizedBox(height: 6),
          Text(
            note.title.trim().isEmpty ? 'Attività' : note.title.trim(),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          if (task != null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.flag_outlined, size: 18),
                  label: Text('Priorità ${task.priority}'),
                ),
                if (task.due != null)
                  Chip(
                    avatar: const Icon(Icons.event_outlined, size: 18),
                    label: Text('Scadenza ${task.due}'),
                  ),
                if (task.plannedDate != null)
                  Chip(
                    avatar: const Icon(Icons.schedule, size: 18),
                    label: Text(
                      task.plannedTime == null
                          ? 'Pianificata ${task.plannedDate}'
                          : 'Pianificata ${task.plannedDate} · ${task.plannedTime}',
                    ),
                  ),
                Chip(
                  avatar: Icon(
                    task.completed
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 18,
                  ),
                  label: Text(task.completed ? 'Completata' : task.stage),
                ),
              ],
            ),
          if (note.body.trim().isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(
              'Note',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(note.body),
          ],
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.identity,
    required this.spaceCount,
    required this.onEdit,
  });

  final SharedIdentity identity;
  final int spaceCount;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(
            child: Text(
              identity.displayName.characters.first.toUpperCase(),
            ),
          ),
          title: Text(identity.displayName),
          subtitle: Text(
            identity.githubBound
                ? '$spaceCount Shared Space${spaceCount == 1 ? '' : 's'} · GitHub @${identity.githubLogin}'
                : '$spaceCount Shared Space${spaceCount == 1 ? '' : 's'} · profilo locale',
          ),
          trailing: IconButton(
            tooltip: 'Modifica nome',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ),
      );
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard({
    required this.onJoin,
    required this.onImport,
  });

  final VoidCallback onJoin;
  final Future<void> Function() onImport;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EditorialEyebrow('PRIVATE BY DEFAULT'),
              const SizedBox(height: 4),
              Text(
                'Condividi solo ciò che scegli.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text(
                'Le note personali restano fuori dagli spazi finché non le aggiungi esplicitamente.',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onJoin,
                    icon: const Icon(Icons.link),
                    label: const Text('Usa invito'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onImport,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Importa aggiornamento'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _LiveSyncCard extends StatelessWidget {
  const _LiveSyncCard({
    required this.state,
    required this.onToggle,
    required this.onSync,
    required this.onNotifications,
  });

  final SharedLiveSyncState state;
  final ValueChanged<bool> onToggle;
  final VoidCallback onSync;
  final Future<void> Function() onNotifications;

  @override
  Widget build(BuildContext context) {
    final last = state.lastSyncAt == null
        ? 'Mai sincronizzato'
        : _formatSyncTime(state.lastSyncAt!);
    final error = state.error
        ?.toString()
        .replaceFirst('FormatException: ', '')
        .replaceFirst('GitHubHttpFailure: ', '');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                state.busy ? Icons.sync : Icons.cloud_sync_outlined,
              ),
              title: const Text('Shared Spaces Live Sync'),
              subtitle: const Text(
                'Usa il repository GitHub privato già collegato e verifica '
                'l’identità dell’account. Sync automatico mentre Notes è aperta.',
              ),
              value: state.enabled,
              onChanged: state.busy ? null : onToggle,
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    state.busy ? 'Sincronizzazione in corso…' : state.message,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: state.busy ? null : onSync,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sincronizza ora'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(
                    _connectionIcon(state.connection),
                    size: 18,
                  ),
                  label: Text(
                    state.enabled
                        ? state.connection.label
                        : 'Auto-sync disattivato',
                  ),
                ),
                if (state.nextRetryAt != null && state.enabled)
                  Chip(
                    avatar: const Icon(Icons.schedule, size: 18),
                    label: Text(_formatRetryTime(state.nextRetryAt!)),
                  ),
                if (state.failureStreak > 0 && state.enabled)
                  Chip(
                    avatar: const Icon(Icons.replay, size: 18),
                    label: Text(
                      'Tentativo ${state.failureStreak + 1}',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              last,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            if (state.conflicts > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${state.conflicts} conflitti preservati come copie locali.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            ],
            if (error != null && error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            if (state.enabled) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.notifications_active_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.backgroundLastCheckAt == null
                          ? 'Background Android pianificato ogni '
                              '${state.backgroundIntervalMinutes} minuti.'
                          : 'Background: ultimo controllo '
                              '${_formatCompactSyncTime(state.backgroundLastCheckAt!)}.',
                    ),
                  ),
                  TextButton(
                    onPressed: onNotifications,
                    child: const Text('Notifiche'),
                  ),
                ],
              ),
              if (state.backgroundLastSuccessAt != null)
                Text(
                  'Ultimo controllo riuscito: '
                  '${_formatCompactSyncTime(state.backgroundLastSuccessAt!)}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              if (state.backgroundError != null &&
                  state.backgroundError!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Background: ${state.backgroundError}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

IconData _connectionIcon(SharedLiveConnectionStatus status) => switch (status) {
      SharedLiveConnectionStatus.idle => Icons.cloud_off_outlined,
      SharedLiveConnectionStatus.online => Icons.cloud_done_outlined,
      SharedLiveConnectionStatus.offline => Icons.cloud_off_outlined,
      SharedLiveConnectionStatus.attention => Icons.warning_amber_rounded,
    };

String _formatRetryTime(int millis) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  final second = date.second.toString().padLeft(2, '0');
  return 'Riprovo alle $hour:$minute:$second';
}

String _formatSyncTime(int millis) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return 'Ultimo sync: $day/$month · $hour:$minute';
}

class _SpaceCard extends StatelessWidget {
  const _SpaceCard({
    required this.space,
    required this.role,
    required this.contentCount,
    required this.taskCount,
    required this.plannedCount,
    required this.syncEnabled,
    required this.syncBusy,
    required this.syncSummary,
    required this.lastSyncAt,
    required this.unreadCount,
    required this.onTap,
  });

  final SharedSpace space;
  final SharedRole role;
  final int contentCount;
  final int taskCount;
  final int plannedCount;
  final bool syncEnabled;
  final bool syncBusy;
  final SharedSpaceSyncSummary? syncSummary;
  final int? lastSyncAt;
  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      child: Icon(Icons.group_work_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        space.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (unreadCount > 0) ...[
                      Badge(
                        label: Text(
                          unreadCount > 99 ? '99+' : '$unreadCount',
                        ),
                        child: const Icon(Icons.notifications_outlined),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Chip(label: Text(role.label)),
                  ],
                ),
                if (space.description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(space.description),
                ],
                const SizedBox(height: 10),
                _SpaceSyncBadge(
                  enabled: syncEnabled,
                  busy: syncBusy,
                  summary: syncSummary,
                  lastSyncAt: lastSyncAt,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    _TinyStat(
                      icon: Icons.description_outlined,
                      label: '$contentCount elementi',
                    ),
                    _TinyStat(
                      icon: Icons.check_circle_outline,
                      label: '$taskCount attività',
                    ),
                    _TinyStat(
                      icon: Icons.event_outlined,
                      label: '$plannedCount pianificati',
                    ),
                    _TinyStat(
                      icon: Icons.people_outline,
                      label: '${space.activeMembers.length} membri',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _ActivityFeedCard extends StatelessWidget {
  const _ActivityFeedCard({
    required this.events,
    required this.space,
    required this.notes,
    required this.identityId,
    required this.lastReadAt,
  });

  final List<SharedActivityEvent> events;
  final SharedSpace space;
  final List<Note> notes;
  final String identityId;
  final int lastReadAt;

  @override
  Widget build(BuildContext context) {
    final visible = events.take(10).toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ultima attività',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${events.length} eventi',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...visible.map((event) {
              final isUnread =
                  event.actorId != identityId && event.at > lastReadAt;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _activityIcon(event.kind),
                  size: 20,
                ),
                title: Text(
                  '${event.actorName} ${event.kind.label}'
                  '${_activitySubject(event, space, notes)}',
                  style: isUnread
                      ? const TextStyle(fontWeight: FontWeight.w700)
                      : null,
                ),
                subtitle: Text(_formatActivityTime(event.at)),
                trailing:
                    isUnread ? const Icon(Icons.fiber_new, size: 18) : null,
              );
            }),
          ],
        ),
      ),
    );
  }
}

IconData _activityIcon(SharedActivityKind kind) => switch (kind) {
      SharedActivityKind.spaceCreated => Icons.add_box_outlined,
      SharedActivityKind.spaceUpdated => Icons.tune,
      SharedActivityKind.contentAdded => Icons.add_link,
      SharedActivityKind.contentRemoved => Icons.link_off,
      SharedActivityKind.memberChanged => Icons.group_outlined,
      SharedActivityKind.documentUpdated => Icons.edit_note,
      SharedActivityKind.conflictPreserved => Icons.call_split,
    };

String _activitySubject(
  SharedActivityEvent event,
  SharedSpace space,
  List<Note> notes,
) {
  final id = event.subjectId;
  if (id == null) return '';
  if (event.kind == SharedActivityKind.memberChanged) {
    final members = space.members.where((member) => member.id == id);
    if (members.isNotEmpty) return ' · ${members.first.displayName}';
    return '';
  }
  final matching = notes.where((note) => note.id == id);
  if (matching.isEmpty) return '';
  final title = matching.first.title.trim();
  return title.isEmpty ? ' · Senza titolo' : ' · $title';
}

String _formatActivityTime(int millis) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day/$month · $hour:$minute';
}

class _SpaceSyncBadge extends StatelessWidget {
  const _SpaceSyncBadge({
    required this.enabled,
    required this.busy,
    required this.summary,
    required this.lastSyncAt,
  });

  final bool enabled;
  final bool busy;
  final SharedSpaceSyncSummary? summary;
  final int? lastSyncAt;

  @override
  Widget build(BuildContext context) {
    final label = !enabled
        ? 'Live Sync disattivato'
        : busy
            ? 'Sincronizzazione…'
            : summary?.label ?? 'Non ancora sincronizzato';
    final icon = !enabled
        ? Icons.cloud_off_outlined
        : busy
            ? Icons.sync
            : summary?.hasAttention == true
                ? Icons.warning_amber_rounded
                : Icons.cloud_done_outlined;
    final suffix = enabled && !busy && lastSyncAt != null
        ? ' · ${_formatCompactSyncTime(lastSyncAt!)}'
        : '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            '$label$suffix',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _SpaceSyncStatusCard extends StatelessWidget {
  const _SpaceSyncStatusCard({
    required this.enabled,
    required this.busy,
    required this.summary,
    required this.lastSyncAt,
    required this.onSync,
  });

  final bool enabled;
  final bool busy;
  final SharedSpaceSyncSummary? summary;
  final int? lastSyncAt;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(
            busy
                ? Icons.sync
                : summary?.hasAttention == true
                    ? Icons.warning_amber_rounded
                    : enabled
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
          ),
          title: Text(
            busy
                ? 'Shared Space in sincronizzazione…'
                : summary?.label ??
                    (enabled
                        ? 'In attesa del primo Live Sync'
                        : 'Live Sync disattivato'),
          ),
          subtitle: lastSyncAt == null
              ? const Text('Nessuna sincronizzazione completata.')
              : Text(_formatSyncTime(lastSyncAt!)),
          trailing: IconButton(
            tooltip: 'Sincronizza ora',
            onPressed: busy ? null : onSync,
            icon: const Icon(Icons.sync),
          ),
        ),
      );
}

String _formatCompactSyncTime(int millis) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class _SpaceHero extends StatelessWidget {
  const _SpaceHero({
    required this.space,
    required this.role,
  });

  final SharedSpace space;
  final SharedRole role;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EditorialEyebrow('SHARED SPACE'),
              Text(
                space.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (space.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(space.description),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(role.label)),
                  Chip(
                    avatar: const Icon(Icons.people_outline, size: 18),
                    label: Text('${space.activeMembers.length} membri'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.lock_outline, size: 18),
                    label: const Text('Selettivo'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.isSelf,
    required this.canManage,
    required this.isOwner,
    required this.onRole,
    required this.onRemove,
  });

  final SharedMember member;
  final bool isSelf;
  final bool canManage;
  final bool isOwner;
  final ValueChanged<SharedRole> onRole;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: CircleAvatar(
            child: Text(
              member.displayName.characters.first.toUpperCase(),
            ),
          ),
          title: Text(
            '${member.displayName}${isSelf ? ' · tu' : ''}',
          ),
          subtitle: Text(member.role.label),
          trailing: !canManage || isOwner
              ? null
              : PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'editor') {
                      onRole(SharedRole.editor);
                    } else if (value == 'viewer') {
                      onRole(SharedRole.viewer);
                    } else if (value == 'remove') {
                      onRemove();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'editor',
                      child: Text('Può modificare'),
                    ),
                    PopupMenuItem(
                      value: 'viewer',
                      child: Text('Solo lettura'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text('Rimuovi membro'),
                    ),
                  ],
                ),
        ),
      );
}

class _SyncInfoCard extends StatelessWidget {
  const _SyncInfoCard({
    required this.onExport,
    required this.onImport,
  });

  final Future<void> Function() onExport;
  final Future<void> Function() onImport;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EditorialEyebrow('COLLABORAZIONE 0.26'),
              const SizedBox(height: 4),
              Text(
                'Aggiornamenti portabili e verificati',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Esporta o importa un pacchetto dello spazio. Include solo i contenuti condivisi e i loro allegati, con controlli di integrità.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onExport,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Esporta'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onImport,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Importa'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _EmptySpaces extends StatelessWidget {
  const _EmptySpaces({
    required this.onCreate,
    required this.onJoin,
  });

  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.group_work_outlined, size: 42),
              const SizedBox(height: 10),
              Text(
                'Nessuno spazio condiviso',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text(
                'Crea uno spazio oppure usa un invito ricevuto.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: onCreate,
                    child: const Text('Crea spazio'),
                  ),
                  OutlinedButton(
                    onPressed: onJoin,
                    child: const Text('Usa invito'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _EmptyContent extends StatelessWidget {
  const _EmptyContent({
    required this.canEdit,
    required this.onAdd,
    required this.onCreate,
  });

  final bool canEdit;
  final VoidCallback onAdd;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.lock_open_outlined, size: 34),
              const SizedBox(height: 8),
              Text(
                'Lo spazio è vuoto',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                canEdit
                    ? 'Aggiungi una nota esistente o creane una direttamente qui.'
                    : 'Nessun contenuto è stato ancora condiviso.',
                textAlign: TextAlign.center,
              ),
              if (canEdit) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: onAdd,
                      child: const Text('Aggiungi esistente'),
                    ),
                    FilledButton(
                      onPressed: onCreate,
                      child: const Text('Nuova nota'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      );
}

class _TinyStat extends StatelessWidget {
  const _TinyStat({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(message),
        ),
      );
}

IconData _noteIcon(Note note) {
  if (note.isTask) {
    return Icons.check_circle_outline;
  }
  if (note.visualKind == VisualDocumentKind.sketch) {
    return Icons.draw_outlined;
  }
  if (note.visualKind == VisualDocumentKind.whiteboard) {
    return Icons.account_tree_outlined;
  }
  return Icons.description_outlined;
}

String _noteKind(Note note) {
  if (note.isTask) {
    final task = TaskDetails.tryDecode(note.taskJson);
    final planned = task?.plannedDate;
    final due = task?.due;
    if (planned != null) {
      return 'Attività · pianificata $planned';
    }
    if (due != null) {
      return 'Attività · scadenza $due';
    }
    return 'Attività';
  }
  if (note.visualKind == VisualDocumentKind.sketch) {
    return 'Disegno';
  }
  if (note.visualKind == VisualDocumentKind.whiteboard) {
    return 'Lavagna / Mind Map';
  }
  return 'Nota';
}
