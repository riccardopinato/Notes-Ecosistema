import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'domain/attachments.dart';
import 'domain/backup.dart';
import 'domain/diary.dart';
import 'domain/media_bundle.dart';
import 'domain/markdown_interop.dart';
import 'domain/markdown_folder_mirror.dart';
import 'domain/note.dart';
import 'domain/planner.dart';
import 'domain/shared_space_bundle.dart';
import 'domain/shared_spaces.dart';
import 'domain/sync.dart';
import 'domain/quick_capture.dart';
import 'domain/quick_switcher.dart';
import 'domain/templates.dart';
import 'domain/visual_documents.dart';
import 'platform/quick_capture_bridge.dart';
import 'platform/quick_sync_bridge.dart';
import 'platform/shared_background_bridge.dart';
import 'platform/reminder_action_bridge.dart';
import 'platform/reminder_bridge.dart';
import 'screens/diary_screen.dart';
import 'screens/editor_screen.dart';
import 'screens/github_sync_screen.dart';
import 'screens/home_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/planner_screen.dart';
import 'screens/shared_spaces_screen.dart';
import 'screens/sketch_screen.dart';
import 'screens/templates_screen.dart';
import 'screens/whiteboard_screen.dart';
import 'state/shared_live_sync_controller.dart';
import 'state/shared_spaces_controller.dart';
import 'state/workspace_controller.dart';
import 'sync/github_sync_service.dart';
import 'theme/notes_theme.dart';
import 'widgets/editorial.dart';
import 'widgets/quick_switcher_sheet.dart';

class NotesEcosistemaApp extends ConsumerStatefulWidget {
  const NotesEcosistemaApp({super.key});

  @override
  ConsumerState<NotesEcosistemaApp> createState() => _NotesEcosistemaAppState();
}

class _NotesEcosistemaAppState extends ConsumerState<NotesEcosistemaApp> {
  bool _dark = false;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('it_IT');
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _dark = prefs.getBool('dark_mode') ?? false);
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Notes Ecosistema',
        debugShowCheckedModeBanner: false,
        theme: NotesTheme.light(),
        darkTheme: NotesTheme.dark(),
        themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
        home: WorkspaceShell(
          dark: _dark,
          onDarkChanged: (value) async {
            setState(() => _dark = value);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('dark_mode', value);
          },
        ),
      );
}

class WorkspaceShell extends ConsumerStatefulWidget {
  const WorkspaceShell({
    required this.dark,
    required this.onDarkChanged,
    super.key,
  });

  final bool dark;
  final ValueChanged<bool> onDarkChanged;

  @override
  ConsumerState<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends ConsumerState<WorkspaceShell>
    with WidgetsBindingObserver {
  int _index = 0;
  String _query = '';
  String? _libraryCollectionId;
  String? _plannerTaskId;
  String _reminderSignature = '';

  static const labels = [
    'Home',
    'Note',
    'Diario',
    'Attività',
    'Spazi',
    'Cerca'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      QuickCaptureBridge.initialize(_handleIncomingCapture);
      QuickSyncBridge.initialize(_handleQuickSync);
      SharedBackgroundBridge.initialize(_handleSharedBackgroundSpace);
      ReminderActionBridge.initialize(_handleReminderAction);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(
      ref.read(sharedLiveSyncProvider.notifier).syncOnForeground(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _handleSharedBackgroundSpace(String spaceId) async {
    if (!mounted) return;
    setState(() => _index = 4);

    await ref.read(sharedLiveSyncProvider.notifier).syncNow(silent: true);
    if (!mounted) return;

    final shared = ref.read(sharedSpacesProvider);
    final identity = shared.identity;
    final space = shared.byId(spaceId);
    if (identity == null || space == null || !space.canRead(identity.id)) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SharedSpaceDetailScreen(
          spaceId: spaceId,
          onOpenNote: _openSharedItem,
          onCreateNote: _createSharedNote,
          onCreateTask: _createSharedTask,
          onExportBundle: _exportSharedSpaceBundle,
          onImportBundle: _importSharedSpaceBundle,
        ),
      ),
    );
  }

  Future<void> _handleReminderAction(ReminderAction action) async {
    if (!mounted) return;

    if (action.action == 'open') {
      setState(() {
        _plannerTaskId = action.id;
        _index = 3;
      });
      return;
    }

    if (action.action != 'snooze' ||
        action.expectedAt == null ||
        action.nextAt == null) {
      return;
    }

    final changed = await ref.read(workspaceProvider.notifier).snoozeReminder(
          action.id,
          action.expectedAt!,
          action.nextAt!,
        );
    if (!mounted) return;

    if (changed) {
      await ReminderBridge.sync(ref.read(workspaceProvider).notes);
      if (!mounted) return;
      setState(() {
        _plannerTaskId = action.id;
        _index = 3;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Promemoria rinviato di 10 minuti.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Il promemoria è già cambiato: nessuna modifica applicata.',
          ),
        ),
      );
    }
  }

  Future<void> _handleQuickSync() async {
    if (!mounted) return;
    final service = GitHubSyncService(ref.read(databaseProvider));
    try {
      final connected = await service.loadStatus();
      if (!connected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'GitHub non collegato. Apri Impostazioni → GitHub Sync.'),
            ),
          );
        }
        return;
      }

      await service.run();
      await ref.read(workspaceProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(service.status.message)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.toString().replaceFirst('FormatException: ', ''),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleIncomingCapture(IncomingCapture capture) async {
    if (!mounted) return;

    if (capture.error != null && capture.error!.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(capture.error!)),
      );
      return;
    }

    try {
      var body = capture.seed.body;
      if (capture.seed.checklist && body.trim().isEmpty) {
        body = '- [ ] ';
      }

      if (capture.files.isNotEmpty) {
        final store = await AttachmentStore.open();
        for (final shared in capture.files.take(20)) {
          final file = File(shared.path);
          if (!await file.exists()) continue;
          final bytes = await file.readAsBytes();
          final type = Attachments.typeFromName(shared.name) ??
              switch (shared.mime.toLowerCase()) {
                'application/pdf' => AttachmentType.pdf,
                'image/png' => AttachmentType.png,
                'image/webp' => AttachmentType.webp,
                _ => AttachmentType.jpeg,
              };
          final key = await store.ingest(bytes, type);
          body = Attachments.append(body, key, shared.name);
          await file.delete().catchError((_) => file);
        }
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      await _openEditor(
        Note(
          id: const Uuid().v4(),
          title: capture.seed.title,
          body: body,
          favorite: false,
          createdAt: now,
          updatedAt: now,
          pinned: false,
          archived: false,
          tags: const [],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('FormatException: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _openEditor([
    Note? note,
    bool readOnly = false,
    bool autoRecord = false,
  ]) async {
    if (note?.isVisual == true) {
      await _openVisual(note!, readOnly: readOnly);
      return;
    }

    final collections = ref.read(workspaceProvider).collections;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          note: note,
          collections: collections,
          allNotes: ref.read(workspaceProvider).notes,
          readOnly: readOnly,
          autoRecord: autoRecord,
        ),
      ),
    );
    await ref.read(workspaceProvider.notifier).refresh();
  }

  Future<void> _openVisual(Note note, {bool readOnly = false}) async {
    if (note.visualKind == VisualDocumentKind.whiteboard) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WhiteboardScreen(
            note: note,
            onSave: (updated) =>
                ref.read(workspaceProvider.notifier).save(updated),
            readOnly: readOnly,
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SketchScreen(
            note: note,
            onSave: (updated) =>
                ref.read(workspaceProvider.notifier).save(updated),
            readOnly: readOnly,
          ),
        ),
      );
    }
    await ref.read(workspaceProvider.notifier).refresh();
  }

  Future<void> _openTemplates() async {
    final workspace = ref.read(workspaceProvider);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplatesScreen(
          notes: workspace.notes,
          onUse: (content) {
            Navigator.pop(context);
            _openTemplateDraft(content);
          },
          onEdit: (note) {
            Navigator.pop(context);
            _openEditor(note);
          },
        ),
      ),
    );
    await ref.read(workspaceProvider.notifier).refresh();
  }

  Future<void> _openTemplateDraft(TemplateContent content) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _openEditor(
      Note(
        id: const Uuid().v4(),
        title: content.title,
        body: content.body,
        favorite: false,
        createdAt: now,
        updatedAt: now,
        pinned: false,
        archived: false,
        tags: content.tags,
      ),
    );
  }

  Future<void> _createVisual({
    required VisualInfoKind kind,
    WhiteboardMode whiteboardMode = WhiteboardMode.freeform,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = const Uuid().v4();
    final note = kind == VisualInfoKind.sketch
        ? Note(
            id: id,
            title: 'Nuovo disegno',
            body: SketchCodec.encode(SketchDocument()),
            favorite: false,
            createdAt: now,
            updatedAt: now,
            pinned: false,
            archived: false,
            tags: const [],
            sketchJson: const VisualInfo(
              kind: VisualInfoKind.sketch,
            ).encode(),
          )
        : Note(
            id: id,
            title: whiteboardMode == WhiteboardMode.mindMap
                ? 'Nuova mind map'
                : 'Nuova lavagna',
            body: WhiteboardCodec.encode(
              WhiteboardOps.empty(whiteboardMode),
            ),
            favorite: false,
            createdAt: now,
            updatedAt: now,
            pinned: false,
            archived: false,
            tags: const [],
            sketchJson: const VisualInfo(
              kind: VisualInfoKind.whiteboard,
            ).encode(),
          );

    await ref.read(workspaceProvider.notifier).save(note);
    await _openVisual(note);
  }

  Future<void> _createDiaryEntry(
    DateTime date,
    String? collectionId,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final draft = Note(
      id: const Uuid().v4(),
      title: '',
      body: '',
      collectionId: collectionId,
      favorite: false,
      createdAt: now,
      updatedAt: now,
      pinned: false,
      archived: false,
      tags: Diary.datedTags(const [], date),
    );
    await _openEditor(draft);
  }

  Future<void> _openSharedItem(Note note, bool readOnly) async {
    if (note.isTask) {
      if (readOnly) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SharedTaskReadOnlyScreen(note: note),
          ),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlannerScreen(
            notes: ref.read(workspaceProvider).notes,
            initialTaskId: note.id,
            onSave: (updated) =>
                ref.read(workspaceProvider.notifier).save(updated),
            onTrash: (id) => ref.read(workspaceProvider.notifier).trash(id),
            onOpenNote: _openEditor,
          ),
        ),
      );
      await ref.read(workspaceProvider.notifier).refresh();
      await ref.read(sharedLiveSyncProvider.notifier).syncSoon();
      return;
    }
    await _openEditor(note, readOnly);
    if (!readOnly) {
      await ref.read(sharedLiveSyncProvider.notifier).syncSoon();
    }
  }

  Future<void> _createSharedNote(String spaceId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = const Uuid().v4();
    final draft = Note(
      id: id,
      title: '',
      body: '',
      favorite: false,
      createdAt: now,
      updatedAt: now,
      pinned: false,
      archived: false,
      tags: const [],
    );
    await _openEditor(draft);
    final saved = await ref.read(databaseProvider).loadNote(id);
    if (saved == null) return;
    await ref.read(sharedSpacesProvider.notifier).linkContent(spaceId, id);
    await ref.read(sharedLiveSyncProvider.notifier).syncSoon();
  }

  Future<void> _createSharedTask(String spaceId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final note = Note(
      id: const Uuid().v4(),
      title: 'Nuova attività',
      body: '',
      favorite: false,
      createdAt: now,
      updatedAt: now,
      pinned: false,
      archived: false,
      tags: const [],
      taskJson: TaskDetails.empty().encode(),
    );
    await ref.read(workspaceProvider.notifier).save(note);
    await ref.read(sharedSpacesProvider.notifier).linkContent(spaceId, note.id);
    final current = await ref.read(databaseProvider).loadNote(note.id);
    if (current != null && mounted) {
      await _openSharedItem(current, false);
    } else {
      await ref.read(sharedLiveSyncProvider.notifier).syncSoon();
    }
  }

  Future<void> _exportSharedSpaceBundle(SharedSpace space) async {
    try {
      final shared = ref.read(sharedSpacesProvider);
      final identity = shared.identity;
      if (identity == null || !space.canRead(identity.id)) {
        throw const FormatException(
          'Accesso allo spazio non disponibile.',
        );
      }

      final all = await ref.read(databaseProvider).syncDocuments();
      final documents = <String, SyncDocument>{};
      for (final id in space.contentIds) {
        final document = all[id];
        if (document == null) {
          throw const FormatException(
            'Uno degli elementi condivisi non è disponibile sul dispositivo.',
          );
        }
        documents[id] = document;
      }

      final store = await AttachmentStore.open();
      final bytes = await SharedSpaceBundle.encode(
        space: space,
        actor: identity,
        documents: documents,
        store: store,
      );

      var cleanName = space.name
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .toLowerCase();
      while (cleanName.startsWith('-')) {
        cleanName = cleanName.substring(1);
      }
      while (cleanName.endsWith('-')) {
        cleanName = cleanName.substring(0, cleanName.length - 1);
      }

      final now = DateTime.now();
      final stamp = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final baseName = cleanName.isEmpty ? 'notes' : cleanName;

      await FilePicker.platform.saveFile(
        dialogTitle: 'Esporta Shared Space',
        fileName: 'shared-space-$baseName-$stamp.zip',
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aggiornamento Shared Space esportato.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('FormatException: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _importSharedSpaceBundle() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw const FormatException(
          'Impossibile leggere il pacchetto Shared Space.',
        );
      }

      final preview = SharedSpaceBundle.decode(Uint8List.fromList(bytes));
      final shared = ref.read(sharedSpacesProvider);
      final identity = shared.identity;
      if (identity == null) {
        throw const FormatException(
          'Profilo collaborazione non disponibile.',
        );
      }
      final localSpace = shared.byId(preview.space.id);
      if (localSpace == null && !preview.space.canRead(identity.id)) {
        throw const FormatException(
          'Importa prima il codice invito di questo Shared Space.',
        );
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Importare “${preview.space.name}”?'),
          content: Text(
            'Pacchetto di ${preview.actor.displayName}: '
            '${preview.documents.length} elementi e '
            '${preview.assets.length} allegati. '
            'Le versioni locali più recenti non verranno sovrascritte.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Importa aggiornamento'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final store = await AttachmentStore.open();
      await SharedSpaceBundle.installAssets(preview, store);

      final database = ref.read(databaseProvider);
      final localDocuments = await database.syncDocuments();
      var downloaded = 0;
      var keptLocal = 0;
      var conflicts = 0;

      for (final remote in preview.documents.values) {
        final local = localDocuments[remote.id];
        if (local == null) {
          await database.applySyncDocument(remote);
          downloaded++;
          continue;
        }
        if (local == remote) continue;
        if (remote.updatedAt > local.updatedAt) {
          await database.applySyncDocument(remote);
          downloaded++;
        } else if (remote.updatedAt < local.updatedAt) {
          keptLocal++;
        } else {
          await database.saveSyncCopy(
            remote,
            suffix: ' (conflitto Shared Space)',
          );
          conflicts++;
        }
      }

      await ref
          .read(sharedSpacesProvider.notifier)
          .mergeRemoteSpace(preview.space);
      await ref.read(workspaceProvider.notifier).refresh();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Shared Space aggiornato · ricevuti $downloaded · '
            'locali mantenuti $keptLocal · conflitti $conflicts.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('FormatException: ', ''),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(sharedLiveSyncProvider);
    final workspace = ref.watch(workspaceProvider);
    final shared = ref.watch(sharedSpacesProvider);
    final section = labels[_index];

    final editableSharedIds = <String>{};
    final viewerSharedIds = <String>{};
    final identity = shared.identity;
    if (identity != null) {
      for (final space in shared.spaces) {
        final role = space.roleFor(identity.id);
        if (role == null) continue;
        if (role.canEdit) {
          editableSharedIds.addAll(space.contentIds);
        } else {
          viewerSharedIds.addAll(space.contentIds);
        }
      }
    }
    final viewerOnlyIds = viewerSharedIds.difference(editableSharedIds);
    final personalNotes = workspace.notes
        .where((note) => !viewerOnlyIds.contains(note.id))
        .toList(growable: false);

    if (!workspace.loading) {
      final reminderSignature = personalNotes
          .where((note) => note.isTask)
          .map(
            (note) =>
                '${note.id}|${note.title}|${note.taskJson}|${note.deletedAt}|${note.archived}',
          )
          .join('\n');
      if (reminderSignature != _reminderSignature) {
        _reminderSignature = reminderSignature;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ReminderBridge.sync(personalNotes).catchError((_) {});
          }
        });
      }
    }

    Widget body;
    if (workspace.loading && workspace.notes.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (workspace.error != null && workspace.notes.isEmpty) {
      body = _ErrorState(
        onRetry: () => ref.read(workspaceProvider.notifier).refresh(),
      );
    } else if (_index == 0) {
      body = HomeScreen(
        notes: personalNotes,
        collections: workspace.collections,
        onCreate: _openEditor,
        onNotes: () => setState(() {
          _libraryCollectionId = null;
          _index = 1;
        }),
        onAgenda: () => setState(() => _index = 3),
        onTasks: () => setState(() => _index = 3),
        onSketch: () => _createVisual(kind: VisualInfoKind.sketch),
        onCollection: (id) => setState(() {
          _libraryCollectionId = id;
          _index = 1;
        }),
        onOpenNote: _openEditor,
        sharedUnread: identity == null ? 0 : live.totalUnread(identity.id),
      );
    } else if (_index == 1 || _index == 5) {
      body = NotesScreen(
        notes: personalNotes,
        collections: workspace.collections,
        query: _query,
        searchMode: _index == 5,
        onQueryChanged: (value) => setState(() => _query = value),
        onOpen: _openEditor,
        onFavorite: (id) => ref.read(workspaceProvider.notifier).favorite(id),
        onPin: (id, value) =>
            ref.read(workspaceProvider.notifier).pin(id, value),
        onArchive: (id, value) =>
            ref.read(workspaceProvider.notifier).archive(id, value),
        onTrash: (id) => ref.read(workspaceProvider.notifier).trash(id),
        onRestore: _restoreFromTrash,
        onDeleteForever: _deleteForever,
        onBulkEdit: (notes, change) =>
            ref.read(workspaceProvider.notifier).bulkEdit(notes, change),
        onRenameCollection: (collection, name) =>
            ref.read(workspaceProvider.notifier).renameCollection(
                  collection,
                  name,
                ),
        onDeleteCollection: (collection) =>
            ref.read(workspaceProvider.notifier).deleteEmptyCollection(
                  collection,
                ),
        initialCollectionId: _index == 1 ? _libraryCollectionId : null,
      );
    } else if (_index == 2) {
      body = DiaryScreen(
        notes: personalNotes,
        collections: workspace.collections,
        onOpen: _openEditor,
        onCreate: _createDiaryEntry,
        onOpenTask: (_) => setState(() => _index = 3),
        onCreateCollection: (name) =>
            ref.read(workspaceProvider.notifier).createCollection(name),
      );
    } else if (_index == 3) {
      body = PlannerScreen(
        notes: personalNotes,
        initialTaskId: _plannerTaskId,
        onSave: (note) => ref.read(workspaceProvider.notifier).save(note),
        onTrash: (id) => ref.read(workspaceProvider.notifier).trash(id),
        onOpenNote: _openEditor,
      );
    } else {
      body = SharedSpacesScreen(
        onOpenNote: _openSharedItem,
        onCreateNote: _createSharedNote,
        onCreateTask: _createSharedTask,
        onExportBundle: _exportSharedSpaceBundle,
        onImportBundle: _importSharedSpaceBundle,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: EditorialAppTitle(section == 'Home' ? 'Il tuo spazio' : section),
        actions: [
          IconButton(
            tooltip: 'Quick Switcher',
            onPressed: () => _quickSwitcher(personalNotes),
            icon: const Icon(Icons.bolt_outlined),
          ),
          IconButton(
            tooltip: 'Impostazioni',
            onPressed: () => _settings(context),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: body,
      floatingActionButton:
          (_index == 5 || _index == 4 || _index == 2 || _index == 3)
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _createMenu(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Crea'),
                ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() {
          if (value == 1) _libraryCollectionId = null;
          if (value != 3) _plannerTaskId = null;
          _index = value;
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.description), label: 'Note'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month), label: 'Diario'),
          NavigationDestination(
              icon: Icon(Icons.check_circle), label: 'Attività'),
          NavigationDestination(
              icon: Icon(Icons.group_work_outlined), label: 'Spazi'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Cerca'),
        ],
      ),
    );
  }

  Future<void> _quickSwitcher(List<Note> notes) async {
    final workspace = ref.read(workspaceProvider);
    final selected = await showQuickSwitcher(
      context: context,
      notes: notes,
      collections: workspace.collections,
    );
    if (selected == null || !mounted) return;

    switch (selected.kind) {
      case QuickSwitcherKind.note:
        final note = notes.where((item) => item.id == selected.id).firstOrNull;
        if (note != null) await _openEditor(note);
        break;
      case QuickSwitcherKind.task:
        setState(() {
          _plannerTaskId = selected.id;
          _index = 3;
        });
        break;
      case QuickSwitcherKind.collection:
        setState(() {
          _libraryCollectionId = selected.id;
          _index = 1;
        });
        break;
      case QuickSwitcherKind.command:
        switch (selected.id) {
          case 'today':
            setState(() => _index = 0);
            break;
          case 'new-note':
            await _openEditor();
            break;
          case 'tasks':
            setState(() => _index = 3);
            break;
          case 'search':
            setState(() => _index = 5);
            break;
        }
        break;
    }
  }

  Future<void> _createMenu(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.note_add),
              title: const Text('Nuova nota'),
              onTap: () => Navigator.pop(context, 'note'),
            ),
            ListTile(
              leading: const Icon(Icons.mic_none),
              title: const Text('Nota vocale'),
              subtitle: const Text('Conserva l’audio originale nella nota'),
              onTap: () => Navigator.pop(context, 'voice'),
            ),
            ListTile(
              leading: const Icon(Icons.today),
              title: const Text('Diario di oggi'),
              onTap: () => Navigator.pop(context, 'diary'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Nuova attività'),
              onTap: () => Navigator.pop(context, 'task'),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_customize),
              title: const Text('Modelli'),
              onTap: () => Navigator.pop(context, 'templates'),
            ),
            ListTile(
              leading: const Icon(Icons.draw),
              title: const Text('Nuovo disegno'),
              onTap: () => Navigator.pop(context, 'sketch'),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text('Nuova lavagna'),
              onTap: () => Navigator.pop(context, 'board'),
            ),
            ListTile(
              leading: const Icon(Icons.account_tree),
              title: const Text('Nuova mind map'),
              onTap: () => Navigator.pop(context, 'mind'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'note') {
      await _openEditor();
    } else if (action == 'voice') {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _openEditor(
        Note(
          id: const Uuid().v4(),
          title: 'Nota vocale',
          body: '',
          favorite: false,
          createdAt: now,
          updatedAt: now,
          pinned: false,
          archived: false,
          tags: const ['voice-source'],
        ),
        false,
        true,
      );
    } else if (action == 'diary') {
      await _createDiaryEntry(DateTime.now(), null);
    } else if (action == 'task') {
      setState(() => _index = 3);
    } else if (action == 'templates') {
      await _openTemplates();
    } else if (action == 'sketch') {
      await _createVisual(kind: VisualInfoKind.sketch);
    } else if (action == 'board') {
      await _createVisual(kind: VisualInfoKind.whiteboard);
    } else if (action == 'mind') {
      await _createVisual(
        kind: VisualInfoKind.whiteboard,
        whiteboardMode: WhiteboardMode.mindMap,
      );
    } else {
      _showPending(action);
    }
  }

  void _showPending(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature: porting Flutter in corso.')),
    );
  }

  Future<void> _syncMarkdownFolder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var path = prefs.getString('markdown_mirror_path');
      path ??= await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Scegli cartella Markdown',
      );
      if (path == null || path.trim().isEmpty) return;
      await prefs.setString('markdown_mirror_path', path);

      final snapshot = await ref.read(workspaceProvider.notifier).snapshot();
      final result = await MarkdownFolderMirror.sync(path, snapshot.notes);
      for (final note in result.updatedNotes) {
        await ref.read(workspaceProvider.notifier).save(note);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cartella Markdown sincronizzata: ${result.writtenFiles} file scritti, '
            '${result.updatedNotes.length} aggiornamenti esterni, '
            '${result.conflicts} conflitti preservati.',
          ),
          action: SnackBarAction(
            label: 'Cambia cartella',
            onPressed: () async {
              final settings = await SharedPreferences.getInstance();
              await settings.remove('markdown_mirror_path');
            },
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('FormatException: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _exportMarkdownWorkspace() async {
    try {
      final snapshot = await ref.read(workspaceProvider.notifier).snapshot();
      final bytes = MarkdownWorkspaceBundle.encode(snapshot.notes);
      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      await FilePicker.platform.saveFile(
        dialogTitle: 'Esporta workspace Markdown',
        fileName: 'notes-markdown-$stamp.zip',
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workspace Markdown esportato senza lock-in.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('FormatException: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _importMarkdownWorkspace() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw const FormatException('Impossibile leggere l’archivio Markdown.');
      }
      final documents = MarkdownWorkspaceBundle.decode(
        Uint8List.fromList(bytes),
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Importare Markdown?'),
          content: Text(
            'Verranno create ${documents.length} copie locali. '
            'Nessuna nota esistente verrà sovrascritta.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Importa copie'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final notifier = ref.read(workspaceProvider.notifier);
      var stamp = DateTime.now().millisecondsSinceEpoch;
      for (final document in documents) {
        await notifier.save(
          Note(
            id: const Uuid().v4(),
            title: document.title,
            body: document.body,
            favorite: false,
            createdAt: stamp,
            updatedAt: stamp,
            pinned: false,
            archived: false,
            tags: const ['import-markdown'],
          ),
        );
        stamp++;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${documents.length} documenti Markdown importati.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('FormatException: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _exportBackup() async {
    try {
      final snapshot = await ref.read(workspaceProvider.notifier).snapshot();
      final store = await AttachmentStore.open();
      final bytes = await MediaBundle.encode(snapshot, store);
      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await FilePicker.platform.saveFile(
        dialogTitle: 'Esporta backup completo Notes',
        fileName: 'notes-ecosistema-$stamp.zip',
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backup completo esportato con allegati.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('FormatException: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _exportLegacyJson() async {
    try {
      final snapshot = await ref.read(workspaceProvider.notifier).snapshot();
      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await FilePicker.platform.saveFile(
        dialogTitle: 'Esporta backup JSON Notes',
        fileName: 'notes-ecosistema-$stamp.json',
        bytes: backupUtf8(snapshot),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup JSON esportato.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('FormatException: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['zip', 'json'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw const FormatException('Impossibile leggere il backup.');
      }

      final isZip = file.extension?.toLowerCase() == 'zip';
      late final BackupSnapshot snapshot;
      MediaBundlePreview? bundle;
      if (isZip) {
        bundle = MediaBundle.decode(Uint8List.fromList(bytes));
        snapshot = bundle.snapshot;
      } else {
        snapshot = BackupCodec.decode(
          utf8.decode(bytes, allowMalformed: false),
        );
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Importare il backup?'),
          content: Text(
            'Verranno create copie separate: '
            '${snapshot.notes.length} elementi, '
            '${snapshot.collections.length} raccolte e '
            '${snapshot.drafts.length} bozze.'
            '${bundle == null ? '' : ' Il pacchetto include ${bundle.assets.length} allegati.'} '
            'I dati esistenti non verranno sovrascritti.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Importa copie'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      if (bundle != null) {
        final store = await AttachmentStore.open();
        await MediaBundle.installAssets(bundle, store);
      }
      await ref.read(workspaceProvider.notifier).importCopies(snapshot);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            bundle == null
                ? 'Backup JSON importato come copie.'
                : 'Backup completo importato con allegati.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('FormatException: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _restoreFromTrash(String id) async {
    await ref.read(workspaceProvider.notifier).restore(id);
  }

  Future<void> _deleteForever(String id) async {
    final shared = ref.read(sharedSpacesProvider);
    final identity = shared.identity;
    final linkedSpaces = shared.spaces
        .where((space) => space.contentIds.contains(id))
        .toList(growable: false);

    if (linkedSpaces.isNotEmpty) {
      if (identity == null) {
        throw const FormatException(
          'Impossibile verificare i permessi dello Shared Space.',
        );
      }
      for (final space in linkedSpaces) {
        final role = space.roleFor(identity.id);
        if (role == null || !role.canEdit) {
          throw const FormatException(
            'Questo elemento è ancora condiviso in uno spazio che non puoi modificare. '
            'Rimuovilo dallo spazio prima dell’eliminazione definitiva.',
          );
        }
      }
      for (final space in linkedSpaces) {
        await ref
            .read(sharedSpacesProvider.notifier)
            .unlinkContent(space.id, id);
      }
    }

    await ref.read(workspaceProvider.notifier).deleteForever(id);
    await ref.read(propertyStoreProvider).deleteValuesForNote(id);
    await ref.read(knowledgeStoreProvider).deleteForNote(id);
    await _cleanupAttachments(silent: true);
    if (linkedSpaces.isNotEmpty) {
      await ref.read(sharedLiveSyncProvider.notifier).syncSoon();
    }
  }

  Future<void> _cleanupAttachments({bool silent = false}) async {
    try {
      final snapshot = await ref.read(workspaceProvider.notifier).snapshot();
      final referenced = <String>{};
      for (final note in snapshot.notes) {
        if (!note.isVisual) {
          referenced.addAll(
            Attachments.refs(note.body).map((ref) => ref.key),
          );
        }
      }
      for (final draft in snapshot.drafts) {
        referenced.addAll(
          Attachments.refs(draft.body).map((ref) => ref.key),
        );
      }

      final store = await AttachmentStore.open();
      final result = await store.cleanup(referenced);
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.files == 0
                ? 'Nessun allegato orfano trovato.'
                : 'Rimossi ${result.files} allegati orfani '
                    '(${(result.bytes / 1024 / 1024).toStringAsFixed(1)} MiB).',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('FormatException: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _settings(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EditorialAppTitle('Impostazioni'),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Tema scuro'),
                  value: widget.dark,
                  onChanged: widget.onDarkChanged,
                ),
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('Esporta backup completo'),
                  subtitle: const Text(
                    'ZIP con note, attività, disegni, lavagne e allegati.',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _exportBackup();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Importa backup'),
                  subtitle: const Text(
                      'Importa come copie senza sovrascrivere i dati attuali.'),
                  onTap: () {
                    Navigator.pop(context);
                    _importBackup();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_sync_outlined),
                  title: const Text('Sincronizza cartella Markdown'),
                  subtitle: const Text(
                    'Mirror interoperabile con protezione dei cambi esterni e conflitti.',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _syncMarkdownFolder();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.text_snippet_outlined),
                  title: const Text('Esporta workspace Markdown'),
                  subtitle: const Text(
                    'ZIP con file .md leggibili anche fuori da Notes.',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _exportMarkdownWorkspace();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.drive_folder_upload_outlined),
                  title: const Text('Importa Markdown'),
                  subtitle: const Text(
                    'Importa un export Markdown come copie, senza sovrascrivere.',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _importMarkdownWorkspace();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.data_object),
                  title: const Text('Esporta JSON compatibile'),
                  subtitle: const Text(
                    'Backup v6 senza file multimediali, per compatibilità Kotlin.',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _exportLegacyJson();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('Pulisci allegati orfani'),
                  subtitle: const Text(
                    'Rimuove solo file locali non più referenziati da note o bozze.',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _cleanupAttachments();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: const Text('Scorciatoia Nuova nota'),
                  subtitle: const Text(
                    'Aggiunge alla Home un accesso diretto al Quick Capture.',
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final requested =
                        await QuickCaptureBridge.pinNoteShortcut();
                    if (!mounted) return;
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text(
                          requested
                              ? 'Richiesta scorciatoia inviata alla Home.'
                              : 'Launcher non compatibile: tieni premuta l’icona di Notes.',
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.widgets_outlined),
                  title: const Text('Aggiungi widget Quick Capture'),
                  subtitle: const Text(
                    'Widget Home con Nuova nota e Checklist.',
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final requested =
                        await QuickCaptureBridge.pinCaptureWidget();
                    if (!mounted) return;
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text(
                          requested
                              ? 'Richiesta widget inviata alla Home.'
                              : 'Apri il selettore Widget Android e cerca Notes.',
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_sync_outlined),
                  title: const Text('GitHub Sync'),
                  subtitle: const Text(
                    'Sincronizza note e allegati con un repository GitHub.',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(this.context).push(
                      MaterialPageRoute(
                        builder: (_) => GitHubSyncScreen(
                          database: ref.read(databaseProvider),
                          onLocalChanged: () =>
                              ref.read(workspaceProvider.notifier).refresh(),
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Notifiche promemoria'),
                  subtitle: const Text(
                    'Abilita le notifiche Android per i promemoria delle attività.',
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final allowed = await ReminderBridge.requestPermission();
                    if (!mounted) return;
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text(
                          allowed
                              ? 'Notifiche promemoria abilitate.'
                              : 'Notifiche non abilitate. I promemoria restano salvati.',
                        ),
                        action: allowed
                            ? null
                            : SnackBarAction(
                                label: 'Impostazioni',
                                onPressed: () {
                                  ReminderBridge.openSettings();
                                },
                              ),
                      ),
                    );
                  },
                ),
                const ListTile(
                  title: Text('Notes · Flutter 0.35.0'),
                  subtitle: Text(
                    'Shared Spaces selettivi · database locale ancora compatibile con Room v8.',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(28),
        children: [
          const Icon(Icons.error_outline, size: 42),
          const SizedBox(height: 12),
          Text(
            'Database non disponibile.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Il port Flutter non ha modificato i dati. Riprova ad aprire il database locale.',
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Riprova')),
        ],
      );
}
